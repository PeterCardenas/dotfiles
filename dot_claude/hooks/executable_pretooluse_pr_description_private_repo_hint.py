#!/usr/bin/env python3
"""PreToolUse hook: detect PR description reads in private/internal repos.

When a Bash tool call appears to read PR description content via gh, and the repo
is private/internal, inject additional context nudging image-resolution behavior.
"""

from __future__ import annotations

import json
import re
import sys
from typing import Optional

from hook_context import (
    gh_hostname_for_cwd,
    gh_user_candidates,
    preferred_gh_user_candidates,
    resolve_hook_cwd,
    run_gh,
    run_gh_json,
)

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
    r"https?://(?:github\.com|personal-github\.com|work-github\.com)/([^/\s]+)/([^/\s]+)/pull/\d+",
    re.IGNORECASE,
)
REPO_FLAG_RE = re.compile(r"--repo\s+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)")
PR_VIEW_NUMBER_RE = re.compile(r"gh\s+pr\s+view(?:\s+(\d+))?", re.IGNORECASE)


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


def _repo_from_pr_view_context(command: str, *, cwd: str, hostname: str) -> Optional[str]:
    match = PR_VIEW_NUMBER_RE.search(command)
    if not match:
        return None
    pr_number = match.group(1)

    cmd = ["gh", "pr", "view"]
    if pr_number:
        cmd.append(pr_number)
    cmd.extend(["--json", "url", "-q", ".url"])

    for user in preferred_gh_user_candidates(hostname) + gh_user_candidates(hostname):
        result = run_gh(cmd, cwd=cwd, timeout=4, user=user, hostname=hostname)
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

    api_pull = API_PULL_RE.search(command)
    if not api_pull:
        return False

    lowered = command.lower()
    if any(
        flag in lowered
        for flag in (" -x patch", " --method patch", " -x post", " -x put")
    ):
        return False
    return True


def _repo_visibility(
    repo: Optional[str], *, cwd: str, hostname: str
) -> tuple[Optional[str], Optional[str]]:
    for user in preferred_gh_user_candidates(hostname) + gh_user_candidates(hostname):
        if repo:
            api_data = run_gh_json(
                ["gh", "api", f"repos/{repo}"],
                cwd=cwd,
                user=user,
                hostname=hostname,
            )
            if api_data:
                visibility = str(api_data.get("visibility") or "").lower() or None
                if api_data.get("private") is True:
                    visibility = "private"
                repo_name = api_data.get("full_name") or repo
                return visibility, repo_name

        cmd = ["gh", "repo", "view"]
        if repo:
            cmd.append(repo)
        cmd.extend(["--json", "nameWithOwner,isPrivate,visibility"])
        data = run_gh_json(cmd, cwd=cwd, user=user, hostname=hostname)
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

    cwd = resolve_hook_cwd(payload, tool_input)
    hostname = gh_hostname_for_cwd(cwd)
    repo_hint = _repo_from_command(command) or _repo_from_pr_view_context(
        command, cwd=cwd, hostname=hostname
    )
    visibility, repo_name = _repo_visibility(repo_hint, cwd=cwd, hostname=hostname)

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
