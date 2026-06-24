#!/usr/bin/env python3
"""PreToolUse hook that enforces the expected gh account per repository."""

from __future__ import annotations

import json
import re
import shlex
import sys

from hook_context import (
    gh_hostname_from_remote,
    preferred_gh_user_for_remote,
    repo_remote_url,
    resolve_hook_cwd,
)

GH_CMD_RE = re.compile(r"(^|[;&|])\s*gh\s+", re.IGNORECASE)
EXISTING_GH_TOKEN_RE = re.compile(r"(^|[;&|])\s*(?:env\s+)?GH_TOKEN=", re.IGNORECASE)


def _main() -> None:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        json.dump({}, sys.stdout)
        return

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

    hostname = gh_hostname_from_remote(remote_url)
    gh_user, reason = preferred_gh_user_for_remote(remote_url)
    user_arg = shlex.quote(gh_user)
    host_arg = shlex.quote(hostname)
    rewritten = (
        f'env GH_HOST={host_arg} GH_TOKEN="$(gh auth token --hostname {host_arg} --user {user_arg})" '
        f"{command}"
    )

    updated_input = dict(tool_input)
    updated_input["command"] = rewritten

    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "updatedInput": updated_input,
                "additionalContext": (
                    f"Enforced gh user `{gh_user}` on `{hostname}` for this repository ({reason})."
                ),
            }
        },
        sys.stdout,
    )


if __name__ == "__main__":
    _main()
