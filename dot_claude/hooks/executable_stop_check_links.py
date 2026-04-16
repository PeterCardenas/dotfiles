#!/usr/bin/env python3
"""Stop hook that reminds the agent to include reference links.

Fires when Claude is about to stop. Checks the last assistant response for
URLs. If none are found, blocks so Claude can consider whether links should
be added (per CLAUDE.md: "Always include links as reference in responses").

Skips checking for trivial interactions (short responses, pure tool-use turns).
"""

from __future__ import annotations

import json
import re
import sys

URL_RE = re.compile(r"https?://\S+")
KEY_REFERENCES_MARKER = "Key references:"

# Responses shorter than this (in chars) are considered trivial and skipped.
MIN_RESPONSE_LENGTH = 120


def _output(block_reason: str | None = None) -> None:
    data: dict = {}
    if block_reason:
        data["decision"] = "block"
        data["reason"] = block_reason
    json.dump(data, sys.stdout)


def _extract_text_from_content(content: object) -> str | None:
    """Extract joined text from either string or block-list content."""
    if isinstance(content, str):
        return content

    if not isinstance(content, list):
        return None

    text_parts = []
    for block in content:
        if isinstance(block, str):
            text_parts.append(block)
            continue

        if not isinstance(block, dict):
            continue

        if block.get("type") == "text" and isinstance(block.get("text"), str):
            text_parts.append(block["text"])
            continue

        # Compatibility: some runtimes may emit plain text blocks without type.
        if isinstance(block.get("text"), str):
            text_parts.append(block["text"])

    if not text_parts:
        return None

    return "\n".join(text_parts)


def _extract_text_from_message(
    message: object, *, require_assistant_role: bool
) -> str | None:
    """Extract text from a message payload."""
    if not isinstance(message, dict):
        return None

    if require_assistant_role and message.get("role") != "assistant":
        return None

    return _extract_text_from_content(message.get("content"))


def _get_last_assistant_text(transcript_path: str) -> str | None:
    """Return the concatenated text blocks from the last assistant message."""
    last_text = None

    try:
        with open(transcript_path, encoding="utf-8") as f:
            for line in f:
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue

                msg = entry.get("message", {})
                if msg.get("role") != "assistant":
                    continue

                msg_text = _extract_text_from_message(msg, require_assistant_role=True)
                if msg_text:
                    last_text = msg_text
    except (OSError, KeyError):
        pass

    return last_text


def _main() -> None:
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        return _output()

    # Only check end_turn stops; tool_use stops are mid-turn, not final responses.
    if input_data.get("stop_reason") not in ("end_turn", None, ""):
        return _output()

    # Prefer the direct stop-hook payload because transcript writes may lag.
    # last_assistant_message is a plain string in the Claude Code hook payload.
    raw = input_data.get("last_assistant_message")
    last_text = raw if isinstance(raw, str) and raw else None

    # Fallback for older runtimes that don't provide last_assistant_message.
    if not last_text:
        transcript_path = input_data.get("transcript_path", "")
        if transcript_path:
            last_text = _get_last_assistant_text(transcript_path)

    # No text response (pure tool use or empty) — skip
    if not last_text:
        return _output()

    # Short/trivial response — skip
    if len(last_text.strip()) < MIN_RESPONSE_LENGTH:
        return _output()

    # If the response already includes the references section marker, skip.
    if KEY_REFERENCES_MARKER in last_text:
        return _output()

    # Check for URLs
    if URL_RE.search(last_text):
        return _output()

    _output(
        "Your response has no reference links. If relevant sources exist, revise the "
        "response to include helpful URLs (docs, source code, issue trackers, etc.) "
        "under:\n\nKey references:\n"
        "If links are truly unnecessary, end immediately with no additional text. "
        "Do not mention missing links or that you are adding them."
    )


if __name__ == "__main__":
    _main()
