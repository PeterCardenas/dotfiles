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
COMMIT_CMD_RE = re.compile(r"(^|[;&|])\s*git\s+commit(\s|$)")


def _run(*args: str, check: bool = False, cwd: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        text=True,
        capture_output=True,
        check=check,
        cwd=cwd,
    )


def _strip_cursor_attribution(cwd: str | None = None) -> tuple[bool, str | None]:
    in_repo = _run("git", "rev-parse", "--is-inside-work-tree", cwd=cwd)
    if in_repo.returncode != 0:
        return False, "not_in_git_repo"

    msg_proc = _run("git", "show", "-s", "--format=%B", "HEAD", cwd=cwd)
    if msg_proc.returncode != 0:
        return False, "head_message_unavailable"

    original = msg_proc.stdout
    cleaned = MADE_WITH_RE.sub("", original)
    cleaned = COAUTHORED_RE.sub("", cleaned)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned).rstrip() + "\n"
    if cleaned == original:
        return False, "no_cursor_attribution_found"

    amend = subprocess.run(
        ("git", "commit", "--amend", "--allow-empty", "-F", "-"),
        text=True,
        input=cleaned,
        capture_output=True,
        cwd=cwd,
    )
    if amend.returncode != 0:
        detail = amend.stderr.strip() or amend.stdout.strip() or "unknown_error"
        return False, f"amend_failed: {detail}"
    return True, None


def _main() -> None:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        payload = {}

    tool_name = payload.get("tool_name")
    tool_input = payload.get("tool_input") or {}
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    cwd = tool_input.get("cwd") if isinstance(tool_input, dict) and isinstance(tool_input.get("cwd"), str) else None
    if cwd == "":
        cwd = None

    stripped = False
    strip_error = None
    if (
        tool_name in {"Bash", "Shell"}
        and isinstance(command, str)
        and COMMIT_CMD_RE.search(command)
    ):
        stripped, strip_error = _strip_cursor_attribution(cwd=cwd)

    event = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "hook_event_name": "PostToolUse",
        "tool_name": tool_name,
        "tool_input": tool_input,
        "stripped_attribution": stripped,
        "strip_error": strip_error,
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
