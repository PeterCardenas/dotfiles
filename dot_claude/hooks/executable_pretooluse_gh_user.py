#!/usr/bin/env python3
"""PreToolUse hook that enforces the expected gh account per repository."""

from __future__ import annotations

import json
import re
import shlex
import subprocess
import sys
from pathlib import Path

GH_CMD_RE = re.compile(r"(^|[;&|])\s*gh\s+", re.IGNORECASE)
EXISTING_GH_TOKEN_RE = re.compile(r"(^|[;&|])\s*(?:env\s+)?GH_TOKEN=", re.IGNORECASE)

DEFAULT_GH_USER = "PeterCardenas"
WORK_GH_USER = "peter-cardenas-ai"


def _run(cmd: list[str], timeout: int = 4) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None


def _repo_remote_url(cwd: str) -> str | None:
    inside = _run(["git", "-C", cwd, "rev-parse", "--is-inside-work-tree"])
    if not inside or inside.returncode != 0:
        return None

    remote = _run(["git", "-C", cwd, "config", "--get", "remote.origin.url"])
    if not remote or remote.returncode != 0:
        return None

    value = (remote.stdout or "").strip()
    return value or None


def _select_user(remote_url: str) -> tuple[str, str]:
    if "work-github.com" in remote_url:
        return WORK_GH_USER, "work remote detected"
    if "personal-github.com" in remote_url:
        return DEFAULT_GH_USER, "personal remote detected"
    return DEFAULT_GH_USER, "unknown remote, defaulting to personal user"


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

    working_directory = tool_input.get("working_directory")
    if not isinstance(working_directory, str) or not working_directory:
        working_directory = str(Path.cwd())

    remote_url = _repo_remote_url(working_directory)
    if not remote_url:
        json.dump({}, sys.stdout)
        return

    gh_user, reason = _select_user(remote_url)
    user_arg = shlex.quote(gh_user)
    rewritten = f'env GH_TOKEN="$(gh auth token --user {user_arg})" {command}'

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
    _main()
