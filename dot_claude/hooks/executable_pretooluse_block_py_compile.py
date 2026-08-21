#!/usr/bin/env python3
"""Deny shell commands mentioning Python bytecode compiler names."""

from __future__ import annotations

import json
import sys


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        payload = {}
    tool_input = payload.get("tool_input")
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    if not isinstance(command, str) or not any(
        compiler in command for compiler in ("py_compile", "compileall")
    ):
        json.dump({}, sys.stdout)
        return
    reason = (
        "Denied because the command contains `py_compile` or `compileall`; "
        "both Python compiler names can write `.pyc` files."
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
    main()
