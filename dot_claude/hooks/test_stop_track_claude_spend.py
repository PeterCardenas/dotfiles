#!/usr/bin/env python3
"""Tests for stop_track_claude_spend.py.

Covers standalone-CLI cost tracking + request dedup, the cursor skips, and the
claude-agent-acp skip guard.

Regression context for the claude-agent-acp skip: claude-agent-acp reports
entrypoint "sdk-ts" (shared with other TS-SDK usage), so
`_is_claude_agent_acp_payload` can never identify it from entrypoint alone.
nvim launches claude-agent-acp with CLAUDE_AGENT_ACP=1 (see sg.lua's
acp_providers['claude-agent-acp'].env) so this hook can reliably skip those
sessions instead of double-counting spend nvim's agentic config already tracks.

Not given an `executable_` chezmoi prefix so it deploys as a plain,
non-executable file.
"""

from __future__ import annotations

import importlib.util
import io
import json
import os
import tempfile
import unittest
from unittest import mock
from pathlib import Path


# Load from the chezmoi source script (not the `~/.claude/hooks` deployed copy)
# so the test always exercises the change under review, even before a
# `chezmoi apply` has synced it to the deployed path.
SCRIPT_PATH = Path(__file__).with_name("executable_stop_track_claude_spend.py")


def load_module():
    spec = importlib.util.spec_from_file_location("stop_track_claude_spend", SCRIPT_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ClaudeAgentAcpGuardTest(unittest.TestCase):
    """Unit tests for the `_is_claude_agent_acp_payload` skip guard."""

    def setUp(self) -> None:
        self.module = load_module()

    def test_env_marker_identifies_claude_agent_acp(self) -> None:
        self.assertTrue(
            self.module._is_claude_agent_acp_payload(
                {}, [], env={"CLAUDE_AGENT_ACP": "1"}
            )
        )

    def test_no_env_marker_and_no_entrypoint_is_not_claude_agent_acp(self) -> None:
        self.assertFalse(self.module._is_claude_agent_acp_payload({}, [], env={}))

    def test_legacy_entrypoint_still_recognized(self) -> None:
        self.assertTrue(
            self.module._is_claude_agent_acp_payload(
                {"entrypoint": "claude-agent-acp"}, [], env={}
            )
        )

    def test_sdk_ts_entrypoint_alone_is_not_enough(self) -> None:
        """Regression for the actual bug: claude-agent-acp reports entrypoint
        "sdk-ts" (shared with other TS-SDK usage), so entrypoint alone must NOT
        identify it -- only the CLAUDE_AGENT_ACP env marker can.
        """
        self.assertFalse(
            self.module._is_claude_agent_acp_payload(
                {"entrypoint": "sdk-ts"}, [], env={}
            )
        )


class TrackClaudeSpendTest(unittest.TestCase):
    """End-to-end tests exercising `track_claude_spend`."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.data_home = self.root / "data"
        self.transcript = self.root / "session.jsonl"
        self.module = load_module()
        # These tests exercise the non-ACP path, but the suite is often run from
        # inside an ACP session (nvim), where an inherited CLAUDE_AGENT_ACP=1
        # would make every payload get skipped.
        env = mock.patch.dict(os.environ, {}, clear=False)
        env.start()
        self.addCleanup(env.stop)
        os.environ.pop("CLAUDE_AGENT_ACP", None)

    def write_transcript(self, entries: list[dict]) -> None:
        self.transcript.write_text(
            "\n".join(json.dumps(entry) for entry in entries) + "\n",
            encoding="utf-8",
        )

    def payload(self, **overrides: object) -> dict:
        data = {
            "hook_event_name": "Stop",
            "session_id": "claude-session-1",
            "transcript_path": str(self.transcript),
        }
        data.update(overrides)
        return data

    def read_daily_total(self) -> str:
        return (self.data_home / "claude-spend" / "daily-2026-06-06").read_text(
            encoding="utf-8"
        )

    def _assistant_entry(self, entrypoint: str, request_id: str = "req_1") -> dict:
        return {
            "type": "assistant",
            "entrypoint": entrypoint,
            "sessionId": "claude-session-1",
            "requestId": request_id,
            "timestamp": "2026-06-06T18:32:26.000Z",
            "message": {
                "model": "claude-sonnet-4-5-20250929",
                "role": "assistant",
                "stop_reason": "end_turn",
                "usage": {
                    "input_tokens": 1_000_000,
                    "cache_creation_input_tokens": 1_000_000,
                    "cache_read_input_tokens": 1_000_000,
                    "output_tokens": 1_000_000,
                },
            },
        }

    def _pricing_urlopen(self):
        pricing_payload = json.dumps(
            {
                "claude-sonnet-4-5-20250929": {
                    "input_cost_per_token": 0.000003,
                    "cache_creation_input_token_cost": 0.00000375,
                    "cache_read_input_token_cost": 0.0000003,
                    "output_cost_per_token": 0.000015,
                }
            }
        ).encode()
        return mock.patch.object(
            self.module.urllib.request,
            "urlopen",
            side_effect=lambda *_args, **_kwargs: io.BytesIO(pricing_payload),
        )

    def test_tracks_standalone_claude_transcript_cost_once(self) -> None:
        # Two identical entries with the same requestId must be deduped.
        self.write_transcript(
            [self._assistant_entry("sdk-cli"), self._assistant_entry("sdk-cli")]
        )
        with self._pricing_urlopen() as urlopen:
            self.module.track_claude_spend(
                self.payload(), data_home=self.data_home, today="2026-06-06"
            )
            self.module.track_claude_spend(
                self.payload(), data_home=self.data_home, today="2026-06-06"
            )

        self.assertEqual("22.0500", self.read_daily_total())
        self.assertEqual(2, urlopen.call_count)

    def test_skips_cursor_agent_stop_payloads(self) -> None:
        cursor_transcript = (
            self.root
            / ".cursor"
            / "projects"
            / "repo"
            / "agent-transcripts"
            / "conv"
            / "conv.jsonl"
        )
        cursor_transcript.parent.mkdir(parents=True)
        cursor_transcript.write_text(
            json.dumps({"role": "assistant", "message": {"content": "done"}}) + "\n",
            encoding="utf-8",
        )

        self.module.track_claude_spend(
            {
                "hook_event_name": "Stop",
                "conversation_id": "conv",
                "workspace_roots": [str(self.root)],
                "transcript_path": str(cursor_transcript),
            },
            data_home=self.data_home,
            today="2026-06-06",
        )

        self.assertFalse((self.data_home / "claude-spend").exists())

    def test_skips_cursor_agent_entrypoint_payloads(self) -> None:
        self.write_transcript(
            [
                {
                    "type": "assistant",
                    "entrypoint": "cursor-agent-cli",
                    "sessionId": "cursor-session-1",
                    "requestId": "req_cursor",
                    "message": {
                        "model": "claude-sonnet-4-5-20250929",
                        "role": "assistant",
                        "stop_reason": "end_turn",
                        "usage": {"input_tokens": 1_000_000},
                    },
                }
            ]
        )

        self.module.track_claude_spend(
            self.payload(entrypoint="cursor-agent-cli"),
            data_home=self.data_home,
            today="2026-06-06",
        )

        self.assertFalse((self.data_home / "claude-spend").exists())

    def test_skips_claude_agent_acp_entrypoint_payloads(self) -> None:
        # Legacy path: an explicit "claude-agent-acp" entrypoint is still skipped.
        self.write_transcript(
            [
                {
                    "type": "assistant",
                    "entrypoint": "claude-agent-acp",
                    "sessionId": "claude-session-1",
                    "requestId": "req_1",
                    "message": {
                        "model": "claude-sonnet-4-5-20250929",
                        "role": "assistant",
                        "stop_reason": "end_turn",
                        "usage": {"input_tokens": 1_000_000},
                    },
                }
            ]
        )

        self.module.track_claude_spend(
            self.payload(entrypoint="claude-agent-acp"),
            data_home=self.data_home,
            today="2026-06-06",
        )

        self.assertFalse((self.data_home / "claude-spend").exists())

    def test_skips_claude_agent_acp_via_env_marker(self) -> None:
        # The real-world case: entrypoint is "sdk-ts" but nvim set CLAUDE_AGENT_ACP=1,
        # so the hook must skip it (nvim already tracks this spend).
        self.write_transcript([self._assistant_entry("sdk-ts")])
        with mock.patch.dict(
            self.module.os.environ, {"CLAUDE_AGENT_ACP": "1"}
        ), self._pricing_urlopen():
            self.module.track_claude_spend(
                self.payload(entrypoint="sdk-ts"),
                data_home=self.data_home,
                today="2026-06-06",
            )

        self.assertFalse((self.data_home / "claude-spend").exists())

    def test_tracks_sdk_ts_without_env_marker(self) -> None:
        # Precision guard: a bare "sdk-ts" session without the marker is NOT
        # claude-agent-acp, so it must still be tracked (no over-skipping).
        self.write_transcript([self._assistant_entry("sdk-ts")])
        # clear=True guarantees CLAUDE_AGENT_ACP is absent regardless of the
        # ambient environment.
        with mock.patch.dict(
            self.module.os.environ, {}, clear=True
        ), self._pricing_urlopen():
            self.module.track_claude_spend(
                self.payload(entrypoint="sdk-ts"),
                data_home=self.data_home,
                today="2026-06-06",
            )

        self.assertEqual("22.0500", self.read_daily_total())


class MultiBlockRequestTest(unittest.TestCase):
    """One billed request split across several transcript entries.

    Regression: Claude Code writes one entry per content block, all sharing a
    requestId, with a running `output_tokens`. The hook used to keep the first
    copy, so a request's output was billed at whatever the first block had
    reached — a systematic undercount of the priciest component.
    """

    PRICING = {
        "claude-opus-5": {
            "input_cost_per_token": 0.000005,
            "output_cost_per_token": 0.000025,
            "cache_creation_input_token_cost": 0.00000625,
            "cache_read_input_token_cost": 0.0000005,
        }
    }

    def setUp(self) -> None:
        self.module = load_module()

    def entry(self, output_tokens: int, block: str) -> dict:
        return {
            "type": "assistant",
            "requestId": "req_1",
            "timestamp": "2026-06-06T18:32:26.000Z",
            "message": {
                "model": "claude-opus-5",
                "role": "assistant",
                "content": [{"type": block}],
                "usage": {
                    "input_tokens": 0,
                    "cache_creation_input_tokens": 0,
                    "cache_read_input_tokens": 0,
                    "output_tokens": output_tokens,
                },
            },
        }

    def costs(self, entries: list[dict]) -> list[tuple[str, str, float]]:
        return self.module._assistant_costs(entries, "2026-06-06", self.PRICING)

    def test_running_output_tokens_bills_the_final_total(self) -> None:
        costs = self.costs(
            [
                self.entry(7, "thinking"),
                self.entry(7, "tool_use"),
                self.entry(297, "tool_use"),
            ]
        )
        self.assertEqual(1, len(costs))
        self.assertAlmostEqual(297 * 0.000025, costs[0][2])

    def test_out_of_order_copies_still_bill_the_largest(self) -> None:
        costs = self.costs([self.entry(297, "text"), self.entry(7, "thinking")])
        self.assertEqual(1, len(costs))
        self.assertAlmostEqual(297 * 0.000025, costs[0][2])

    def test_date_comes_from_the_first_copy(self) -> None:
        # A response streaming across midnight must bill to the day it started.
        first = self.entry(7, "thinking")
        second = self.entry(297, "text")
        second["timestamp"] = "2026-06-07T00:00:05.000Z"
        costs = self.costs([first, second])
        self.assertEqual([("req_1", "2026-06-06", 297 * 0.000025)], costs)

    def test_distinct_requests_are_kept_separate(self) -> None:
        second = self.entry(100, "text")
        second["requestId"] = "req_2"
        costs = self.costs([self.entry(50, "text"), second])
        self.assertEqual(["req_1", "req_2"], [c[0] for c in costs])
        self.assertAlmostEqual(150 * 0.000025, sum(c[2] for c in costs))


class CacheWriteTtlPricingTest(unittest.TestCase):
    """Cache-creation tokens must be priced by their TTL.

    Regression: every cache write used to be billed at the 5-minute rate. Claude
    Code writes 1-hour caches, which Anthropic bills at 2x base input instead of
    1.25x, so the hook under-reported real spend by ~17% overall.
    """

    PRICES = {
        "input_cost_per_token": 0.000005,
        "output_cost_per_token": 0.000025,
        "cache_creation_input_token_cost": 0.00000625,
        "cache_creation_input_token_cost_above_1hr": 0.00001,
        "cache_read_input_token_cost": 0.0000005,
    }

    def setUp(self) -> None:
        self.module = load_module()
        self.pricing = {"claude-opus-5": dict(self.PRICES)}

    def cost(self, usage: dict) -> float:
        return self.module._cost_from_usage(
            {"model": "claude-opus-5", "usage": usage}, self.pricing
        )

    def test_one_hour_cache_writes_use_the_one_hour_rate(self) -> None:
        cost = self.cost(
            {
                "cache_creation_input_tokens": 1_000_000,
                "cache_creation": {
                    "ephemeral_1h_input_tokens": 1_000_000,
                    "ephemeral_5m_input_tokens": 0,
                },
            }
        )
        self.assertAlmostEqual(10.0, cost)

    def test_five_minute_cache_writes_use_the_five_minute_rate(self) -> None:
        cost = self.cost(
            {
                "cache_creation_input_tokens": 1_000_000,
                "cache_creation": {
                    "ephemeral_1h_input_tokens": 0,
                    "ephemeral_5m_input_tokens": 1_000_000,
                },
            }
        )
        self.assertAlmostEqual(6.25, cost)

    def test_mixed_ttls_are_priced_separately(self) -> None:
        cost = self.cost(
            {
                "cache_creation_input_tokens": 1_000_000,
                "cache_creation": {
                    "ephemeral_1h_input_tokens": 400_000,
                    "ephemeral_5m_input_tokens": 600_000,
                },
            }
        )
        self.assertAlmostEqual(400_000 * 0.00001 + 600_000 * 0.00000625, cost)

    def test_missing_breakdown_falls_back_to_five_minute_rate(self) -> None:
        # Older transcripts report only the total, with no `cache_creation` map.
        self.assertAlmostEqual(
            6.25, self.cost({"cache_creation_input_tokens": 1_000_000})
        )

    def test_model_without_one_hour_price_falls_back_to_base_rate(self) -> None:
        self.pricing["claude-opus-5"].pop(
            "cache_creation_input_token_cost_above_1hr"
        )
        cost = self.cost(
            {
                "cache_creation_input_tokens": 1_000_000,
                "cache_creation": {"ephemeral_1h_input_tokens": 1_000_000},
            }
        )
        self.assertAlmostEqual(6.25, cost)


if __name__ == "__main__":
    unittest.main()
