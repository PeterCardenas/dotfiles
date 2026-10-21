"""GitHub consumers use the Fish account-selection override, without real credentials."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parent
FUNCTIONS = ROOT / "dot_config/fish/functions"


class GhAuthTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / "bin"
        self.bin.mkdir()
        config = self.home / ".config/fish"
        config.mkdir(parents=True)
        (config / "functions").symlink_to(FUNCTIONS, target_is_directory=True)
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "GIT_CONFIG_GLOBAL": str(ROOT / "dot_config/git/config"),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_TERMINAL_PROMPT": "0",
            "GH_CONFIG_DIR": str(self.home / ".config/gh"),
            "GH_TOKEN": "unselected-test-token",
            "GITHUB_TOKEN": "unselected-test-token",
        }
        self.repo = self.home / "repo"
        subprocess.run(["git", "init", "-q", str(self.repo)], env=self.env, check=True)
        self.executable("gh", '''case "$1 $2" in
  'auth token')
    [ "$FAIL_AUTH" != 1 ] || exit 1
    if [ -n "$4" ]; then printf 'token-%s\n' "$4"; else printf '%s\n' "$GH_TOKEN"; fi ;;
  'auth git-credential')
    [ "$3" = get ] || exit 1
    IFS= read -r protocol
    [ "$protocol" = protocol=https ] || exit 1
    printf 'username=test-user\npassword=%s\n' "$GH_TOKEN" ;;
esac
''')
        self.executable("bob", 'printf "%s\\n" "$GITHUB_TOKEN"\n')

    def executable(self, name, script):
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + script)
        path.chmod(0o755)

    def select_remote(self, alias):
        subprocess.run(["git", "-C", str(self.repo), "config", "remote.origin.url", f"{alias}:owner/repo"], env=self.env, check=True)

    def test_bob_gets_token_through_gh_override(self):
        for alias, user in (("work-github.com", "peter-cardenas-ai"), ("personal-github.com", "PeterCardenas")):
            with self.subTest(alias=alias):
                self.select_remote(alias)
                result = subprocess.run(["fish", "--no-config", "-c", f"set fish_function_path {FUNCTIONS} $fish_function_path; bob --version"], cwd=self.repo, env=self.env, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), f"token-{user}")

    def test_bob_does_not_run_if_account_token_lookup_fails(self):
        self.select_remote("work-github.com")
        result = subprocess.run(["fish", "--no-config", "-c", f"set fish_function_path {FUNCTIONS} $fish_function_path; bob --version"], cwd=self.repo, env={**self.env, "FAIL_AUTH": "1"}, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_git_credentials_use_gh_override(self):
        for alias, user in (("work-github.com", "peter-cardenas-ai"), ("personal-github.com", "PeterCardenas")):
            for host in ("github.com", "gist.github.com"):
                with self.subTest(alias=alias, host=host):
                    self.select_remote(alias)
                    result = subprocess.run(["git", "credential", "fill"], input=f"protocol=https\nhost={host}\n\n", cwd=self.repo, env=self.env, text=True, capture_output=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertTrue(f"password=token-{user}\n" in result.stdout, "Credential helper did not use the repository-selected test token")


if __name__ == "__main__":
    unittest.main()
