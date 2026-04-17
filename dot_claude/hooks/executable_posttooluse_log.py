#!/usr/bin/env python3
"""PostToolUse hook that strips Cursor commit attribution trailers."""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
import subprocess
import sys

LOG_FILE = Path("/tmp/claude-posttooluse.log")
MADE_WITH_RE = re.compile(r"(?im)^Made-with:\s*Cursor\s*$\n?")
COAUTHORED_RE = re.compile(r"(?im)^Co-authored-by:\s*Cursor <[^>]+>\s*$\n?")


def _run(*args: str, check: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        text=True,
        capture_output=True,
        check=check,
    )


def _strip_cursor_attribution() -> bool:
    in_repo = _run("git", "rev-parse", "--is-inside-work-tree")
    if in_repo.returncode != 0:
        return False

    msg_proc = _run("git", "show", "-s", "--format=%B", "HEAD")
    if msg_proc.returncode != 0:
        return False

    original = msg_proc.stdout
    cleaned = MADE_WITH_RE.sub("", original)
    cleaned = COAUTHORED_RE.sub("", cleaned)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned).rstrip() + "\n"
    if cleaned == original:
        return False

    amend = subprocess.run(
        ("git", "commit", "--amend", "-F", "-"),
        text=True,
        input=cleaned,
        capture_output=True,
    )
    return amend.returncode == 0


def _main() -> None:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        payload = {}

    tool_name = payload.get("tool_name")
    tool_input = payload.get("tool_input") or {}
    command = tool_input.get("command") if isinstance(tool_input, dict) else None

    stripped = False
    if tool_name == "Bash" and isinstance(command, str) and "git commit" in command:
        stripped = _strip_cursor_attribution()

    event = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "hook_event_name": "PostToolUse",
        "tool_name": tool_name,
        "tool_input": tool_input,
        "stripped_attribution": stripped,
    }

    try:
        with LOG_FILE.open("a", encoding="utf-8") as f:
            f.write(json.dumps(event, ensure_ascii=True) + "\n")
    except OSError:
        # Best effort logging only.
        pass

    json.dump({}, sys.stdout)


if __name__ == "__main__":
    _main()
