"""Shared helpers for Claude/Cursor hook payloads and gh host resolution."""

from __future__ import annotations

import os
import subprocess
from typing import Optional

DEFAULT_GH_HOST = "github.com"
WORK_GH_USER = "peter-cardenas-ai"
DEFAULT_GH_USER = "PeterCardenas"
_USER_TOKEN_CACHE: dict[tuple[str, str], Optional[str]] = {}


def resolve_hook_cwd(payload: dict, tool_input: dict | None = None) -> str:
    """Return repo cwd from hook payload fields Cursor/Claude may emit."""
    sources = [payload]
    if tool_input is not None:
        sources.append(tool_input)
    for source in sources:
        for key in ("cwd", "working_directory"):
            value = source.get(key)
            if isinstance(value, str) and value:
                return value
    return "."


def repo_remote_url(cwd: str) -> Optional[str]:
    try:
        inside = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--is-inside-work-tree"],
            capture_output=True,
            text=True,
            timeout=4,
            check=False,
        )
        if inside.returncode != 0:
            return None

        remote = subprocess.run(
            ["git", "-C", cwd, "config", "--get", "remote.origin.url"],
            capture_output=True,
            text=True,
            timeout=4,
            check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None

    if remote.returncode != 0:
        return None

    value = (remote.stdout or "").strip()
    return value or None


def gh_hostname_from_remote(remote_url: str) -> str:
    if "work-github.com" in remote_url:
        return "work-github.com"
    if "personal-github.com" in remote_url:
        return "personal-github.com"
    return DEFAULT_GH_HOST


def preferred_gh_user_for_remote(remote_url: str) -> tuple[str, str]:
    if "work-github.com" in remote_url:
        return WORK_GH_USER, "work remote detected"
    if "personal-github.com" in remote_url:
        return DEFAULT_GH_USER, "personal remote detected"
    return DEFAULT_GH_USER, "unknown remote, defaulting to personal user"


def gh_hostname_for_cwd(cwd: str) -> str:
    return gh_hostname_from_remote(repo_remote_url(cwd) or "")


def gh_env(hostname: str = DEFAULT_GH_HOST) -> dict[str, str]:
    env = os.environ.copy()
    env.pop("GH_TOKEN", None)
    env.pop("GITHUB_TOKEN", None)
    if hostname:
        env["GH_HOST"] = hostname
    return env


def run_gh(
    cmd: list[str],
    *,
    cwd: str = ".",
    timeout: int = 4,
    user: Optional[str] = None,
    hostname: str = DEFAULT_GH_HOST,
) -> Optional[subprocess.CompletedProcess[str]]:
    env = gh_env(hostname)
    if user:
        token = gh_token_for_user(user, hostname)
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


def run_gh_json(
    cmd: list[str],
    *,
    cwd: str = ".",
    timeout: int = 4,
    user: Optional[str] = None,
    hostname: str = DEFAULT_GH_HOST,
) -> Optional[dict]:
    result = run_gh(cmd, cwd=cwd, timeout=timeout, user=user, hostname=hostname)
    if not result or result.returncode != 0:
        return None

    try:
        import json

        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None

    return data if isinstance(data, dict) else None


def gh_known_users(hostname: str = DEFAULT_GH_HOST) -> list[str]:
    data = run_gh_json(
        ["gh", "auth", "status", "--hostname", hostname, "--json", "hosts"],
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


def gh_user_candidates(hostname: str = DEFAULT_GH_HOST) -> list[Optional[str]]:
    seen: set[Optional[str]] = {None}
    candidates: list[Optional[str]] = [None]
    for user in gh_known_users(hostname):
        if user in seen:
            continue
        seen.add(user)
        candidates.append(user)
    return candidates


def gh_token_for_user(user: str, hostname: str = DEFAULT_GH_HOST) -> Optional[str]:
    cache_key = (hostname, user)
    if cache_key in _USER_TOKEN_CACHE:
        return _USER_TOKEN_CACHE[cache_key]

    result = run_gh(
        ["gh", "auth", "token", "--hostname", hostname, "--user", user],
        hostname=hostname,
    )
    if not result or result.returncode != 0:
        _USER_TOKEN_CACHE[cache_key] = None
        return None

    token = (result.stdout or "").strip() or None
    _USER_TOKEN_CACHE[cache_key] = token
    return token


def preferred_gh_user_candidates(hostname: str) -> list[Optional[str]]:
    preferred_user = (
        WORK_GH_USER if hostname == "work-github.com" else DEFAULT_GH_USER
    )
    seen: set[Optional[str]] = set()
    candidates: list[Optional[str]] = []
    for user in [preferred_user, None, *gh_known_users(hostname)]:
        if user in seen:
            continue
        seen.add(user)
        candidates.append(user)
    return candidates
