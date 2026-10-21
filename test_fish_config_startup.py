import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent
INTERACTIVE_CONFIG = (ROOT / "dot_config" / "fish" / "interactive_config.fish").read_text()
FISH_CONFIG = ROOT / "dot_config" / "fish" / "config.fish"


class FishConfigStartupTests(unittest.TestCase):
    def test_managed_startup_exports_no_bytecode_to_child_processes(self) -> None:
        with tempfile.TemporaryDirectory() as home:
            config_dir = Path(home) / ".config" / "fish"
            config_dir.mkdir(parents=True)
            (config_dir / "config.fish").symlink_to(FISH_CONFIG)
            env = {
                key: value
                for key, value in os.environ.items()
                if key != "PYTHONDONTWRITEBYTECODE"
            }
            env.update({"HOME": home, "XDG_CONFIG_HOME": str(Path(home) / ".config")})
            result = subprocess.run(
                ["fish", "-c", "python3 -c 'import os; print(os.environ[\"PYTHONDONTWRITEBYTECODE\"])'"],
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "1")

    def test_wsl_check_uses_builtin_match(self) -> None:
        self.assertTrue(
            "if string match -q -- '*WSL2*' (uname -a)" in INTERACTIVE_CONFIG,
            "WSL detection must use the builtin matcher",
        )

    def test_wsl_match_preserves_substring_and_case(self) -> None:
        for uname_output, expected in (
            ("Linux host 5.15.0-microsoft-standard-WSL2 x86_64", 0),
            ("Linux host WSL2 x86_64", 0),
            ("Linux host wsl2 x86_64", 1),
            ("Linux host 6.0.0 x86_64", 1),
        ):
            with self.subTest(uname_output=uname_output):
                result = subprocess.run(
                    [
                        "fish",
                        "-N",
                        "-c",
                        "string match -q -- '*WSL2*' $argv[1]",
                        uname_output,
                    ],
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(result.returncode, expected, result.stderr)


if __name__ == "__main__":
    unittest.main()
