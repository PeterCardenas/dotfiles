#!/usr/bin/env python3
"""PreToolUse hook that formats git commit messages with commitmsgfmt."""

from __future__ import annotations

import json
import re
import subprocess
import sys

COMMIT_CMD_RE = re.compile(r"(^|[;&|])\s*git\s+commit(\s|$)")
HEREDOC_MESSAGE_RE = re.compile(
    r"(\s(?:-m|--message)\s+[\"']\$\(\s*cat\s+<<'EOF'\n)([\s\S]*?)(\nEOF\n\)\s*[\"'])"
)
QUOTED_MESSAGE_RE = re.compile(r"(\s(?:-m|--message)\s+)([\"'])(.*?)(\2)", re.DOTALL)


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
        encoded = formatted.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
        return f"{prefix}{quote}{encoded}{suffix}"

    return QUOTED_MESSAGE_RE.sub(_replacement, command, count=1)


def _sanitize_command(command: str) -> str:
    updated = _replace_heredoc_message(command)
    if updated != command:
        return updated

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
    if not isinstance(command, str) or not COMMIT_CMD_RE.search(command):
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
                "additionalContext": "Formatted git commit message with commitmsgfmt.",
            }
        },
        sys.stdout,
    )


if __name__ == "__main__":
    _main()
