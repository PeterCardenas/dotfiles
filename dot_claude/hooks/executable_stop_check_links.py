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

# Responses shorter than this (in chars) are considered trivial and skipped.
MIN_RESPONSE_LENGTH = 120


def _output(block_reason: str | None = None) -> None:
    data: dict = {}
    if block_reason:
        data["decision"] = "block"
        data["reason"] = block_reason
    json.dump(data, sys.stdout)


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

                content = msg.get("content")
                if not isinstance(content, list):
                    continue

                text_parts = []
                for block in content:
                    if block.get("type") == "text":
                        text_parts.append(block.get("text", ""))

                if text_parts:
                    last_text = "\n".join(text_parts)
    except (OSError, KeyError):
        pass

    return last_text


def _main() -> None:
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        return _output()

    transcript_path = input_data.get("transcript_path", "")
    if not transcript_path:
        return _output()

    last_text = _get_last_assistant_text(transcript_path)

    # No text response (pure tool use or empty) — skip
    if not last_text:
        return _output()

    # Short/trivial response — skip
    if len(last_text.strip()) < MIN_RESPONSE_LENGTH:
        return _output()

    # Check for URLs
    if URL_RE.search(last_text):
        return _output()

    _output(
        "Your response has no reference links. Per instructions, you should "
        "include links as references in responses. Consider whether any URLs "
        "(documentation, source, issue trackers, etc.) would be helpful here. "
        "If links genuinely weren't used, immediately finish with no extra response."
        "Do NOT acknowledge saying that there's no links, simply just stop."
        "Additionally, if you think you should add links, do NOT acknowledge"
        "that you are adding links, simply just add the links as \n\nKey references:"
    )


if __name__ == "__main__":
    _main()
