#!/usr/bin/env python3
"""PreToolUse hook: detect PR description reads in private/internal repos.

When a Bash tool call appears to read PR description content via gh, and the repo
is private/internal, inject additional context nudging image-resolution behavior.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from typing import Optional

GH_CMD_RE = re.compile(r"(^|[;&|])\s*gh\s+", re.IGNORECASE)
PR_VIEW_BODY_RE = re.compile(
    r"gh\s+pr\s+view\b[^\n]*?(--json[^\n]*\bbody\b|\b-q\s+\.body\b)",
    re.IGNORECASE,
)
API_PULL_RE = re.compile(
    r"gh\s+api\s+(?:'|\")?repos/([^/\s]+)/([^/\s]+)/pulls/\d+(?:[?'\"]|\s|$)",
    re.IGNORECASE,
)
PR_URL_RE = re.compile(
    r"https?://github\.com/([^/\s]+)/([^/\s]+)/pull/\d+",
    re.IGNORECASE,
)
REPO_FLAG_RE = re.compile(r"--repo\s+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)")
PR_VIEW_NUMBER_RE = re.compile(r"gh\s+pr\s+view(?:\s+(\d+))?", re.IGNORECASE)
DEFAULT_GH_HOST = "github.com"
_USER_TOKEN_CACHE: dict[tuple[str, str], Optional[str]] = {}


def _repo_from_command(command: str) -> Optional[str]:
    repo_match = REPO_FLAG_RE.search(command)
    if repo_match:
        return repo_match.group(1)

    api_match = API_PULL_RE.search(command)
    if api_match:
        return f"{api_match.group(1)}/{api_match.group(2)}"

    pr_url_match = PR_URL_RE.search(command)
    if pr_url_match:
        return f"{pr_url_match.group(1)}/{pr_url_match.group(2)}"

    return None


def _repo_from_pr_view_context(command: str) -> Optional[str]:
    match = PR_VIEW_NUMBER_RE.search(command)
    if not match:
        return None
    pr_number = match.group(1)

    cmd = ["gh", "pr", "view"]
    if pr_number:
        cmd.append(pr_number)
    cmd.extend(["--json", "url", "-q", ".url"])

    for user in _gh_user_candidates(DEFAULT_GH_HOST):
        result = _run_gh(cmd, timeout=4, user=user, hostname=DEFAULT_GH_HOST)
        if not result or result.returncode != 0:
            continue

        url = (result.stdout or "").strip()
        url_match = PR_URL_RE.search(url)
        if url_match:
            return f"{url_match.group(1)}/{url_match.group(2)}"

    return None


def _is_pr_description_read(command: str) -> bool:
    if PR_VIEW_BODY_RE.search(command):
        return True

    # `gh api repos/<owner>/<repo>/pulls/<num>` defaults to GET and returns body.
    api_pull = API_PULL_RE.search(command)
    if not api_pull:
        return False

    # Exclude obvious mutating calls; we only want read heuristics.
    lowered = command.lower()
    if any(
        flag in lowered
        for flag in (" -x patch", " --method patch", " -x post", " -x put")
    ):
        return False
    return True


def _gh_env() -> dict:
    env = os.environ.copy()
    env.pop("GH_TOKEN", None)
    env.pop("GITHUB_TOKEN", None)
    return env


def _run_gh(
    cmd: list[str],
    timeout: int = 4,
    user: Optional[str] = None,
    hostname: str = DEFAULT_GH_HOST,
) -> Optional[subprocess.CompletedProcess]:
    env = _gh_env()
    if user:
        token = _gh_token_for_user(user, hostname)
        if not token:
            return None
        # Force gh to authenticate as this specific user for this call.
        env["GH_TOKEN"] = token

    try:
        return subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
            env=env,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None


def _run_gh_json(
    cmd: list[str],
    timeout: int = 4,
    user: Optional[str] = None,
    hostname: str = DEFAULT_GH_HOST,
) -> Optional[dict]:
    result = _run_gh(cmd, timeout=timeout, user=user, hostname=hostname)
    if not result:
        return None

    if result.returncode != 0:
        return None

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


def _gh_known_users(hostname: str = DEFAULT_GH_HOST) -> list[str]:
    data = _run_gh_json(
        ["gh", "auth", "status", "--hostname", hostname, "--json", "hosts"],
        timeout=4,
        hostname=hostname,
    )
    if not data:
        return []

    hosts = data.get("hosts")
    entries = []
    if isinstance(hosts, dict):
        host_entries = hosts.get(hostname)
        if isinstance(host_entries, list):
            entries = host_entries
    elif isinstance(hosts, list):
        entries = hosts

    users = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        login = entry.get("login")
        if isinstance(login, str) and login:
            users.append(login)
    return users


def _gh_user_candidates(hostname: str = DEFAULT_GH_HOST) -> list[Optional[str]]:
    # None means "use current gh default account" before trying explicit users.
    seen = {None}
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
        timeout=4,
        hostname=hostname,
    )
    if not result or result.returncode != 0:
        _USER_TOKEN_CACHE[cache_key] = None
        return None

    token = (result.stdout or "").strip() or None
    _USER_TOKEN_CACHE[cache_key] = token
    return token


def _repo_visibility(repo: Optional[str]) -> tuple[Optional[str], Optional[str]]:
    for user in _gh_user_candidates(DEFAULT_GH_HOST):
        # First, try REST API repo metadata (most direct source for private/internal).
        if repo:
            api_data = _run_gh_json(
                ["gh", "api", f"repos/{repo}"], user=user, hostname=DEFAULT_GH_HOST
            )
            if api_data:
                visibility = str(api_data.get("visibility") or "").lower() or None
                if api_data.get("private") is True:
                    visibility = "private"
                repo_name = api_data.get("full_name") or repo
                return visibility, repo_name

        # Fallback to gh repo view (works for current repo or explicit repo).
        cmd = ["gh", "repo", "view"]
        if repo:
            cmd.append(repo)
        cmd.extend(["--json", "nameWithOwner,isPrivate,visibility"])
        data = _run_gh_json(cmd, user=user, hostname=DEFAULT_GH_HOST)
        if not data:
            continue

        visibility = str(data.get("visibility") or "").lower() or None
        if data.get("isPrivate") is True:
            visibility = "private"
        repo_name = data.get("nameWithOwner")
        return visibility, repo_name

    return None, None


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

    if not _is_pr_description_read(command):
        json.dump({}, sys.stdout)
        return

    repo_hint = _repo_from_command(command) or _repo_from_pr_view_context(command)
    visibility, repo_name = _repo_visibility(repo_hint)

    if visibility not in {"private", "internal"}:
        json.dump({}, sys.stdout)
        return

    repo_display = repo_name or repo_hint or "current repository"
    additional_context = (
        f"Heuristic: detected a PR description/body read in {repo_display} ({visibility}). "
        "If the PR includes screenshot/user-attachment links, use the `pr-image-visibility` skill "
        "to resolve them to rendered/private URLs before analysis and treat those resolved URLs as "
        "ephemeral signed links."
    )

    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "additionalContext": additional_context,
            }
        },
        sys.stdout,
    )


if __name__ == "__main__":
    _main()
