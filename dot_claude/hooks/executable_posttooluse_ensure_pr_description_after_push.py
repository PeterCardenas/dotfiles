#!/usr/bin/env python3
"""PostToolUse hook that nudges PR description review after a successful git push."""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
from typing import Optional

DEFAULT_GH_HOST = "github.com"
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
_USER_TOKEN_CACHE: dict[tuple[str, str], Optional[str]] = {}


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


def _gh_env() -> dict[str, str]:
    env = os.environ.copy()
    env.pop("GH_TOKEN", None)
    env.pop("GITHUB_TOKEN", None)
    return env


def _run_gh(
    cmd: list[str],
    *,
    cwd: str,
    timeout: int = 4,
    user: Optional[str] = None,
    hostname: str = DEFAULT_GH_HOST,
) -> Optional[subprocess.CompletedProcess[str]]:
    env = _gh_env()
    if user:
        token = _gh_token_for_user(user, hostname)
        if not token:
            return None
        env["GH_TOKEN"] = token

    try:
        return subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
            cwd=cwd,
            env=env,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None


def _run_gh_json(
    cmd: list[str],
    *,
    cwd: str,
    timeout: int = 4,
    user: Optional[str] = None,
    hostname: str = DEFAULT_GH_HOST,
) -> Optional[dict]:
    result = _run_gh(cmd, cwd=cwd, timeout=timeout, user=user, hostname=hostname)
    if not result or result.returncode != 0:
        return None

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None

    return data if isinstance(data, dict) else None


def _gh_known_users(hostname: str = DEFAULT_GH_HOST) -> list[str]:
    data = _run_gh_json(
        ["gh", "auth", "status", "--hostname", hostname, "--json", "hosts"],
        cwd=".",
        hostname=hostname,
    )
    if not data:
        return []

    hosts = data.get("hosts")
    entries: list[dict] = []
    if isinstance(hosts, dict):
        host_entries = hosts.get(hostname)
        if isinstance(host_entries, list):
            entries = [entry for entry in host_entries if isinstance(entry, dict)]
    elif isinstance(hosts, list):
        entries = [entry for entry in hosts if isinstance(entry, dict)]

    users: list[str] = []
    for entry in entries:
        login = entry.get("login")
        if isinstance(login, str) and login:
            users.append(login)
    return users


def _gh_user_candidates(hostname: str = DEFAULT_GH_HOST) -> list[Optional[str]]:
    seen: set[Optional[str]] = {None}
    candidates: list[Optional[str]] = [None]
    for user in _gh_known_users(hostname):
        if user in seen:
            continue
        seen.add(user)
        candidates.append(user)
    return candidates


def _gh_token_for_user(user: str, hostname: str = DEFAULT_GH_HOST) -> Optional[str]:
    cache_key = (hostname, user)
    if cache_key in _USER_TOKEN_CACHE:
        return _USER_TOKEN_CACHE[cache_key]

    result = _run_gh(
        ["gh", "auth", "token", "--hostname", hostname, "--user", user],
        cwd=".",
        hostname=hostname,
    )
    if not result or result.returncode != 0:
        _USER_TOKEN_CACHE[cache_key] = None
        return None

    token = (result.stdout or "").strip() or None
    _USER_TOKEN_CACHE[cache_key] = token
    return token


def get_current_branch_pr(cwd: str) -> Optional[dict]:
    """Return PR metadata for the current branch, or None when no PR exists."""
    for user in _gh_user_candidates(DEFAULT_GH_HOST):
        data = _run_gh_json(
            ["gh", "pr", "view", "--json", "number,title,url"],
            cwd=cwd,
            user=user,
            hostname=DEFAULT_GH_HOST,
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
        "if needed, make sure the PR description is up to date before finishing."
    )
    return {
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": additional_context,
        }
    }


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
    if not isinstance(command, str) or not is_git_push_command(command):
        json.dump({}, sys.stdout)
        return

    cwd = payload.get("cwd")
    if not isinstance(cwd, str) or not cwd:
        cwd = tool_input.get("working_directory")
    if not isinstance(cwd, str) or not cwd:
        cwd = "."

    pr_details = get_current_branch_pr(cwd)
    if not pr_details:
        json.dump({}, sys.stdout)
        return

    json.dump(_advisory(pr_details), sys.stdout)


if __name__ == "__main__":
    _main()
