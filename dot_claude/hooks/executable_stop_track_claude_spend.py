#!/usr/bin/env python3
"""Track standalone Claude CLI spend from Stop hooks.

The tmux status script already reads ~/.local/share/claude-spend/daily-* and
live PID files. Claude CLI Stop hooks are short-lived, so this hook records
deduped deltas directly into the daily aggregate.
"""

from __future__ import annotations

import fcntl
import json
import os
import sys
import urllib.request
from collections.abc import Iterable
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


SPEND_SUBDIR = "claude-spend"
STATE_FILE = ".claude-cli-state.json"
LOCK_FILE = ".claude-cli.lock"
LITELLM_PRICING_URL = (
    "https://raw.githubusercontent.com/BerriAI/litellm/main/"
    "model_prices_and_context_window.json"
)


def _output() -> None:
    json.dump({}, sys.stdout)


def _as_float(value: object) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return None
    return None


def _usage_number(usage: dict[str, Any], key: str) -> float:
    return _as_float(usage.get(key)) or 0.0


def _fetch_litellm_pricing() -> dict[str, Any]:
    with urllib.request.urlopen(LITELLM_PRICING_URL, timeout=10) as response:
        raw = json.load(response)
    return raw if isinstance(raw, dict) else {}


def _model_prices(model: object, pricing: dict[str, Any]) -> dict[str, Any] | None:
    if not isinstance(model, str):
        return None
    normalized = model.lower()
    candidates = (model, normalized, f"anthropic/{model}", f"anthropic/{normalized}")
    for candidate in candidates:
        prices = pricing.get(candidate)
        if isinstance(prices, dict):
            return prices
    for model_name, prices in pricing.items():
        if not isinstance(model_name, str) or not isinstance(prices, dict):
            continue
        aliases = prices.get("aliases")
        if isinstance(aliases, list) and normalized in {
            alias.lower() for alias in aliases if isinstance(alias, str)
        }:
            return prices
    return None


def _tiered_cost(
    tokens: float, base_cost: float, above_200k_cost: float | None
) -> float:
    if above_200k_cost is None or tokens <= 200_000:
        return tokens * base_cost
    return 200_000 * base_cost + (tokens - 200_000) * above_200k_cost


def _cost_from_usage(message: dict[str, Any], pricing: dict[str, Any]) -> float:
    usage = message.get("usage")
    if not isinstance(usage, dict):
        return 0.0

    direct_cost = _as_float(usage.get("total_cost_usd")) or _as_float(
        usage.get("cost_usd")
    )
    if direct_cost is not None:
        return direct_cost

    cost = usage.get("cost")
    if isinstance(cost, dict):
        direct_cost = _as_float(cost.get("amount"))
        if direct_cost is not None:
            return direct_cost

    prices = _model_prices(message.get("model"), pricing)
    if prices is None:
        return 0.0

    input_tokens = _usage_number(usage, "input_tokens")
    output_tokens = _usage_number(usage, "output_tokens")
    cache_write_tokens = _usage_number(usage, "cache_creation_input_tokens")
    cache_read_tokens = _usage_number(usage, "cache_read_input_tokens")
    input_cost = _as_float(prices.get("input_cost_per_token")) or 0.0
    output_cost = _as_float(prices.get("output_cost_per_token")) or 0.0
    cache_write_cost = _as_float(prices.get("cache_creation_input_token_cost")) or 0.0
    cache_read_cost = _as_float(prices.get("cache_read_input_token_cost")) or 0.0
    return (
        _tiered_cost(
            input_tokens,
            input_cost,
            _as_float(prices.get("input_cost_per_token_above_200k_tokens")),
        )
        + _tiered_cost(
            output_tokens,
            output_cost,
            _as_float(prices.get("output_cost_per_token_above_200k_tokens")),
        )
        + _tiered_cost(
            cache_write_tokens,
            cache_write_cost,
            _as_float(prices.get("cache_creation_input_token_cost_above_200k_tokens")),
        )
        + _tiered_cost(
            cache_read_tokens,
            cache_read_cost,
            _as_float(prices.get("cache_read_input_token_cost_above_200k_tokens")),
        )
    )


def _date_from_entry(entry: dict[str, Any], fallback: str) -> str:
    timestamp = entry.get("timestamp")
    if not isinstance(timestamp, str):
        return fallback
    try:
        return (
            datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
            .astimezone(UTC)
            .strftime("%Y-%m-%d")
        )
    except ValueError:
        return fallback


def _entry_request_id(entry: dict[str, Any]) -> str:
    request_id = entry.get("requestId")
    if isinstance(request_id, str) and request_id:
        return request_id
    message = entry.get("message")
    if isinstance(message, dict):
        message_id = message.get("id")
        if isinstance(message_id, str) and message_id:
            return message_id
    uuid = entry.get("uuid")
    return str(uuid) if uuid else json.dumps(entry, sort_keys=True)


def _is_cursor_entrypoint(value: object) -> bool:
    return isinstance(value, str) and "cursor" in value.lower()


def _is_cursor_payload(
    payload: dict[str, Any],
    transcript_path: Path | None,
    entries: Iterable[dict[str, Any]] = (),
) -> bool:
    if transcript_path and ".cursor" in transcript_path.parts:
        return True
    if _is_cursor_entrypoint(payload.get("entrypoint")):
        return True
    for entry in entries:
        if _is_cursor_entrypoint(entry.get("entrypoint")):
            return True
    return bool(payload.get("conversation_id") and payload.get("workspace_roots"))


def _is_claude_agent_acp_payload(
    payload: dict[str, Any],
    entries: Iterable[dict[str, Any]],
    env: dict[str, str] | None = None,
) -> bool:
    env = os.environ if env is None else env
    # claude-agent-acp reports entrypoint "sdk-ts" (shared with other TS-SDK
    # usage), so entrypoint alone can't identify it. nvim launches the process
    # with CLAUDE_AGENT_ACP=1, which this hook inherits, to mark sessions it
    # already tracks in its own spend accounting and that we must not double-count.
    if env.get("CLAUDE_AGENT_ACP") == "1":
        return True
    entrypoint = payload.get("entrypoint")
    if isinstance(entrypoint, str) and entrypoint == "claude-agent-acp":
        return True
    for entry in entries:
        entry_entrypoint = entry.get("entrypoint")
        if isinstance(entry_entrypoint, str) and entry_entrypoint == "claude-agent-acp":
            return True
    return False


def _load_transcript(path: Path) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    try:
        with path.open(encoding="utf-8") as f:
            for line in f:
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(entry, dict):
                    entries.append(entry)
    except OSError:
        pass
    return entries


def _assistant_costs(
    entries: Iterable[dict[str, Any]], today: str, pricing: dict[str, Any]
) -> list[tuple[str, str, float]]:
    seen_in_transcript: set[str] = set()
    costs: list[tuple[str, str, float]] = []
    for entry in entries:
        if entry.get("type") != "assistant":
            continue
        message = entry.get("message")
        if not isinstance(message, dict) or message.get("role") != "assistant":
            continue
        request_id = _entry_request_id(entry)
        if request_id in seen_in_transcript:
            continue
        seen_in_transcript.add(request_id)
        cost = _cost_from_usage(message, pricing)
        if cost <= 0:
            continue
        costs.append((request_id, _date_from_entry(entry, today), cost))
    return costs


def _load_state(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"sessions": {}}
    return data if isinstance(data, dict) else {"sessions": {}}


def _write_state(path: Path, state: dict[str, Any]) -> None:
    path.write_text(json.dumps(state, sort_keys=True), encoding="utf-8")


def _add_daily_total(spend_dir: Path, day: str, amount: float) -> None:
    daily_file = spend_dir / f"daily-{day}"
    current = 0.0
    try:
        current = float(daily_file.read_text(encoding="utf-8") or "0")
    except (OSError, ValueError):
        current = 0.0
    daily_file.write_text(f"{current + amount:.4f}", encoding="utf-8")


def track_claude_spend(
    payload: dict[str, Any], *, data_home: Path | None = None, today: str | None = None
) -> None:
    """Record new Claude CLI transcript costs in the shared spend store."""
    transcript_raw = payload.get("transcript_path")
    transcript_path = (
        Path(transcript_raw).expanduser()
        if isinstance(transcript_raw, str) and transcript_raw
        else None
    )
    if _is_cursor_payload(payload, transcript_path):
        return
    if not transcript_path or not transcript_path.is_file():
        return

    entries = _load_transcript(transcript_path)
    if _is_cursor_payload(payload, transcript_path, entries):
        return
    if _is_claude_agent_acp_payload(payload, entries):
        return

    today = today or datetime.now(UTC).strftime("%Y-%m-%d")
    try:
        pricing = _fetch_litellm_pricing()
    except (OSError, json.JSONDecodeError):
        return
    costs = _assistant_costs(entries, today, pricing)
    if not costs:
        return

    root = data_home or Path(
        os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")
    )
    spend_dir = root / SPEND_SUBDIR
    spend_dir.mkdir(parents=True, exist_ok=True)

    session_id = payload.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        session_id = transcript_path.stem

    lock_path = spend_dir / LOCK_FILE
    with lock_path.open("w", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state_path = spend_dir / STATE_FILE
        state = _load_state(state_path)
        sessions = state.setdefault("sessions", {})
        if not isinstance(sessions, dict):
            sessions = {}
            state["sessions"] = sessions
        session_state = sessions.setdefault(session_id, {})
        if not isinstance(session_state, dict):
            session_state = {}
            sessions[session_id] = session_state
        seen_raw = session_state.setdefault("seen_requests", [])
        seen = set(seen_raw if isinstance(seen_raw, list) else [])

        new_seen = list(seen)
        by_day: dict[str, float] = {}
        for request_id, day, cost in costs:
            if request_id in seen:
                continue
            by_day[day] = by_day.get(day, 0.0) + cost
            new_seen.append(request_id)

        if by_day:
            for day, amount in by_day.items():
                _add_daily_total(spend_dir, day, amount)
            session_state["seen_requests"] = new_seen[-1000:]
            _write_state(state_path, state)


def main() -> None:
    """Read a Claude Stop hook payload from stdin and track spend."""
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return _output()
    if isinstance(payload, dict):
        track_claude_spend(payload)
    _output()


if __name__ == "__main__":
    main()
