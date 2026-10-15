"""Git identity selection for personal/work clone and init entry points."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parent
FUNCTIONS = ROOT / "dot_config/fish/functions"
WORK_FUNCTIONS = ROOT.parent / "applied-dotfiles/dot_config/fish/functions"


class GitIdentityTest(unittest.TestCase):
    def test_wrappers_select_standalone_identity_for_clone_and_init(self):
        for identity in ("personal", "work"):
            for operation in ("clone", "git-init"):
                with self.subTest(identity=identity, operation=operation):
                    if identity == "work" and not WORK_FUNCTIONS.is_dir():
                        self.skipTest(
                            "Work wrappers require the sibling applied-dotfiles checkout"
                        )
                    with tempfile.TemporaryDirectory() as directory:
                        home = Path(directory)
                        config_home = home / "custom config"
                        identities = config_home / "git/identities"
                        identities.mkdir(parents=True)
                        for profile in ("personal", "work"):
                            (identities / profile).write_text(
                                f"[user]\nemail = {profile}@example.com\n"
                                f"signingkey = {profile}-key\n"
                            )
                        env = {
                            **os.environ,
                            "HOME": directory,
                            "XDG_CONFIG_HOME": str(config_home),
                            "GIT_CONFIG_GLOBAL": str(home / ".gitconfig"),
                            "GIT_CONFIG_NOSYSTEM": "1",
                        }
                        remote = home / "remote.git"
                        subprocess.run(
                            ["git", "init", "--initial-branch=main", str(remote)],
                            env=env,
                            check=True,
                            capture_output=True,
                        )
                        subprocess.run(
                            [
                                "git",
                                "-C",
                                str(remote),
                                "-c",
                                "user.name=Test",
                                "-c",
                                "user.email=test@example.com",
                                "-c",
                                "commit.gpgSign=false",
                                "commit",
                                "--allow-empty",
                                "-m",
                                "initial",
                            ],
                            env=env,
                            check=True,
                            capture_output=True,
                        )
                        subprocess.run(
                            [
                                "git",
                                "config",
                                "--global",
                                f"url.{remote}.insteadOf",
                                f"{identity}-github.com:owner/example",
                            ],
                            env=env,
                            check=True,
                            capture_output=True,
                        )
                        command = operation + ("-work" if identity == "work" else "")
                        argument = (
                            "owner/example" if operation == "clone" else "example"
                        )
                        script = """
set fish_function_path $argv[1] $argv[2] $fish_function_path
function print_error
    echo $argv >&2
end
function print_info
    echo $argv
end
function gh
    if test "$argv[1] $argv[2]" = 'api user'
        echo owner
    end
end
$argv[3] $argv[4]
"""
                        result = subprocess.run(
                            [
                                "fish",
                                "--no-config",
                                "-c",
                                script,
                                str(FUNCTIONS),
                                str(WORK_FUNCTIONS),
                                command,
                                argument,
                            ],
                            cwd=home,
                            env=env,
                            text=True,
                            capture_output=True,
                        )
                        self.assertEqual(result.returncode, 0, result.stderr)
                        for key, expected in (
                            ("user.email", f"{identity}@example.com"),
                            ("user.signingkey", f"{identity}-key"),
                            ("commit.gpgSign", "true"),
                        ):
                            actual = subprocess.check_output(
                                [
                                    "git",
                                    "-C",
                                    str(home / "example"),
                                    "config",
                                    "--local",
                                    key,
                                ],
                                env=env,
                                text=True,
                            ).strip()
                            self.assertEqual(actual, expected)


if __name__ == "__main__":
    unittest.main()
