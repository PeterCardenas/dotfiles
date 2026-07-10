from __future__ import annotations

from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import threading
from typing import TextIO


_SPINNER_FRAMES = ("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")


@dataclass(frozen=True)
class DelegateArgs:
    max_budget_usd: str
    query: str
    output_mode: str = "auto"


def build_claude_command(
    *,
    allowed_tools: Sequence[str],
    prompt: str,
    max_budget_usd: str = "1",
    output_format: str = "json",
    include_partial_messages: bool = False,
) -> list[str]:
    if not allowed_tools:
        raise ValueError("at least one allowed tool is required")
    if not prompt.strip():
        raise ValueError("prompt must not be empty")
    if output_format not in {"json", "stream-json"}:
        raise ValueError("output format must be json or stream-json")

    command = [
        "claude",
        "-p",
        "--setting-sources",
        "project,local",
        "--output-format",
        output_format,
        "--no-session-persistence",
        "--max-budget-usd",
        max_budget_usd,
        "--allowedTools",
        ",".join(allowed_tools),
    ]
    if output_format == "stream-json":
        command.append("--verbose")
        if include_partial_messages:
            command.append("--include-partial-messages")
    command.extend(["--", prompt])
    return command


def parse_delegate_args(argv: Sequence[str], program: str) -> DelegateArgs:
    max_budget_usd = "1"
    output_mode = "auto"
    remaining = list(argv)

    if not remaining or remaining[0] in {"--help", "-h"}:
        _print_usage(program)
        raise SystemExit(0 if remaining else 2)

    while remaining:
        option = remaining[0]
        if option == "--max-budget-usd":
            if len(remaining) < 2:
                _print_usage(program)
                raise SystemExit(2)
            max_budget_usd = remaining[1]
            remaining = remaining[2:]
            continue
        if option == "--json":
            if output_mode != "auto":
                _print_usage(program)
                raise SystemExit(2)
            output_mode = "json"
            remaining = remaining[1:]
            continue
        if option == "--human":
            if output_mode != "auto":
                _print_usage(program)
                raise SystemExit(2)
            output_mode = "human"
            remaining = remaining[1:]
            continue
        if option.startswith("--"):
            _print_usage(program)
            raise SystemExit(2)
        break

    query = " ".join(remaining).strip()
    if not query:
        _print_usage(program)
        raise SystemExit(2)

    return DelegateArgs(
        max_budget_usd=max_budget_usd, query=query, output_mode=output_mode
    )


def choose_output_mode(
    requested_output_mode: str,
    stdout: TextIO,
    env: Mapping[str, str] | None = None,
) -> str:
    if requested_output_mode in {"json", "human"}:
        return requested_output_mode
    if requested_output_mode != "auto":
        raise ValueError("output mode must be auto, json, or human")
    if is_agent_environment(env):
        return "json"
    return "human" if stdout.isatty() else "json"


def is_agent_environment(env: Mapping[str, str] | None = None) -> bool:
    active_env = os.environ if env is None else env
    agent_markers = (
        "AGENT",
        "AI_AGENT",
        "CLAUDE_CODE",
        "CLAUDE_CODE_CHILD_SESSION",
        "CLAUDECODE",
        "CURSOR_AGENT",
    )
    if any(_truthy_env(active_env, marker) for marker in agent_markers):
        return True
    return active_env.get("CURSOR_EXTENSION_HOST_ROLE") == "agent-exec"


def run_delegate(
    *,
    allowed_tools: Sequence[str],
    prompt: str,
    max_budget_usd: str,
    output_mode: str = "auto",
    stdout: TextIO | None = None,
    stderr: TextIO | None = None,
) -> int:
    stdout = sys.stdout if stdout is None else stdout
    stderr = sys.stderr if stderr is None else stderr

    if shutil.which("claude") is None:
        print("connector delegate: missing dependency: claude", file=stderr)
        return 127

    resolved_output_mode = choose_output_mode(output_mode, stdout)
    if resolved_output_mode == "human" and importlib.util.find_spec("rich") is None:
        print("connector delegate: missing dependency: rich", file=stderr)
        return 127
    output_format = "stream-json" if resolved_output_mode == "human" else "json"
    command = build_claude_command(
        allowed_tools=allowed_tools,
        prompt=_human_prompt(prompt) if resolved_output_mode == "human" else prompt,
        max_budget_usd=max_budget_usd,
        output_format=output_format,
        include_partial_messages=resolved_output_mode == "human",
    )
    if resolved_output_mode == "human":
        return _run_human_delegate(
            command,
            markdown_stream=_MarkdownStream(stdout),
            stdout=stdout,
            stderr=stderr,
        )

    result = subprocess.run(command, stdin=subprocess.DEVNULL, check=False)
    return result.returncode


def run_entrypoint(
    *,
    argv: Sequence[str],
    program: str,
    allowed_tools: Sequence[str],
    build_prompt: Callable[[str], str],
) -> int:
    args = parse_delegate_args(argv, program)
    return run_delegate(
        allowed_tools=allowed_tools,
        prompt=build_prompt(args.query),
        max_budget_usd=args.max_budget_usd,
        output_mode=args.output_mode,
    )


def _print_usage(program: str) -> None:
    print(
        f"Usage: {program} [--json|--human] [--max-budget-usd <amount>] <query>",
        file=sys.stderr,
    )


def _truthy_env(env: Mapping[str, str], name: str) -> bool:
    value = env.get(name)
    return value is not None and value.lower() not in {"", "0", "false", "no", "off"}


def _human_prompt(prompt: str) -> str:
    return (
        "Do not emit preambles, plans, progress narration, or commentary before "
        "or between tool calls. Put reasoning in thinking blocks. Emit visible "
        "text only once, as the final Markdown response after all tool calls. "
        "Begin the final response with exactly `# Summary`. " + prompt
    )


def _spinner_frame(state: str, frame_index: int) -> str:
    return f"\r\033[2K{_SPINNER_FRAMES[frame_index % len(_SPINNER_FRAMES)]} {state}"


class _StatusUpdater:
    def __init__(self, output: TextIO) -> None:
        self._output = output
        self._state = ""
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self, state: str) -> None:
        self.update(state)
        if self._output.isatty():
            self._thread = threading.Thread(target=self._spin, daemon=True)
            self._thread.start()

    def update(self, state: str) -> None:
        if self._stop.is_set():
            return
        with self._lock:
            if state == self._state:
                return
            self._state = state
        if not self._output.isatty():
            print(f"{state}...", file=self._output, flush=True)

    def stop(self) -> None:
        if self._stop.is_set():
            return
        self._stop.set()
        if self._thread is not None:
            self._thread.join()
            self._thread = None
            self._output.write("\r\033[2K")
            self._output.flush()

    def finish(self, state: str) -> None:
        self.stop()
        if self._output.isatty():
            print(f"✓ {state}", file=self._output, flush=True)
        else:
            print(f"{state}.", file=self._output, flush=True)

    def _spin(self) -> None:
        frame_index = 0
        while not self._stop.wait(0.08):
            with self._lock:
                state = self._state
            self._output.write(_spinner_frame(state, frame_index))
            self._output.flush()
            frame_index += 1


class _MarkdownStream:
    def __init__(self, output: TextIO) -> None:
        from rich.console import Console
        from rich.live import Live

        self._markdown = ""
        self._live = Live(
            console=Console(file=output, force_terminal=output.isatty()),
            auto_refresh=False,
            vertical_overflow="ellipsis",
        )

    def start(self) -> None:
        self._live.start(refresh=True)

    def append(self, text: str) -> None:
        from rich.markdown import Markdown

        self._markdown += text
        self._live.update(Markdown(self._markdown), refresh=True)

    def stop(self) -> None:
        self._live.stop()


def _run_human_delegate(
    command: Sequence[str],
    *,
    markdown_stream: _MarkdownStream,
    stdout: TextIO,
    stderr: TextIO,
) -> int:
    status = _StatusUpdater(stderr)
    status.start("Starting connector delegate")
    process = subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        text=True,
    )
    result_was_error = False
    seen_tools: set[str] = set()
    duration = ""
    stream_started = False
    pending_text = ""

    if process.stdout is not None:
        for raw_line in process.stdout:
            event = _parse_stream_event(raw_line, stderr)
            if event is None:
                continue
            _update_stream_status(event, status, seen_tools)
            text_delta = _extract_text_delta(event)
            if text_delta and seen_tools:
                if not stream_started:
                    pending_text += text_delta
                    final_heading = re.search(r"(?m)^#{1,6} ", pending_text)
                    if final_heading is None:
                        continue
                    text_delta = pending_text[final_heading.start() :]
                    pending_text = ""
                    status.stop()
                    markdown_stream.start()
                    stream_started = True
                markdown_stream.append(text_delta)
            if event.get("type") == "result":
                result_was_error = bool(event.get("is_error"))
                duration = _format_duration(event.get("duration_ms"))

    return_code = process.wait()
    if stream_started:
        markdown_stream.stop()
    succeeded = return_code == 0 and not result_was_error
    status.finish(
        f"Done in {duration}"
        if succeeded and duration
        else "Done"
        if succeeded
        else "Failed"
    )
    if return_code == 0 and result_was_error:
        return 1
    return return_code


def _parse_stream_event(raw_line: str, stderr: TextIO) -> dict[str, object] | None:
    line = raw_line.strip()
    if not line:
        return None
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        print(f"connector delegate: ignored non-json stream line: {line}", file=stderr)
        return None
    if not isinstance(event, dict):
        return None
    return event


def _extract_text_delta(event: dict[str, object]) -> str:
    if event.get("type") != "stream_event":
        return ""
    stream_event = event.get("event")
    if not isinstance(stream_event, dict):
        return ""
    if stream_event.get("type") != "content_block_delta":
        return ""
    delta = stream_event.get("delta")
    if not isinstance(delta, dict) or delta.get("type") != "text_delta":
        return ""
    text = delta.get("text")
    return text if isinstance(text, str) else ""


def _update_stream_status(
    event: dict[str, object], status: _StatusUpdater, seen_tools: set[str]
) -> None:
    event_type = event.get("type")
    if event_type == "system":
        _update_system_status(event, status)
        return
    if event_type == "assistant":
        _update_assistant_status(event, status, seen_tools)
        return
    if event_type == "stream_event":
        stream_event = event.get("event")
        if isinstance(stream_event, dict):
            _update_content_block_status(stream_event, status, seen_tools)


def _update_system_status(event: dict[str, object], status: _StatusUpdater) -> None:
    if event.get("subtype") == "init":
        session_id = str(event.get("session_id") or "")
        suffix = f" ({session_id[:12]})" if session_id else ""
        status.update(f"Connected to Claude{suffix}")
    elif event.get("subtype") == "api_retry":
        attempt = event.get("attempt")
        max_retries = event.get("max_retries")
        status.update(f"Retrying Claude API ({attempt}/{max_retries})")


def _update_assistant_status(
    event: dict[str, object], status: _StatusUpdater, seen_tools: set[str]
) -> None:
    message = event.get("message")
    if not isinstance(message, dict):
        return
    content = message.get("content")
    if not isinstance(content, list):
        return
    for block in content:
        if isinstance(block, dict):
            _update_content_status(block, status, seen_tools)


def _update_content_block_status(
    event: dict[str, object], status: _StatusUpdater, seen_tools: set[str]
) -> None:
    if event.get("type") != "content_block_start":
        return
    content_block = event.get("content_block")
    if isinstance(content_block, dict):
        _update_content_status(content_block, status, seen_tools)


def _update_content_status(
    block: dict[str, object], status: _StatusUpdater, seen_tools: set[str]
) -> None:
    block_type = block.get("type")
    if block_type == "thinking":
        status.update("Thinking")
        return
    if block_type == "text":
        return
    if block_type != "tool_use":
        return
    raw_name = block.get("name")
    if not isinstance(raw_name, str) or raw_name in seen_tools:
        return
    seen_tools.add(raw_name)
    status.update(f"Using {_format_tool_name(raw_name)}")


def _format_tool_name(raw_name: str) -> str:
    parts = raw_name.split("__")
    if len(parts) >= 3 and parts[0] == "mcp":
        server = parts[1].replace("claude_ai_", "").replace("_", " ")
        tool = parts[-1].replace("_", " ")
        return f"{server} {tool}".strip()
    return raw_name.replace("_", " ")


def _format_duration(raw_duration_ms: object) -> str:
    if not isinstance(raw_duration_ms, int | float):
        return ""
    seconds = raw_duration_ms / 1000
    return f"{seconds:.1f}s"
