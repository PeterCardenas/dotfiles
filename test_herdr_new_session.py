"""Picker-to-clone checks using local Git repos, with only UI/GitHub APIs stubbed."""
import json
import os
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parent
FUNCTIONS = ROOT / "dot_config/fish/functions"


class HerdrNewSessionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / "bin"
        self.bin.mkdir()
        self.calls = self.home / "calls"
        self.rows = self.home / "rows"
        self.projects = self.home / "projects"
        self.env = {
            **os.environ, "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "GIT_CONFIG_GLOBAL": str(self.home / ".gitconfig"),
            "GIT_CONFIG_NOSYSTEM": "1",
            "HERDR_ACTIVE_WORKSPACE_ID": "w-active",
        }
        self.remote = self.home / "remote/example.git"
        self.git("init", "-q", "-b", "main", str(self.remote))
        self.git("-C", str(self.remote), "-c", "user.name=Test", "-c", "user.email=test@example.com",
                 "-c", "commit.gpgSign=false", "commit", "-q", "--allow-empty", "-m", "initial")
        identity = self.home / ".config/git/identities/personal"
        identity.parent.mkdir(parents=True)
        identity.write_text("[user]\nemail = test@example.com\nsigningkey = test-key\n")
        self.git("config", "--global", f"url.{self.home / 'remote'}/.insteadOf", "personal-github.com:owner/")
        self.executable("gh", "case \"$1 $2\" in 'api user') echo owner ;; esac\n")
        self.executable("fzf", f"tee '{self.rows}' | grep '^:new-session'\n")
        self.executable("tput", "echo 100\n")
        self.executable("herdr", f"printf '%s\\n' \"$*\" >> '{self.calls}'\n" + """
case "$1 $2" in
  'workspace list') echo '{"result":{"workspaces":[]}}' ;;
  'worktree list') echo '{"result":{"source":{}}}' ;;
  'workspace create')
    [ "$FAIL_CREATE" != 1 ] || exit 1
    if [ -n "$CREATE_JSON" ]; then printf '%s\\n' "$CREATE_JSON"; else
      echo '{"result":{"workspace":{"workspace_id":"w-new"}}}'
    fi ;;
  'worktree open') [ "$FAIL_OPEN" != 1 ] ;;
esac
""")

    def executable(self, name, script):
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + script)
        path.chmod(0o755)

    def git(self, *args):
        return subprocess.check_output(["git", *args], env=self.env, text=True, stderr=subprocess.PIPE).strip()

    def pick(self, response="owner/example.git\n", **env):
        return subprocess.run(
            ["fish", "--no-config", "-c", f"set fish_function_path {FUNCTIONS} /usr/share/fish/functions; function print_error; echo $argv >&2; end; herdr_new_worktree"],
            cwd=self.remote, env={**self.env, **env}, input=response,
            text=True, capture_output=True, timeout=15,
        )

    def test_new_session_streams_clone_and_opens_default_checkout_under_bare_group(self):
        result = self.pick()
        self.assertEqual(result.returncode, 0, result.stderr)
        repo = self.projects / "example"
        self.assertIn(":new-session\tNew session", self.rows.read_text())
        self.assertIn("Cloning into", result.stderr)
        self.assertIn("Repo", result.stderr)
        self.assertEqual(self.git("-C", str(repo), "rev-parse", "--is-bare-repository"), "true")
        self.assertEqual(self.git("-C", str(repo / "main"), "rev-parse", "--abbrev-ref", "@{upstream}"), "origin/main")
        self.assertEqual(self.git("-C", str(repo), "symbolic-ref", "--short", "refs/remotes/origin/HEAD"), "origin/main")
        self.assertEqual(self.calls.read_text().splitlines(), [
            "workspace list",
            "worktree list --workspace w-active",
            f"workspace create --cwd {repo} --label example --no-focus",
            f"worktree open --workspace w-new --path {repo / 'main'} --focus",
        ])

    def test_real_herdr_focuses_checkout_as_child_of_bare_repository_group(self):
        controller = "/home/pcardenas/.claude/skills/herdr-automation/scripts/herdr_automation.py"
        name = f"newrepo{os.getpid() % 100000}"
        command = ["python3", controller]
        created = subprocess.run([*command, "create", name], text=True, capture_output=True, timeout=20)
        self.assertEqual(created.returncode, 0, created.stderr)
        try:
            self.executable("herdr", f"PATH={shlex.quote(os.environ['PATH'])} exec python3 {controller} herdr {name} -- \"$@\"\n")
            result = self.pick()
            self.assertEqual(result.returncode, 0, result.stderr)
            listed = subprocess.check_output([*command, "herdr", name, "--", "workspace", "list"], text=True, timeout=20)
            workspaces = json.loads(listed)["result"]["workspaces"]
            repo = str(self.projects / "example")
            parent = next(workspace for workspace in workspaces if workspace.get("worktree", {}).get("checkout_path") == repo)
            child = next(workspace for workspace in workspaces if workspace.get("worktree", {}).get("checkout_path") == repo + "/main")
            self.assertFalse(parent["worktree"]["is_linked_worktree"])
            self.assertTrue(child["worktree"]["is_linked_worktree"])
            self.assertEqual(parent["worktree"]["repo_key"], child["worktree"]["repo_key"])
            self.assertTrue(child["focused"])
            self.assertFalse(parent["focused"])
            listing = subprocess.check_output([*command, "herdr", name, "--", "worktree", "list", "--workspace", child["workspace_id"]], text=True, timeout=20)
            source = json.loads(listing)["result"]["source"]
            self.assertEqual(source["source_workspace_id"], parent["workspace_id"])
            self.assertEqual(source["source_checkout_path"], repo)
        finally:
            closed = subprocess.run([*command, "close", name], text=True, capture_output=True, timeout=20)
            self.assertEqual(closed.returncode, 0, closed.stderr)

    def test_empty_or_cancelled_prompt_does_not_clone_or_create(self):
        for response in ("\n", ""):
            with self.subTest(response=response):
                result = self.pick(response)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.calls.read_text().splitlines(), ["workspace list", "worktree list --workspace w-active"])
                self.assertFalse((self.projects / "example").exists())
                self.calls.unlink()

    def test_clone_failure_leaves_existing_files_and_never_creates_workspace(self):
        repo = self.projects / "example"
        repo.mkdir(parents=True)
        (repo / "keep").write_text("existing work")
        result = self.pick()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((repo / "keep").read_text(), "existing work")
        self.assertEqual(self.calls.read_text().splitlines(), ["workspace list", "worktree list --workspace w-active"])
        self.assertIn("Press Enter", result.stderr)

    def test_workspace_create_failure_does_not_open_checkout(self):
        result = self.pick(FAIL_CREATE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("worktree open", self.calls.read_text())

    def test_missing_workspace_id_does_not_open_checkout(self):
        result = self.pick(CREATE_JSON=json.dumps({"result": {"workspace": {}}}))
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("worktree open", self.calls.read_text())

    def test_open_failure_is_reported_without_deleting_clone(self):
        result = self.pick(FAIL_OPEN="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.projects / "example/main/.git").is_file())
        self.assertIn("Press Enter", result.stderr)

    def test_projects_path_failure_never_clones_or_creates_workspace(self):
        self.projects.write_text("not a directory")
        result = self.pick()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.projects.read_text(), "not a directory")
        self.assertEqual(self.calls.read_text().splitlines(), ["workspace list", "worktree list --workspace w-active"])
        self.assertIn("Press Enter", result.stderr)


if __name__ == "__main__":
    unittest.main()
