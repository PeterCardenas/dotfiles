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
PUSH_OPTIONS_WITH_VALUES = {
    "--exec",
    "--receive-pack",
    "--repo",
    "--push-option",
    "-o",
}


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


def _push_args_without_options(args: list[str]) -> list[str]:
    result: list[str] = []
    index = 0
    while index < len(args):
        token = args[index]
        if token == "--":
            result.extend(args[index + 1 :])
            break
        if token in PUSH_OPTIONS_WITH_VALUES:
            index += 2
            continue
        if any(token.startswith(f"{option}=") for option in PUSH_OPTIONS_WITH_VALUES):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        result.append(token)
        index += 1
    return result


def _branch_from_refspec(refspec: str) -> Optional[str]:
    if refspec.startswith("+"):
        refspec = refspec[1:]
    if ":" in refspec:
        _source, destination = refspec.rsplit(":", 1)
    else:
        destination = refspec

    destination = destination.strip()
    if not destination or destination == "HEAD":
        return None
    if destination.startswith("refs/heads/"):
        return destination.removeprefix("refs/heads/")
    if destination.startswith("refs/"):
        return None
    return destination


def pushed_branch_from_command(command: str) -> Optional[str]:
    """Return the destination branch from a git push refspec when explicit."""
    for segment in _command_segments(command):
        subcommand, remaining = _first_git_subcommand(segment)
        if subcommand != "push":
            continue
        if any(flag in DRY_RUN_FLAGS for flag in remaining):
            continue

        positional = _push_args_without_options(remaining)
        if not positional:
            continue

        # First positional arg is usually the remote/repository. Refspecs follow it.
        refspecs = positional[1:] if len(positional) > 1 else positional
        for refspec in refspecs:
            branch = _branch_from_refspec(refspec)
            if branch:
                return branch
    return None


def get_branch_pr(cwd: str, branch: Optional[str] = None) -> Optional[dict]:
    """Return PR metadata for a branch, or None when no PR exists."""
    remote_url = require_repo_remote_url(cwd)

    for user in preferred_gh_user_candidates(remote_url):
        cmd = ["gh", "pr", "view", "--json", "number,title,url"]
        if branch:
            cmd.insert(3, branch)
        data = run_gh_json(
            cmd,
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


def get_current_branch_pr(cwd: str) -> Optional[dict]:
    """Return PR metadata for the current branch, or None when no PR exists."""
    return get_branch_pr(cwd)


def _advisory(pr_details: dict) -> dict:
    pr_number = pr_details.get("number")
    pr_title = pr_details.get("title") or "current branch PR"
    pr_url = pr_details.get("url") or ""
    pr_label = f"#{pr_number}" if isinstance(pr_number, int) else "This branch"
    additional_context = (
        f"Detected a successful `git push` for {pr_label}: {pr_title} ({pr_url}). "
        "Required before completing this task: inspect the PR with "
        f"`gh pr view {pr_url} --json title,body`, compare it with the pushed changes, "
        "and, if either field is stale, update it with `gh pr edit`. "
        "Do not merely acknowledge this reminder; complete the review and any needed update."
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
    pr_details = get_branch_pr(cwd, pushed_branch_from_command(command))
    if not pr_details:
        pr_details = get_current_branch_pr(cwd)
    if not pr_details:
        json.dump({}, sys.stdout)
        return

    json.dump(_advisory(pr_details), sys.stdout)


if __name__ == "__main__":
    run_hook(_main, default_event="PostToolUse")
