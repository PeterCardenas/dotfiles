#!/usr/bin/env python3
"""PreToolUse hook that blocks sending Slack messages."""

from __future__ import annotations

import json
import re
import sys

SEND_MESSAGE_TOOL_RE = re.compile(
    r"(?:^|[_\-.])(?:send|post|reply)(?:[_\-.].*)?(?:message|slack)(?:[_\-.]|$)|"
    r"chat[_\-.]?postmessage|postmessage|postephemeral",
    re.IGNORECASE,
)
SLACK_MCP_TOOL_RE = re.compile(
    r"(?:^|[_\-.])(?:mcp[_\-.]+)?slack(?:[_\-.]|$)", re.IGNORECASE
)


def _mcp_tool_parts(
    payload: dict[str, object], tool_input: dict[str, object]
) -> list[str]:
    names: list[str] = []
    for source in (payload, tool_input):
        for key in (
            "tool_name",
            "name",
            "tool",
            "mcp_tool_name",
            "server_name",
            "mcp_server_name",
        ):
            value = source.get(key)
            if isinstance(value, str):
                names.append(value)
    return names


def _should_block(payload: dict[str, object]) -> bool:
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        tool_input = {}

    tool_parts = _mcp_tool_parts(payload, tool_input)
    is_slack_mcp = any(SLACK_MCP_TOOL_RE.search(name) for name in tool_parts)
    sends_message = any(SEND_MESSAGE_TOOL_RE.search(name) for name in tool_parts)
    return is_slack_mcp and sends_message


def _main() -> None:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        payload = {}

    if not isinstance(payload, dict) or not _should_block(payload):
        json.dump({}, sys.stdout)
        return

    reason = (
        "Blocked sending a Slack message from an agent. "
        "Use Slack directly if a message should be sent."
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
