from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass
import shutil
import subprocess
import sys


@dataclass(frozen=True)
class DelegateArgs:
    max_budget_usd: str
    query: str


def build_claude_command(
    *,
    allowed_tools: Sequence[str],
    prompt: str,
    max_budget_usd: str = "1",
) -> list[str]:
    if not allowed_tools:
        raise ValueError("at least one allowed tool is required")
    if not prompt.strip():
        raise ValueError("prompt must not be empty")

    return [
        "claude",
        "-p",
        "--setting-sources",
        "project,local",
        "--output-format",
        "json",
        "--no-session-persistence",
        "--max-budget-usd",
        max_budget_usd,
        "--allowedTools",
        ",".join(allowed_tools),
        "--",
        prompt,
    ]


def parse_delegate_args(argv: Sequence[str], program: str) -> DelegateArgs:
    max_budget_usd = "1"
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
        if option.startswith("--"):
            _print_usage(program)
            raise SystemExit(2)
        break

    query = " ".join(remaining).strip()
    if not query:
        _print_usage(program)
        raise SystemExit(2)

    return DelegateArgs(max_budget_usd=max_budget_usd, query=query)


def run_delegate(
    *,
    allowed_tools: Sequence[str],
    prompt: str,
    max_budget_usd: str,
) -> int:
    if shutil.which("claude") is None:
        print("connector delegate: missing dependency: claude", file=sys.stderr)
        return 127

    command = build_claude_command(
        allowed_tools=allowed_tools,
        prompt=prompt,
        max_budget_usd=max_budget_usd,
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
    )


def _print_usage(program: str) -> None:
    print(f"Usage: {program} [--max-budget-usd <amount>] <query>", file=sys.stderr)
