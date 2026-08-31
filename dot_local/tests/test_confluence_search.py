from __future__ import annotations

from pathlib import Path
import runpy
import unittest


CONFLUENCE_SEARCH = Path(__file__).parents[1] / "bin" / "executable_confluence-search"


class ConfluenceSearchEntrypointTests(unittest.TestCase):
    def test_allows_reading_confluence_pages(self) -> None:
        module = runpy.run_path(str(CONFLUENCE_SEARCH))

        self.assertIn(
            "mcp__claude_ai_Atlassian__getConfluencePage",
            module["ALLOWED_TOOLS"],
        )
        self.assertIn(
            "mcp__claude_ai_Atlassian__getAccessibleAtlassianResources",
            module["ALLOWED_TOOLS"],
        )


if __name__ == "__main__":
    unittest.main()
