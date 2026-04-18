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
import time
from pathlib import Path

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

                msg_text = None

                # Claude-style transcript shape:
                # {"message": {"role": "assistant", "content": ...}}
                msg = entry.get("message", {})
                msg_text = _extract_text_from_message(msg, require_assistant_role=True)

                # Cursor transcript shape:
                # {"role": "assistant", "message": {"content": ...}}
                if not msg_text and entry.get("role") == "assistant":
                    msg_text = _extract_text_from_message(
                        entry.get("message", {}), require_assistant_role=False
                    )

                # Additional compatibility: top-level content payload.
                if not msg_text and entry.get("role") == "assistant":
                    msg_text = _extract_text_from_content(entry.get("content"))

                if msg_text:
                    last_text = msg_text
    except (OSError, KeyError):
        pass

    return last_text


def _safe_conversation_id(raw_id: str) -> str:
    """Mirror Cursor-safe conversation id normalization for path lookup."""
    # Cursor keeps UUID-ish ids intact; this replaces anything unsafe conservatively.
    return re.sub(r"[^A-Za-z0-9._-]", "_", raw_id)


def _candidate_transcript_paths(input_data: dict) -> list[Path]:
    """Build transcript path candidates from hook stdin fields."""
    candidates: list[Path] = []
    seen: set[str] = set()

    def add(path: Path) -> None:
        key = str(path)
        if key in seen:
            return
        seen.add(key)
        candidates.append(path)

    workspace_roots = input_data.get("workspace_roots")
    if not isinstance(workspace_roots, list):
        workspace_roots = []
    roots = [Path(p) for p in workspace_roots if isinstance(p, str) and p]

    ids: list[str] = []
    for key in ("conversation_id", "session_id"):
        value = input_data.get(key)
        if isinstance(value, str) and value:
            ids.append(_safe_conversation_id(value))

    for root in roots:
        transcripts_root = root / "agent-transcripts"
        for conv_id in ids:
            add(transcripts_root / conv_id / f"{conv_id}.jsonl")
            add(transcripts_root / f"{conv_id}.jsonl")  # legacy

    return candidates


def _latest_transcript_fallback(input_data: dict) -> Path | None:
    """Fallback to most recently updated transcript under workspace roots."""
    workspace_roots = input_data.get("workspace_roots")
    if not isinstance(workspace_roots, list):
        return None

    newest_path: Path | None = None
    newest_mtime = 0.0
    now = time.time()
    max_age_sec = 300  # keep selection local to current interaction window

    for root_str in workspace_roots:
        if not isinstance(root_str, str) or not root_str:
            continue
        transcripts_root = Path(root_str) / "agent-transcripts"
        if not transcripts_root.is_dir():
            continue
        for pattern in ("*/*.jsonl", "*.jsonl"):
            for path in transcripts_root.glob(pattern):
                try:
                    mtime = path.stat().st_mtime
                except OSError:
                    continue
                if now - mtime > max_age_sec:
                    continue
                if mtime > newest_mtime:
                    newest_mtime = mtime
                    newest_path = path

    return newest_path


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

    # Cursor ACP stop payloads may not include transcript_path or assistant text.
    if not last_text:
        for candidate in _candidate_transcript_paths(input_data):
            if candidate.is_file():
                last_text = _get_last_assistant_text(str(candidate))
                if last_text:
                    break

    # Final fallback: infer the active transcript by recent modification time.
    if not last_text:
        latest = _latest_transcript_fallback(input_data)
        if latest and latest.is_file():
            last_text = _get_last_assistant_text(str(latest))

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
        "Your response has no reference links. Output ONLY the additional suffix to "
        "append to the existing response, not a rewrite of the full response. If "
        "relevant sources exist, output only:\n\nKey references:\n- [Short title]"
        "(https://example.com)\n- [Short title](https://example.com)\n\nUse "
        "well-formatted Markdown links. Do not repeat any prior response text. Do "
        "not add preamble, thought content, explanations, or commentary about "
        "adding links. If links are truly unnecessary, end immediately with no "
        "additional text."
    )


if __name__ == "__main__":
    _main()
