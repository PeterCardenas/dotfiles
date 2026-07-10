#!/usr/bin/env python3
"""PreToolUse hook that prevents shell commands from writing Python bytecode."""

from __future__ import annotations

import json
import re
import shlex
import sys
from pathlib import PurePath


SHELL_SEGMENT_RE = re.compile(r"(?:^|[;&|])\s*([^;&|]+)")
PYTHON_COMMAND_RE = re.compile(r"^(?:python|python\d+(?:\.\d+)?|py)$")


def _basename(token: str) -> str:
    return PurePath(token).name


def _shell_segments(command: str) -> list[str]:
    return [match.group(1).strip() for match in SHELL_SEGMENT_RE.finditer(command)]


def _loads_py_compile_module(tokens: list[str]) -> bool:
    saw_python = False
    for idx, token in enumerate(tokens):
        command_name = _basename(token)
        if PYTHON_COMMAND_RE.fullmatch(command_name):
            saw_python = True
            continue

        if not saw_python:
            continue

        if token == "-m" and idx + 1 < len(tokens) and tokens[idx + 1] == "py_compile":
            return True
        if token == "-mpy_compile":
            return True

    return False


def _runs_py_compile(command: str) -> bool:
    for segment in _shell_segments(command):
        try:
            tokens = shlex.split(segment)
        except ValueError:
            continue
        if not tokens:
            continue
        if _basename(tokens[0]) == "py_compile":
            return True
        if _loads_py_compile_module(tokens):
            return True

    return False


def _runs_python(command: str) -> bool:
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|")
        lexer.whitespace_split = True
        lexer.commenters = ""
        tokens = list(lexer)
    except ValueError:
        return False
    command_start = True
    for token in tokens:
        if all(char in ";&|" for char in token):
            command_start = True
            continue
        if not command_start:
            continue
        command_name = _basename(token)
        if command_name == "env" or ("=" in token and not token.startswith("=")):
            continue
        if PYTHON_COMMAND_RE.fullmatch(command_name):
            return True
        command_start = False

    return False


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
    if not isinstance(command, str):
        json.dump({}, sys.stdout)
        return

    if _runs_py_compile(command):
        reason = (
            "Blocked `py_compile` because it writes `.pyc` files. "
            "Use this no-write syntax check instead: "
            "`python3 -c 'import sys, tokenize; "
            '[compile(tokenize.open(p).read(), p, "exec") for p in sys.argv[1:]]\' '
            "path/to/file.py`."
        )
        json.dump(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            },
            sys.stdout,
        )
        return

    if not _runs_python(command) or "PYTHONDONTWRITEBYTECODE=" in command:
        json.dump({}, sys.stdout)
        return

    reason = (
        "Blocked this Python command because imports can write `.pyc` files. "
        "Rerun it with `PYTHONDONTWRITEBYTECODE=1` before the Python command."
    )
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        },
        sys.stdout,
    )


if __name__ == "__main__":
    _main()
