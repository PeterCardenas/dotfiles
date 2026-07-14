from __future__ import annotations

from pathlib import Path
import runpy
import unittest


JIRA_SEARCH = Path(__file__).parents[1] / "bin" / "executable_jira-search"


class JiraSearchEntrypointTests(unittest.TestCase):
    def test_allows_atlassian_resource_discovery(self) -> None:
        module = runpy.run_path(str(JIRA_SEARCH))

        self.assertIn(
            "mcp__claude_ai_Atlassian__getAccessibleAtlassianResources",
            module["ALLOWED_TOOLS"],
        )
