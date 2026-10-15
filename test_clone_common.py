"""Local Git regression tests for the bare-repository clone layout."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


FUNCTION = Path(__file__).parent / "dot_config/fish/functions/clone-common.fish"


class CloneCommonTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.source = self.home / "remotes/owner/example.git"
        self.source.parent.mkdir(parents=True)
        self.git("init", "--initial-branch=main", str(self.source))
        self.git("-C", str(self.source), "config", "user.email", "test@example.com")
        self.git("-C", str(self.source), "config", "user.name", "Test")
        (self.source / "README.md").write_text("example\n")
        self.git("-C", str(self.source), "add", ".")
        self.git(
            "-C",
            str(self.source),
            "-c",
            "commit.gpgSign=false",
            "commit",
            "-m",
            "initial",
        )
        self.identity = self.home / "identity"
        self.git("init", str(self.identity))
        self.git("-C", str(self.identity), "config", "user.email", "peter@example.com")
        self.git("-C", str(self.identity), "config", "user.signingkey", "test-key")
        self.projects = self.home / "projects"
        self.projects.mkdir()
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "GIT_CONFIG_GLOBAL": str(self.home / ".gitconfig"),
            "GIT_CONFIG_NOSYSTEM": "1",
        }
        self.git(
            "config",
            "--file",
            self.env["GIT_CONFIG_GLOBAL"],
            f"url.{self.home / 'remotes'}/.insteadOf",
            "test-github.com:",
        )

    def git(self, *args):
        return subprocess.check_output(
            ["git", *args], text=True, stderr=subprocess.PIPE
        ).strip()

    def clone(self, *args):
        script = """
source $argv[1]
function print_error
    echo $argv >&2
end
function print_info
    echo $argv
end
function gh
    switch "$argv[1] $argv[2]"
        case 'api graphql'
            return 0
        case 'api user'
            echo owner
        case 'repo set-default'
            printf '%s\n' $argv[3] > $HOME/default-repo
    end
end
clone-common test-github.com identity $argv[2..-1]
or exit $status
pwd > $HOME/clone-pwd
"""
        return subprocess.run(
            [
                "fish",
                "--no-config",
                "-c",
                script,
                str(FUNCTION),
                "owner/example.git",
                *args,
            ],
            cwd=self.projects,
            env=self.env,
            text=True,
            capture_output=True,
        )

    def test_default_clone_creates_bare_repo_and_enters_default_branch_worktree(self):
        result = self.clone()
        self.assertEqual(result.returncode, 0, result.stderr)
        repo = self.projects / "example"
        self.assertTrue((repo / ".bare").is_dir(), "clone must store Git data in .bare")
        self.assertEqual((repo / ".git").read_text().strip(), "gitdir: ./.bare")
        self.assertEqual(
            self.git("-C", str(repo), "rev-parse", "--is-bare-repository"), "true"
        )
        self.assertEqual((repo / "main/README.md").read_text(), "example\n")
        self.assertEqual(
            (self.home / "clone-pwd").read_text().strip(), str(repo / "main")
        )
        self.assertEqual(
            self.git("-C", str(repo / "main"), "branch", "--show-current"), "main"
        )
        self.assertEqual(
            self.git(
                "-C", str(repo / "main"), "rev-parse", "--abbrev-ref", "@{upstream}"
            ),
            "origin/main",
        )
        self.assertEqual(
            self.git("-C", str(repo), "config", "user.email"), "peter@example.com"
        )
        self.assertEqual(
            self.git("-C", str(repo), "config", "user.name"), "Peter Cardenas"
        )
        self.assertEqual(
            self.git("-C", str(repo), "config", "user.signingkey"), "test-key"
        )
        self.assertEqual(self.git("-C", str(repo), "config", "commit.gpgSign"), "true")
        self.assertEqual(
            (self.home / "default-repo").read_text().strip(), "owner/example"
        )

    def test_fetch_updates_remote_tracking_branches(self):
        result = self.clone()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.git("-C", str(self.source), "branch", "new-branch")
        repo = self.projects / "example"
        subprocess.run(
            ["git", "-C", str(repo), "fetch", "origin"],
            env=self.env,
            check=True,
            capture_output=True,
        )
        self.assertEqual(
            self.git("-C", str(repo), "rev-parse", "origin/new-branch"),
            self.git("-C", str(self.source), "rev-parse", "main"),
        )

    def test_clone_options_select_initial_worktree_branch(self):
        self.git("-C", str(self.source), "branch", "develop")
        result = self.clone("--branch", "develop")
        self.assertEqual(result.returncode, 0, result.stderr)
        repo = self.projects / "example"
        self.assertTrue((repo / "develop/README.md").is_file())
        self.assertEqual(
            (self.home / "clone-pwd").read_text().strip(), str(repo / "develop")
        )

    def test_existing_destination_is_not_modified(self):
        repo = self.projects / "example"
        repo.mkdir()
        (repo / "keep").write_text("existing work\n")
        result = self.clone()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(repo.iterdir()), [repo / "keep"])
        self.assertEqual((repo / "keep").read_text(), "existing work\n")


if __name__ == "__main__":
    unittest.main()
