from __future__ import annotations

from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
import json
import os
import shutil
import subprocess
import sys
from typing import TextIO


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

    return DelegateArgs(max_budget_usd=max_budget_usd, query=query, output_mode=output_mode)


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
    output_format = "stream-json" if resolved_output_mode == "human" else "json"
    command = build_claude_command(
        allowed_tools=allowed_tools,
        prompt=prompt,
        max_budget_usd=max_budget_usd,
        output_format=output_format,
        include_partial_messages=resolved_output_mode == "human",
    )
    if resolved_output_mode == "human":
        return _run_human_delegate(command, stdout=stdout, stderr=stderr)

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


def _run_human_delegate(command: Sequence[str], *, stdout: TextIO, stderr: TextIO) -> int:
    print("Starting connector delegate...", file=stderr, flush=True)
    process = subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        text=True,
    )
    final_result = ""
    result_was_error = False
    seen_tools: set[str] = set()

    if process.stdout is not None:
        for raw_line in process.stdout:
            event = _parse_stream_event(raw_line, stderr)
            if event is None:
                continue
            _print_stream_progress(event, stderr, seen_tools)
            if event.get("type") == "result":
                final_result = str(event.get("result") or "")
                result_was_error = bool(event.get("is_error"))

    return_code = process.wait()
    if final_result:
        print(final_result.rstrip(), file=stdout)
    if return_code == 0 and result_was_error:
        return 1
    return return_code


def _parse_stream_event(
    raw_line: str, stderr: TextIO
) -> dict[str, object] | None:
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


def _print_stream_progress(
    event: dict[str, object], stderr: TextIO, seen_tools: set[str]
) -> None:
    event_type = event.get("type")
    if event_type == "system":
        _print_system_progress(event, stderr)
        return
    if event_type == "assistant":
        _print_assistant_progress(event, stderr, seen_tools)
        return
    if event_type == "stream_event":
        stream_event = event.get("event")
        if isinstance(stream_event, dict):
            _print_content_block_progress(stream_event, stderr, seen_tools)
        return
    if event_type == "result":
        duration = _format_duration(event.get("duration_ms"))
        if duration:
            print(f"Done in {duration}.", file=stderr, flush=True)


def _print_system_progress(event: dict[str, object], stderr: TextIO) -> None:
    if event.get("subtype") == "init":
        session_id = str(event.get("session_id") or "")
        suffix = f" ({session_id[:12]})" if session_id else ""
        print(f"Connected to Claude{suffix}.", file=stderr, flush=True)
    elif event.get("subtype") == "api_retry":
        attempt = event.get("attempt")
        max_retries = event.get("max_retries")
        print(f"Retrying Claude API ({attempt}/{max_retries})...", file=stderr, flush=True)


def _print_assistant_progress(
    event: dict[str, object], stderr: TextIO, seen_tools: set[str]
) -> None:
    message = event.get("message")
    if not isinstance(message, dict):
        return
    content = message.get("content")
    if not isinstance(content, list):
        return
    for block in content:
        if isinstance(block, dict):
            _print_tool_progress(block, stderr, seen_tools)


def _print_content_block_progress(
    event: dict[str, object], stderr: TextIO, seen_tools: set[str]
) -> None:
    if event.get("type") != "content_block_start":
        return
    content_block = event.get("content_block")
    if isinstance(content_block, dict):
        _print_tool_progress(content_block, stderr, seen_tools)


def _print_tool_progress(
    block: dict[str, object], stderr: TextIO, seen_tools: set[str]
) -> None:
    if block.get("type") != "tool_use":
        return
    raw_name = block.get("name")
    if not isinstance(raw_name, str) or raw_name in seen_tools:
        return
    seen_tools.add(raw_name)
    print(f"Using {_format_tool_name(raw_name)}...", file=stderr, flush=True)


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
