#!/usr/bin/env python3
"""PreToolUse hook that enforces the expected gh account per repository."""

from __future__ import annotations

import json
import re
import sys

from hook_context import (
    MissingGhTokenError,
    gh_token_command_expr,
    gh_token_for_user,
    preferred_gh_user_for_remote,
    repo_remote_url,
    resolve_hook_cwd,
    run_hook,
)

GH_CMD_RE = re.compile(r"(^|[;&|])\s*gh\s+", re.IGNORECASE)
EXISTING_GH_TOKEN_RE = re.compile(r"(^|[;&|])\s*(?:env\s+)?GH_TOKEN=", re.IGNORECASE)

_MISSING_GH_TOKEN_MESSAGE = (
    "User action required: this command was blocked because `gh auth token` could not "
    "resolve a token for the GitHub user required by this repository. Please run "
    "`gh auth status` and ensure the expected account is logged in."
)


def _main(payload: dict) -> None:
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        json.dump({}, sys.stdout)
        return

    command = tool_input.get("command")
    if not isinstance(command, str) or not GH_CMD_RE.search(command):
        json.dump({}, sys.stdout)
        return

    if EXISTING_GH_TOKEN_RE.search(command):
        json.dump({}, sys.stdout)
        return

    cwd = resolve_hook_cwd(payload, tool_input)
    remote_url = repo_remote_url(cwd)
    if not remote_url:
        json.dump({}, sys.stdout)
        return

    gh_user, reason = preferred_gh_user_for_remote(remote_url)
    if not gh_token_for_user(gh_user):
        raise MissingGhTokenError(_MISSING_GH_TOKEN_MESSAGE)

    token_expr = gh_token_command_expr(gh_user)
    rewritten = f"GH_TOKEN={token_expr} {command}"

    updated_input = dict(tool_input)
    updated_input["command"] = rewritten

    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "updatedInput": updated_input,
                "additionalContext": (
                    f"Enforced gh user `{gh_user}` for this repository ({reason})."
                ),
            }
        },
        sys.stdout,
    )


if __name__ == "__main__":
    run_hook(_main)
