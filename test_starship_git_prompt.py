"""Keep the git prompt's visual module order when work moves to async rendering."""

import tomllib
import unittest
from pathlib import Path


CONFIG = Path(__file__).parent / "dot_config"


class StarshipGitPromptTests(unittest.TestCase):
    def test_git_prompt_preserves_module_order(self) -> None:
        before = tomllib.loads((CONFIG / "starship_before_git_status.toml").read_text())
        async_git = tomllib.loads((CONFIG / "starship_git_status.toml").read_text())

        self.assertEqual(before["format"].strip(), "$git_branch")
        self.assertEqual(
            async_git["format"], "$git_commit$git_state$git_metrics$git_status"
        )


if __name__ == "__main__":
    unittest.main()
