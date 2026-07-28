#!/usr/bin/env python3
"""PreToolUse hook that chains every shell-command rewriter into one response.

Claude Code runs all matching hooks in parallel and honors a single
`updatedInput`, so two hooks that each rewrite `command` silently clobber each
other: rtk's rewrite won, which left the git sanitizer (attribution stripping,
commit message formatting) and the gh-user enforcement as no-ops -- they still
reported their `additionalContext`, so they looked like they had run.

This hook is therefore the only registered command rewriter. It runs the others
in order, feeding each the previous one's command, and returns the composed
result. Deny-only hooks are unaffected by the clobbering and stay registered on
their own.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

from hook_context import allow_with_updated_input

HOOKS_DIR = Path(__file__).resolve().parent

# Cheap prefilter so a plain `ls` does not pay for a python start per link.
# It must stay strictly broader than the link's own matcher -- the link remains
# the authority on whether it applies, and a too-narrow pattern here would
# disable it silently, which is the failure this whole hook exists to prevent.
_GIT_OR_GH_RE = re.compile(r"\b(?:git|gh)\b")

# Order matters: sanitizing runs on the real command, and rtk runs last so it
# rewrites what will actually execute.
CHAIN: tuple[tuple[re.Pattern[str] | None, list[str]], ...] = (
    (_GIT_OR_GH_RE, [sys.executable, str(HOOKS_DIR / "pretooluse_gh_user.py")]),
    (_GIT_OR_GH_RE, [sys.executable, str(HOOKS_DIR / "pretooluse_git_sanitize.py")]),
    (None, ["rtk", "hook", "claude"]),
)

# Each link is a hook that already had its own 10s budget; keep some headroom
# under the chain's own timeout rather than letting one slow link stall a tool
# call indefinitely.
_LINK_TIMEOUT_SECONDS = 8


def _run_link(argv: list[str], payload: dict) -> dict:
    """Run one chained hook and return its parsed response ({} if it opted out).

    A link that cannot run (missing binary, timeout, malformed output) is
    skipped rather than allowed to block the tool call: these hooks are
    conveniences, and a broken one must not wedge every shell command.
    """
    try:
        result = subprocess.run(
            argv,
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            timeout=_LINK_TIMEOUT_SECONDS,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return {}

    if result.returncode != 0:
        # Exit-code blocks (2 = block, per the hook protocol) belong to the
        # harness, not to us: mirror the link's verdict instead of swallowing it.
        sys.stderr.write(result.stderr)
        sys.exit(result.returncode)

    if not result.stdout.strip():
        return {}

    try:
        parsed = json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}

    return parsed if isinstance(parsed, dict) else {}


def _main(payload: dict) -> None:
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        json.dump({}, sys.stdout)
        return

    original_command = tool_input.get("command")
    if not isinstance(original_command, str):
        json.dump({}, sys.stdout)
        return

    command = original_command
    contexts: list[str] = []

    for prefilter, argv in CHAIN:
        if prefilter is not None and not prefilter.search(command):
            continue

        link_payload = dict(payload)
        link_input = dict(tool_input)
        link_input["command"] = command
        link_payload["tool_input"] = link_input

        output = _run_link(argv, link_payload).get("hookSpecificOutput")
        if not isinstance(output, dict):
            continue

        if output.get("permissionDecision") == "deny":
            # A block is final: stop before a later link can rewrite the
            # command out from under the reason the user is about to read.
            json.dump({"hookSpecificOutput": output}, sys.stdout)
            return

        updated_input = output.get("updatedInput")
        if isinstance(updated_input, dict):
            rewritten = updated_input.get("command")
            if isinstance(rewritten, str):
                command = rewritten

        context = output.get("additionalContext")
        if isinstance(context, str) and context.strip():
            contexts.append(context.strip())

    if command == original_command:
        # Nothing rewrote the command; pass along any context the links added.
        if contexts:
            json.dump(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "additionalContext": "\n".join(contexts),
                    }
                },
                sys.stdout,
            )
        else:
            json.dump({}, sys.stdout)
        return

    reason = "\n".join(contexts) if contexts else "Rewrote the shell command."
    json.dump(
        allow_with_updated_input(tool_input, {"command": command}, reason),
        sys.stdout,
    )


if __name__ == "__main__":
    try:
        input_payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        input_payload = {}
    _main(input_payload if isinstance(input_payload, dict) else {})
