"""The global git config is the concatenation of every chezmoi source's config.d fragment."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parent
MODIFY = ROOT / "dot_config/git/modify_config.tmpl"


class GitConfigFragmentsTest(unittest.TestCase):
    def test_modify_script_keeps_other_sources_fragments(self):
        script = subprocess.check_output(
            ["chezmoi", "--source", str(ROOT), "execute-template"], stdin=MODIFY.open(), text=True
        )
        with tempfile.TemporaryDirectory() as home:
            fragments = Path(home) / ".config/git/config.d"
            fragments.mkdir(parents=True)
            (fragments / "other-source").write_text("[maintenance]\n\trepo = /srv/other/.repo\n")
            merged = subprocess.run(
                ["bash", "-c", script], input="stale target contents\n", text=True,
                capture_output=True, check=True, env={**os.environ, "HOME": home},
            ).stdout
            config = Path(home) / "config"
            config.write_text(merged)
            git_env = {**os.environ, "GIT_CONFIG_GLOBAL": str(config), "GIT_CONFIG_NOSYSTEM": "1"}

            def get(*key):
                return subprocess.check_output(["git", "config", "--global", *key], env=git_env, text=True).strip()

            self.assertNotIn("stale target contents", merged)
            self.assertEqual(get("--get-all", "maintenance.repo"), "/srv/other/.repo")
            self.assertEqual(get("user.name"), "Peter Cardenas")
            self.assertTrue((fragments / "chezmoi").is_file())


if __name__ == "__main__":
    unittest.main()
