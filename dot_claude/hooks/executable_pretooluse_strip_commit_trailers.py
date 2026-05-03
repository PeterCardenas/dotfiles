#!/usr/bin/env python3
"""PreToolUse hook that strips Cursor attribution trailers from git commits."""

from __future__ import annotations

import json
import re
import sys

COMMIT_CMD_RE = re.compile(
    r"(^|[;&|])\s*git\b(?:(?![;&|]).)*\bcommit(\s|$)"
)
PR_CREATE_CMD_RE = re.compile(r"(^|[;&|])\s*gh\s+pr\s+create(\s|$)")
TRAILER_PATTERNS = (
    r"Made-with:\s*Cursor",
    r"Co-authored-by:\s*Cursor <[^>]+>",
)
LITERAL_TRAILER_RES = tuple(
    re.compile(rf"(?i){pattern}(?=(?:\r?\n|$|['\"]))") for pattern in TRAILER_PATTERNS
)
ESCAPED_TRAILER_RES = tuple(
    re.compile(rf"(?i){pattern}(?=(?:\\n|$|['\"]))") for pattern in TRAILER_PATTERNS
)
EMPTY_TRAILER_ARG_RE = re.compile(r"""\s+--trailer(?:\s+|=)(['"])\s*\1""")
LITERAL_EMPTY_LINES_BEFORE_CLOSER_RE = re.compile(r"\n{2,}(?=['\"])")
ESCAPED_EMPTY_LINES_BEFORE_CLOSER_RE = re.compile(r"(?:\\n){2,}(?=['\"])")
PR_ATTRIBUTION_PATTERNS = (r"Made with \[Cursor\]\(https://cursor\.com\)",)
LITERAL_PR_ATTRIBUTION_RES = tuple(
    re.compile(rf"(?i){pattern}(?=(?:\r?\n|$|['\"]))")
    for pattern in PR_ATTRIBUTION_PATTERNS
)
ESCAPED_PR_ATTRIBUTION_RES = tuple(
    re.compile(rf"(?i){pattern}(?=(?:\\n|$|['\"]))")
    for pattern in PR_ATTRIBUTION_PATTERNS
)


def _sanitize_command(command: str) -> str:
    cleaned = command
    for trailer_re in LITERAL_TRAILER_RES:
        cleaned = trailer_re.sub("", cleaned)
    for trailer_re in ESCAPED_TRAILER_RES:
        cleaned = trailer_re.sub("", cleaned)
    cleaned = EMPTY_TRAILER_ARG_RE.sub("", cleaned)
    for attribution_re in LITERAL_PR_ATTRIBUTION_RES:
        cleaned = attribution_re.sub("", cleaned)
    for attribution_re in ESCAPED_PR_ATTRIBUTION_RES:
        cleaned = attribution_re.sub("", cleaned)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    cleaned = re.sub(r"(?:\\n){3,}", lambda _: "\\n\\n", cleaned)
    cleaned = re.sub(r"[ \t]+\n", "\n", cleaned)
    cleaned = LITERAL_EMPTY_LINES_BEFORE_CLOSER_RE.sub("\n", cleaned)
    cleaned = ESCAPED_EMPTY_LINES_BEFORE_CLOSER_RE.sub("\\n", cleaned)
    return cleaned


def _main() -> None:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        payload = {}

    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        json.dump({}, sys.stdout)
        return

    command = tool_input.get("command")
    if not isinstance(command, str) or not (
        COMMIT_CMD_RE.search(command) or PR_CREATE_CMD_RE.search(command)
    ):
        json.dump({}, sys.stdout)
        return

    cleaned = _sanitize_command(command)
    if cleaned == command:
        json.dump({}, sys.stdout)
        return

    updated_input = dict(tool_input)
    updated_input["command"] = cleaned
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "updatedInput": updated_input,
                "additionalContext": (
                    "Removed Cursor attribution from the git command before execution."
                ),
            }
        },
        sys.stdout,
    )


if __name__ == "__main__":
    _main()
