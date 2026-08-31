from __future__ import annotations

import base64
import json
import os
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


HOOK = Path(__file__).with_name("executable_posttooluse_chezmoi_apply.py")
SETTINGS = Path(__file__).parents[2] / ".chezmoitemplates/claude-settings.json"


class PostToolUseChezmoiApplyTest(unittest.TestCase):
    def test_settings_quotes_rendered_source_dir_as_one_argument(self) -> None:
        source_dir = "/tmp/space 'quote\" $() `tick` \\slash"
        with tempfile.NamedTemporaryFile("w", suffix=".toml", encoding="utf-8") as config:
            config.write(f"sourceDir = {json.dumps(source_dir)}\n")
            config.flush()
            rendered = subprocess.run(
                ["chezmoi", "--config", config.name, "execute-template"],
                input=SETTINGS.read_text(encoding="utf-8"), text=True, capture_output=True, check=True,
            ).stdout
        settings = json.loads(rendered, object_pairs_hook=self._reject_duplicate_keys)
        matching = [group for group in settings["hooks"]["PostToolUse"] if group.get("matcher") == "Edit|Write"]
        self.assertEqual(len(matching), 1)
        command = matching[0]["hooks"][0]["command"]
        parsed = shlex.split(command, posix=True)
        self.assertEqual(parsed[0], "~/.claude/hooks/posttooluse_chezmoi_apply.py")
        self.assertEqual(parsed[1], "--source-base64")
        decoded = base64.b64decode(parsed[2], validate=True).decode("utf-8")
        self.assertEqual(decoded, source_dir)

    @staticmethod
    def _reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
        result: dict[str, object] = {}
        for key, value in pairs:
            if key in result:
                raise AssertionError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    def test_applies_successful_source_edit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            edited = source / "tracked.txt"
            edited.write_text("changed", encoding="utf-8")
            log = root / "chezmoi.log"
            fake_bin = root / "bin"
            fake_bin.mkdir()
            fake = fake_bin / "chezmoi"
            fake.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$*\" >> \"$CHEZMOI_TEST_LOG\"\n"
                "if [ \"$1\" = source-path ]; then printf '%s\\n' \"$CHEZMOI_TEST_SOURCE\"; fi\n",
                encoding="utf-8",
            )
            fake.chmod(0o755)
            env = {
                **os.environ,
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "CHEZMOI_TEST_LOG": str(log),
                "CHEZMOI_TEST_SOURCE": str(source),
            }
            result = subprocess.run(
                [sys.executable, str(HOOK), "--source-base64", base64.b64encode(str(source).encode()).decode()],
                input=json.dumps(
                    {
                        "hook_event_name": "PostToolUse",
                        "tool_name": "Edit",
                        "tool_input": {"file_path": str(edited)},
                        "tool_result": {"is_error": False},
                    }
                ),
                text=True,
                capture_output=True,
                env=env,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                log.read_text(encoding="utf-8").splitlines(),
                [f"--source {source} apply --source-path {edited}"],
            )

    def test_ignores_symlink_inside_source_resolving_outside(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            outside = root / "outside.txt"
            outside.write_text("changed", encoding="utf-8")
            link = source / "link.txt"
            link.symlink_to(outside)
            log = root / "chezmoi.log"
            fake_bin = root / "bin"
            fake_bin.mkdir()
            fake = fake_bin / "chezmoi"
            fake.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$CHEZMOI_TEST_LOG\"\n", encoding="utf-8")
            fake.chmod(0o755)
            result = subprocess.run(
                [sys.executable, str(HOOK), "--source-base64", base64.b64encode(str(source).encode()).decode()],
                input=json.dumps({"tool_name": "Edit", "tool_input": {"file_path": str(link)}, "tool_result": {"is_error": False}}),
                text=True, capture_output=True, env={**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}", "CHEZMOI_TEST_LOG": str(log)}, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(log.exists())

    def test_ignores_malformed_base64(self) -> None:
        for value in ("not-base64!", "////", base64.b64encode(b"\xff").decode("ascii")):
            result = subprocess.run([sys.executable, str(HOOK), "--source-base64", value], input="{}", text=True, capture_output=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_ignores_malformed_payloads(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            for payload in (None, [], {"tool_result": None}, {"tool_input": "invalid"}):
                with self.subTest(payload=payload):
                    result = subprocess.run(
                        [sys.executable, str(HOOK), "--source-base64", base64.b64encode(str(source).encode()).decode()],
                        input=json.dumps(payload),
                        text=True,
                        capture_output=True,
                        check=False,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_ignores_payload_with_nul_path_or_cwd(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            encoded = base64.b64encode(str(source).encode()).decode()
            for payload in (
                {"tool_input": {"file_path": "tracked\x00.txt"}},
                {"cwd": "bad\x00cwd", "tool_input": {"file_path": "tracked.txt"}},
            ):
                result = subprocess.run(
                    [sys.executable, str(HOOK), "--source-base64", encoded],
                    input=json.dumps(payload), text=True, capture_output=True, check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_missing_wrong_and_extra_arguments(self) -> None:
        for arguments in ([], ["--source-base64"], ["--wrong", "x"], ["--source-base64", "x", "extra"]):
            with self.subTest(arguments=arguments):
                result = subprocess.run([sys.executable, str(HOOK), *arguments], input="{}", text=True, capture_output=True, check=False)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_ignores_failed_edits_and_paths_outside_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            outside = root / "outside.txt"
            outside.write_text("changed", encoding="utf-8")
            log = root / "chezmoi.log"
            fake_bin = root / "bin"
            fake_bin.mkdir()
            fake = fake_bin / "chezmoi"
            fake.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$*\" >> \"$CHEZMOI_TEST_LOG\"\n"
                "if [ \"$1\" = source-path ]; then printf '%s\\n' \"$CHEZMOI_TEST_SOURCE\"; fi\n",
                encoding="utf-8",
            )
            fake.chmod(0o755)
            env = {
                **os.environ,
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "CHEZMOI_TEST_LOG": str(log),
                "CHEZMOI_TEST_SOURCE": str(source),
            }
            for is_error in (True, False):
                subprocess.run(
                    [sys.executable, str(HOOK), "--source-base64", base64.b64encode(str(source).encode()).decode()],
                    input=json.dumps(
                        {
                            "hook_event_name": "PostToolUse",
                            "tool_name": "Write",
                            "tool_input": {"file_path": str(outside)},
                            "tool_result": {"is_error": is_error},
                        }
                    ),
                    text=True,
                    capture_output=True,
                    env=env,
                    check=False,
                )
            self.assertFalse(log.exists())


if __name__ == "__main__":
    unittest.main()
