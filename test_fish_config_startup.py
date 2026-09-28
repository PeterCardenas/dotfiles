from pathlib import Path
import subprocess
import unittest


INTERACTIVE_CONFIG = (
    Path(__file__).resolve().parent / "dot_config" / "fish" / "interactive_config.fish"
).read_text()


class FishConfigStartupTests(unittest.TestCase):
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
