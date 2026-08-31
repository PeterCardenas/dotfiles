from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


HOOK = Path(__file__).with_name("executable_posttooluse_chezmoi_apply.py")
SETTINGS = Path(__file__).parents[2] / ".chezmoitemplates/claude-settings.json"


class PostToolUseChezmoiApplyTest(unittest.TestCase):
    def test_settings_runs_hook_after_edit_and_write(self) -> None:
        settings = json.loads(SETTINGS.read_text(encoding="utf-8"))
        groups = settings["hooks"]["PostToolUse"]
        matching = [group for group in groups if group.get("matcher") == "Edit|Write"]
        self.assertEqual(len(matching), 1)
        self.assertEqual(
            matching[0]["hooks"][0]["command"],
            "~/.claude/hooks/posttooluse_chezmoi_apply.py",
        )

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
                [sys.executable, str(HOOK)],
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
                ["source-path", f"apply --source-path {edited}"],
            )

    def test_ignores_malformed_payloads(self) -> None:
        for payload in (None, [], {"tool_result": None}, {"tool_input": "invalid"}):
            with self.subTest(payload=payload):
                result = subprocess.run(
                    [sys.executable, str(HOOK)],
                    input=json.dumps(payload),
                    text=True,
                    capture_output=True,
                    check=False,
                )
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
                    [sys.executable, str(HOOK)],
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
            self.assertEqual(log.read_text(encoding="utf-8").splitlines(), ["source-path"])


if __name__ == "__main__":
    unittest.main()
