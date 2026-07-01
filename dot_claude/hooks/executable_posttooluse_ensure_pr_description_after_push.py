#!/usr/bin/env python3
"""PostToolUse hook that nudges PR title/description review after a successful git push."""

from __future__ import annotations

import json
import re
import shlex
import sys
from typing import Optional

from hook_context import (
    preferred_gh_user_candidates,
    require_repo_remote_url,
    resolve_hook_cwd,
    run_gh_json,
    run_hook,
)

COMMAND_SEPARATORS = {"&&", "||", ";", "|"}
GIT_GLOBAL_OPTIONS_WITH_VALUES = {
    "-c",
    "-C",
    "--config-env",
    "--exec-path",
    "--git-dir",
    "--namespace",
    "--super-prefix",
    "--work-tree",
}
DRY_RUN_FLAGS = {"-n", "--dry-run"}
ENV_ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=.*$")


def _command_segments(command: str) -> list[list[str]]:
    try:
        tokens = shlex.split(command)
    except ValueError:
        return []

    segments: list[list[str]] = []
    current: list[str] = []
    for token in tokens:
        if token in COMMAND_SEPARATORS:
            if current:
                segments.append(current)
                current = []
            continue
        current.append(token)

    if current:
        segments.append(current)
    return segments


def _skip_env_prefix(tokens: list[str], start: int = 0) -> int:
    index = start
    if index < len(tokens) and tokens[index] == "env":
        index += 1

    while index < len(tokens) and ENV_ASSIGNMENT_RE.match(tokens[index]):
        index += 1
    return index


def _first_git_subcommand(tokens: list[str]) -> tuple[Optional[str], list[str]]:
    index = _skip_env_prefix(tokens)
    if index >= len(tokens) or tokens[index] != "git":
        return None, []

    index += 1
    while index < len(tokens):
        token = tokens[index]
        if not token.startswith("-"):
            return token, tokens[index + 1 :]

        if token in GIT_GLOBAL_OPTIONS_WITH_VALUES and index + 1 < len(tokens):
            index += 2
            continue

        index += 1

    return None, []


def is_git_push_command(command: str) -> bool:
    """Return True when *command* includes a real git push invocation."""
    if "git" not in command or "push" not in command:
        return False

    for segment in _command_segments(command):
        subcommand, remaining = _first_git_subcommand(segment)
        if subcommand != "push":
            continue
        if any(flag in DRY_RUN_FLAGS for flag in remaining):
            continue
        return True
    return False


def get_current_branch_pr(cwd: str) -> Optional[dict]:
    """Return PR metadata for the current branch, or None when no PR exists."""
    remote_url = require_repo_remote_url(cwd)

    for user in preferred_gh_user_candidates(remote_url):
        data = run_gh_json(
            ["gh", "pr", "view", "--json", "number,title,url"],
            cwd=cwd,
            user=user,
        )
        if not data:
            continue

        url = data.get("url")
        if not isinstance(url, str) or not url:
            continue

        pr_details = {"url": url}
        number = data.get("number")
        title = data.get("title")
        if isinstance(number, int):
            pr_details["number"] = number
        if isinstance(title, str) and title:
            pr_details["title"] = title
        return pr_details

    return None


def _advisory(pr_details: dict) -> dict:
    pr_number = pr_details.get("number")
    pr_title = pr_details.get("title") or "current branch PR"
    pr_url = pr_details.get("url") or ""
    pr_label = f"#{pr_number}" if isinstance(pr_number, int) else "This branch"
    additional_context = (
        f"Detected a successful `git push` for {pr_label}: {pr_title} ({pr_url}). "
        "Check whether the latest branch changes are reflected in the pull request and, "
        "if needed, update the PR title and description before finishing "
        "(including the title when it no longer matches what the branch actually does)."
    )
    return {
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": additional_context,
        }
    }


def _main(payload: dict) -> None:
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        json.dump({}, sys.stdout)
        return

    command = tool_input.get("command")
    if not isinstance(command, str) or not is_git_push_command(command):
        json.dump({}, sys.stdout)
        return

    cwd = resolve_hook_cwd(payload, tool_input)
    pr_details = get_current_branch_pr(cwd)
    if not pr_details:
        json.dump({}, sys.stdout)
        return

    json.dump(_advisory(pr_details), sys.stdout)


if __name__ == "__main__":
    run_hook(_main, default_event="PostToolUse")
