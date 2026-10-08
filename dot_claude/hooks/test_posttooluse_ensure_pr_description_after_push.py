from __future__ import annotations

import unittest

from executable_posttooluse_ensure_pr_description_after_push import _advisory


class PushPrDescriptionGuidanceTest(unittest.TestCase):
    def test_guidance_covers_decision_and_latest_visual_evidence(self) -> None:
        output = _advisory({"number": 42, "title": "Old title", "url": "https://github.com/org/repo/pull/42"})
        guidance = output["hookSpecificOutput"]["additionalContext"]

        self.assertIn("title", guidance)
        self.assertIn("concise", guidance)
        self.assertIn("rationale", guidance)
        self.assertIn("investigated", guidance)
        self.assertIn("why", guidance)
        self.assertIn("latest", guidance)
        self.assertIn("screenshots", guidance)
        self.assertIn("screen recording", guidance)
        self.assertIn("upload", guidance)
        self.assertIn("pr-add-screenshots", guidance)
        self.assertIn("browser-evidence", guidance)


if __name__ == "__main__":
    unittest.main()
