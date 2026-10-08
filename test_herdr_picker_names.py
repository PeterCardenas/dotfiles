"""Regression checks for the custom Herdr workspace switcher's displayed names."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

PICKER = Path(__file__).parent / "dot_config/fish/functions/manage_herdr_sessions.fish"


class HerdrPickerNamesTest(unittest.TestCase):
    def test_grouped_auto_worktree_uses_sidebar_branch_but_custom_and_standalone_keep_labels(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            rows_file = root / "rows"
            calls_file = root / "calls"
            (root / ".config/herdr").mkdir(parents=True)
            (bin_dir / "herdr").write_text(
                "#!/bin/sh\n"
                f"printf '%s\\n' \"$*\" >> '{calls_file}'\n"
                "case \"$1 $2\" in\n"
                "  'workspace list') printf '%s\\n' '{\"result\":{\"workspaces\":["
                "{\"workspace_id\":\"base\",\"label\":\"Repo\",\"number\":1,\"worktree\":{\"repo_key\":\"repo\",\"is_linked_worktree\":false}},"
                "{\"workspace_id\":\"auto\",\"label\":\"checkout\",\"number\":2,\"worktree\":{\"repo_key\":\"repo\",\"is_linked_worktree\":true,\"checkout_path\":\"/repo/checkout\"}},"
                "{\"workspace_id\":\"custom\",\"label\":\"Review notes\",\"number\":3,\"worktree\":{\"repo_key\":\"repo\",\"is_linked_worktree\":true,\"checkout_path\":\"/repo/review\"}},"
                "{\"workspace_id\":\"alone\",\"label\":\"solo\",\"number\":4,\"worktree\":{\"repo_key\":\"other\",\"is_linked_worktree\":true,\"checkout_path\":\"/other/solo\"}},"
                "{\"workspace_id\":\"focused\",\"label\":\"Active\",\"focused\":true,\"number\":5}]}}' ;;\n"
                "  'worktree list') printf '%s\\n' '{\"result\":{\"worktrees\":[{\"open_workspace_id\":\"auto\",\"branch\":\"worktree/feature/real-title\"}]}}' ;;\n"
                "esac\n"
            )
            (bin_dir / "fzf").write_text(f"#!/bin/sh\ntee '{rows_file}' | head -n 1\n")
            (bin_dir / "tput").write_text("#!/bin/sh\nprintf '100\\n'\n")
            for executable in ("herdr", "fzf", "tput"):
                (bin_dir / executable).chmod(0o755)
            result = subprocess.run(
                ["fish", "--no-config", "-c", f"set fish_function_path {PICKER.parent}; manage_herdr_sessions"],
                env={**os.environ, "HOME": directory, "PATH": f"{bin_dir}:{os.environ['PATH']}"},
                text=True, capture_output=True, timeout=10,
            )
            rows = rows_file.read_text().splitlines()
            calls = calls_file.read_text().splitlines()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([row.split("\t", 1)[0] for row in rows], ["auto", "custom", "alone"])
        self.assertIn("feature/real-title", rows[0])
        self.assertNotIn("worktree/", rows[0])
        self.assertIn("Review notes", rows[1])
        self.assertIn("solo", rows[2])
        self.assertEqual(calls, ["workspace list", "worktree list --workspace auto", "workspace focus auto"])


if __name__ == "__main__":
    unittest.main()
