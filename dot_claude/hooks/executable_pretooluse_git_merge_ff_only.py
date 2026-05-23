#!/usr/bin/env python3
"""PreToolUse hook that blocks git merge commands that may create merge commits."""

from __future__ import annotations

import json
import re
import shlex
import sys

GIT_MERGE_SEGMENT_RE = re.compile(
    r"(?:^|[;&|])\s*([^;&|]*\bgit\b[^;&|]*\bmerge\b[^;&|]*)",
    re.IGNORECASE,
)
SAFE_MERGE_FLAGS = {"--ff-only", "--squash", "--abort", "--quit"}
BLOCKED_MERGE_FLAGS = {"--continue"}


def _merge_segments(command: str) -> list[str]:
    return [match.group(1).strip() for match in GIT_MERGE_SEGMENT_RE.finditer(command)]


def _merge_args(segment: str) -> list[str] | None:
    try:
        tokens = shlex.split(segment)
    except ValueError:
        return None

    for idx, token in enumerate(tokens):
        if token == "merge" and "git" in tokens[:idx]:
            return tokens[idx + 1 :]

    return None


def _is_safe_merge(args: list[str]) -> bool:
    if any(flag in args for flag in BLOCKED_MERGE_FLAGS):
        return False

    return any(flag in args for flag in SAFE_MERGE_FLAGS)


def _should_block(command: str) -> bool:
    for segment in _merge_segments(command):
        merge_args = _merge_args(segment)
        if merge_args is None:
            continue
        if not _is_safe_merge(merge_args):
            return True

    return False


def _main() -> None:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        payload = {}

    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        json.dump({}, sys.stdout)
        return

    command = tool_input.get("command")
    if not isinstance(command, str) or not _should_block(command):
        json.dump({}, sys.stdout)
        return

    # On deny, Claude Code feeds permissionDecisionReason to the model (not
    # additionalContext as the primary cancellation explanation). See hooks guide.
    reason = (
        "Blocked `git merge` because it may create a merge commit. "
        "Use `git merge --ff-only ...`, `git merge --squash ...`, "
        "or `git rebase` instead."
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
    _main()
