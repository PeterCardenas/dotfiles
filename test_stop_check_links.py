from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path


HOOK_PATH = Path(__file__).parent / "dot_claude/hooks/executable_stop_check_links.py"


class StopCheckLinksHookTest(unittest.TestCase):
    def _run_hook(
        self, last_assistant_message: str, *, cursor: bool = False
    ) -> dict[str, object]:
        self.assertTrue(HOOK_PATH.exists(), f"missing hook: {HOOK_PATH}")
        payload = {
            "last_assistant_message": last_assistant_message,
            "stop_reason": "end_turn",
        }
        if cursor:
            payload["cursor_version"] = "3.11.19"
        result = subprocess.run(
            [sys.executable, str(HOOK_PATH)],
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            check=True,
        )
        return json.loads(result.stdout)

    def test_allows_markdown_key_references_heading_without_colon(self) -> None:
        message = (
            "Fixed the hook behavior and kept the change deliberately small. "
            "This sentence pads the response past the non-trivial threshold so "
            "the hook must make its decision from the references marker. The "
            "important part is that a normal markdown heading should count as "
            "the references section even without a trailing colon.\n\n"
            "## Key References\n"
            "- `dot_claude/hooks/executable_stop_check_links.py`"
        )

        self.assertEqual(self._run_hook(message), {})

    def test_long_response_without_references_still_blocks(self) -> None:
        message = (
            "This answer is intentionally long enough to avoid the trivial-response "
            "skip and it does not include a key references heading, URLs, or any "
            "other marker that should satisfy the stop hook link reminder."
        )

        self.assertEqual(self._run_hook(message).get("decision"), "block")

    def test_cursor_block_reason_is_hidden_markdown_comment(self) -> None:
        message = (
            "This answer is intentionally long enough to avoid the trivial-response "
            "skip and it does not include a key references heading, URLs, or any "
            "other marker that should satisfy the stop hook link reminder."
        )

        output = self._run_hook(message, cursor=True)

        self.assertEqual(output.get("decision"), "block")
        self.assertTrue(str(output.get("reason", "")).startswith("<!--"))
        self.assertIn("Begin the suffix with EXACTLY two newline characters", output["reason"])
        self.assertIn("output only an additional suffix, not a rewrite", output["reason"])
        self.assertNotIn("Your final response has no reference links", output["reason"])


if __name__ == "__main__":
    unittest.main()
