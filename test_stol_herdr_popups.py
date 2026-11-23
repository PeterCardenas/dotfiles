"""stol-aware Herdr popup checks using real local Git repos; only herdr, stol and fzf are stubbed.

The real stol needs a reflink filesystem, so a stub emulates its worktree layout
(`<project>/<branch with / as -->`) with plain git worktrees.
"""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parent
FUNCTIONS = ROOT / "dot_config/fish/functions"
GIT_IDENTITY = ["-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgSign=false"]


class StolHerdrPopupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.stol_root = root / "work"
        self.project = self.stol_root / "projects/example"
        self.repo = self.project / ".repo"
        self.calls = root / "calls"
        remote = root / "remote.git"
        self.git("init", "-q", "--bare", "-b", "main", str(remote))
        self.git("clone", "-q", str(remote), str(self.repo))
        self.git("-C", str(self.repo), *GIT_IDENTITY, "commit", "-q", "--allow-empty", "-m", "initial")
        self.git("-C", str(self.repo), "push", "-q", "origin", "main")
        self.git("-C", str(self.repo), "remote", "set-head", "origin", "-a")
        self.git("-C", str(self.repo), "switch", "-q", "--detach")
        self.git("-C", str(self.repo), "worktree", "add", "-q", str(self.project / "00-main"), "main")
        # A newer origin/main proves popups branch from the fetched default and refresh the template.
        other = root / "other"
        self.git("clone", "-q", str(remote), str(other))
        self.git("-C", str(other), *GIT_IDENTITY, "commit", "-q", "--allow-empty", "-m", "latest")
        self.git("-C", str(other), "push", "-q", "origin", "main")
        self.latest = self.git("-C", str(other), "rev-parse", "HEAD")

        bin_dir = root / "bin"
        bin_dir.mkdir()
        self.executable(bin_dir / "herdr", f"""
case "$1 $2" in
  'workspace list') cat <<'JSON'
{{"result":{{"workspaces":[
  {{"workspace_id":"w-parent","label":"example","worktree":{{"repo_key":"{self.repo}/.git","is_linked_worktree":false}}}},
  {{"workspace_id":"w-child","label":"task","worktree":{{"repo_key":"{self.repo}/.git","is_linked_worktree":true,"checkout_path":"{self.project}/task"}}}}]}}}}
JSON
  ;;
  'worktree list') printf '%s\\n' "$WORKTREE_LIST" ;;
  *) printf '%s\\n' "$*" >> '{self.calls}' ;;
esac
""")
        self.executable(bin_dir / "stol", f"""
printf '%s|%s|%s\\n' "$*" "$PWD" "$STOL_ROOT" >> '{self.calls}.stol'
case "$1" in
  new) name=$(printf '%s' "$3" | sed 's|/|--|g'); git -C .repo worktree add -q "$PWD/$name" "$3" >&2 && printf '%s\\n' "$PWD/$name" ;;
  rm) [ -n "$STOL_RM_FAIL" ] && exit 1; git -C .repo worktree remove --force "$PWD/$2" >&2 && printf 'stol rm %s\\n' "$2" >> '{self.calls}' ;;
esac
""")
        self.executable(bin_dir / "fzf", "head -n 1\n")
        self.env = {
            **os.environ,
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
            "HERDR_ACTIVE_WORKSPACE_ID": "w-child",
            "WORKTREE_LIST": f'{{"result":{{"source":{{"source_workspace_id":"w-parent","source_checkout_path":"{self.repo}"}}}}}}',
        }
        self.env.pop("STOL_ROOT", None)
        self.shared_hooks = root / "home/.config/stol/hooks"
        self.shared_hooks.mkdir(parents=True)
        self.env["HOME"] = str(root / "home")

    @staticmethod
    def executable(path, body):
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)

    @staticmethod
    def git(*args):
        return subprocess.check_output(["git", *args], text=True, stderr=subprocess.PIPE).strip()

    def popup(self, function, answer, **env):
        return subprocess.run(
            ["fish", "--no-config", "-c", f"set fish_function_path {FUNCTIONS} $fish_function_path; {function}"],
            input=answer, env={**self.env, **env}, text=True, capture_output=True, timeout=30,
        )

    def lines(self, suffix=""):
        path = Path(f"{self.calls}{suffix}")
        return path.read_text().splitlines() if path.exists() else []

    def test_new_branch_is_created_through_stol_from_latest_default(self):
        result = self.popup("herdr_new_worktree", "feature/new\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        worktree = self.project / "feature--new"
        # stol runs from the project dir with STOL_ROOT derived from it, not inherited.
        self.assertEqual(self.lines(".stol"), [f"new --existing feature/new|{self.project}|{self.stol_root}"])
        self.assertEqual(self.lines(), [f"worktree open --workspace w-parent --path {worktree} --focus"])
        self.assertEqual(self.git("-C", str(worktree), "rev-parse", "HEAD"), self.latest)
        self.assertEqual(self.git("-C", str(self.project / "00-main"), "rev-parse", "HEAD"), self.latest)
        # The fish stol wrapper gives projects without hooks the shared cleanup hooks.
        self.assertEqual((self.project / ".stol/hooks").readlink(), self.shared_hooks)

    def test_stol_groups_reject_detached_checkouts(self):
        result = self.popup("herdr_new_worktree", "\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("stol worktrees need a branch", result.stderr)
        self.assertEqual(self.lines(".stol"), [])
        self.assertEqual(self.lines(), [])

    def test_close_removes_stol_worktree_with_stol_rm(self):
        self.git("-C", str(self.repo), "worktree", "add", "-q", "-b", "task", str(self.project / "task"), "main")
        listing = (f'{{"result":{{"worktrees":[{{"open_workspace_id":"w-child","path":"{self.project}/task",'
                   '"is_linked_worktree":true,"is_bare":false}]}}')
        result = self.popup("herdr_close_workspace", "y\n", WORKTREE_LIST=listing)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.lines(".stol"), [f"rm task --force|{self.project}|{self.stol_root}"])
        self.assertFalse((self.project / "task").exists())
        # Focus stays on the closing workspace until the slow stol rm finishes.
        self.assertEqual(self.lines(), ["stol rm task", "workspace focus w-parent", "workspace close w-child"])

    def test_failed_stol_rm_keeps_focus_and_workspace(self):
        self.git("-C", str(self.repo), "worktree", "add", "-q", "-b", "task", str(self.project / "task"), "main")
        listing = (f'{{"result":{{"worktrees":[{{"open_workspace_id":"w-child","path":"{self.project}/task",'
                   '"is_linked_worktree":true,"is_bare":false}]}}')
        result = self.popup("herdr_close_workspace", "y\n\n", WORKTREE_LIST=listing, STOL_RM_FAIL="1")
        self.assertEqual(result.returncode, 1)
        self.assertTrue((self.project / "task").is_dir())
        self.assertEqual(self.lines(), [])

    def test_close_never_removes_a_stol_template(self):
        listing = (f'{{"result":{{"worktrees":[{{"open_workspace_id":"w-child","path":"{self.project}/00-main",'
                   '"is_linked_worktree":true,"is_bare":false}]}}')
        result = self.popup("herdr_close_workspace", "y\n", WORKTREE_LIST=listing)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("stol template", result.stderr)
        self.assertEqual(self.lines(".stol"), [])
        self.assertTrue((self.project / "00-main").is_dir())
        self.assertEqual(self.lines(), ["workspace focus w-parent", "workspace close w-child"])


if __name__ == "__main__":
    unittest.main()
