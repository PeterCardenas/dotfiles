#!/usr/bin/env python3
"""PreToolUse hook that sanitizes git commit and PR commands."""

from __future__ import annotations

import json
import re
import subprocess
import sys

COMMIT_CMD_RE = re.compile(r"(^|[;&|])\s*git\b(?:(?![;&|]).)*\bcommit(\s|$)")
PR_CREATE_CMD_RE = re.compile(r"(^|[;&|])\s*gh\s+pr\s+create(\s|$)")
HEREDOC_MESSAGE_RE = re.compile(
    r"(\s(?:-m|--message)\s+[\"']\$\(\s*cat\s+<<'EOF'\n)([\s\S]*?)(\nEOF\n\)\s*[\"'])"
)
QUOTED_MESSAGE_RE = re.compile(r"(\s(?:-m|--message)\s+)([\"'])(.*?)(\2)", re.DOTALL)
TRAILER_PATTERNS = (
    r"Made-with:\s*Cursor",
    r"Co-authored-by:\s*Cursor <[^>]+>",
    r"Co-authored-by:\s*Claude <[^>]+>",
)
LITERAL_TRAILER_RES = tuple(
    re.compile(rf"(?i){pattern}(?=(?:\r?\n|$|['\"]))")
    for pattern in TRAILER_PATTERNS
)
ESCAPED_TRAILER_RES = tuple(
    re.compile(rf"(?i){pattern}(?=(?:\\n|$|['\"]))")
    for pattern in TRAILER_PATTERNS
)
PR_ATTRIBUTION_PATTERNS = (
    r"Made with \[Cursor\]\(https://cursor\.com\)",
    # Claude Code prefixes the line with a 🤖 emoji; strip it too when present.
    r"(?:🤖\s*)?Generated with \[Claude Code\]\(https://claude\.(?:com/claude-code|ai/code)\)",
)
LITERAL_PR_ATTRIBUTION_RES = tuple(
    re.compile(rf"(?i){pattern}(?=(?:\r?\n|$|['\"]))")
    for pattern in PR_ATTRIBUTION_PATTERNS
)
ESCAPED_PR_ATTRIBUTION_RES = tuple(
    re.compile(rf"(?i){pattern}(?=(?:\\n|$|['\"]))")
    for pattern in PR_ATTRIBUTION_PATTERNS
)
EMPTY_TRAILER_ARG_RE = re.compile(r"""\s+--trailer(?:\s+|=)(['"])\s*\1""")
LITERAL_EMPTY_LINES_BEFORE_CLOSER_RE = re.compile(r"\n{2,}(?=['\"])")
ESCAPED_EMPTY_LINES_BEFORE_CLOSER_RE = re.compile(r"(?:\\n){2,}(?=['\"])")


def _format_message(message: str) -> str:
    try:
        result = subprocess.run(
            ["commitmsgfmt"],
            input=message,
            text=True,
            capture_output=True,
            check=False,
        )
    except OSError:
        return message

    if result.returncode != 0:
        return message

    return result.stdout


def _replace_heredoc_message(command: str) -> str:
    def _replacement(match: re.Match[str]) -> str:
        prefix, message, suffix = match.groups()
        formatted = _format_message(message).rstrip("\n")
        return f"{prefix}{formatted}{suffix}"

    return HEREDOC_MESSAGE_RE.sub(_replacement, command, count=1)


def _replace_quoted_message(command: str) -> str:
    def _replacement(match: re.Match[str]) -> str:
        prefix, quote, message, suffix = match.groups()
        if quote == "'":
            return match.group(0)

        decoded = message.replace("\\n", "\n")
        formatted = _format_message(decoded).rstrip("\n")
        encoded = (
            formatted.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
        )
        return f"{prefix}{quote}{encoded}{suffix}"

    return QUOTED_MESSAGE_RE.sub(_replacement, command, count=1)


def _strip_agent_attribution(command: str) -> str:
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


def _sanitize_command(command: str) -> str:
    command = _strip_agent_attribution(command)
    if HEREDOC_MESSAGE_RE.search(command):
        return _replace_heredoc_message(command)

    return _replace_quoted_message(command)


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
                "additionalContext": "Removed agent attribution and formatted the git command.",
            }
        },
        sys.stdout,
    )


if __name__ == "__main__":
    _main()
