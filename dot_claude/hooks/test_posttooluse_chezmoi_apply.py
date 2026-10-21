from __future__ import annotations

import base64
import io
import json
import os
import runpy
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
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
    def _fake_chezmoi(root: Path) -> tuple[Path, Path, dict[str, str]]:
        fake_bin = root / "bin"
        fake_bin.mkdir()
        log = root / "chezmoi.log"
        fake = fake_bin / "chezmoi"
        fake.write_text(
            "#!/bin/sh\n"
            "printf '%s\\n' \"$*\" >> \"$CHEZMOI_TEST_LOG\"\n"
            "if [ \"$3\" = managed ]; then\n"
            "  [ \"$CHEZMOI_TEST_MANAGED_ERROR\" != 1 ] || { printf 'managed lookup failed\\n' >&2; exit 8; }\n"
            "  printf '%s\\n' \"$CHEZMOI_TEST_MANAGED_PATHS\"\n"
            "  exit 0\n"
            "fi\n"
            "[ \"$CHEZMOI_TEST_APPLY_ERROR\" != 1 ] || { printf 'apply failed\\n' >&2; exit 9; }\n",
            encoding="utf-8",
        )
        fake.chmod(0o755)
        return fake_bin, log, {
            "CHEZMOI_TEST_LOG": str(log),
            "CHEZMOI_TEST_MANAGED_PATHS": "",
            "CHEZMOI_TEST_MANAGED_ERROR": "0",
            "CHEZMOI_TEST_APPLY_ERROR": "0",
        }

    @staticmethod
    def _reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
        result: dict[str, object] = {}
        for key, value in pairs:
            if key in result:
                raise AssertionError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    def test_skips_unmanaged_source_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            edited = source / "ignored.txt"
            edited.write_text("changed", encoding="utf-8")
            log = root / "chezmoi.log"
            fake_bin = root / "bin"
            fake_bin.mkdir()
            fake = fake_bin / "chezmoi"
            fake.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$*\" >> \"$CHEZMOI_TEST_LOG\"\n"
                "if [ \"$3\" = managed ]; then exit 0; fi\n",
                encoding="utf-8",
            )
            fake.chmod(0o755)
            result = subprocess.run(
                [sys.executable, str(HOOK), "--source-base64", base64.b64encode(str(source).encode()).decode()],
                input=json.dumps({"tool_name": "Edit", "tool_input": {"file_path": str(edited)}, "tool_result": {"is_error": False}}),
                text=True,
                capture_output=True,
                env={**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}", "CHEZMOI_TEST_LOG": str(log)},
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                log.read_text(encoding="utf-8").splitlines(),
                [f"--source {source} managed --path-style=source-absolute"],
            )
            self.assertNotIn(" apply ", log.read_text(encoding="utf-8"))

    def test_native_managed_query_skips_ignored_files_and_applies_into_isolated_destination(self) -> None:
        chezmoi = shutil.which("chezmoi")
        self.assertIsNotNone(chezmoi)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            (source / ".chezmoiignore").write_text("ignored.txt\n", encoding="utf-8")
            managed = source / "managed.txt"
            managed.write_text("managed content\n", encoding="utf-8")
            ignored = source / "ignored.txt"
            ignored.write_text("ignored content\n", encoding="utf-8")
            result = subprocess.run(
                [chezmoi, "--source", str(source), "--destination", str(destination), "managed", "--path-style=source-absolute"],
                text=True, capture_output=True, check=True,
            )
            managed_paths = set(result.stdout.splitlines())
            self.assertIn(str(managed), managed_paths)
            self.assertNotIn(str(ignored), managed_paths)

            fake_bin = root / "bin"
            fake_bin.mkdir()
            wrapper = fake_bin / "chezmoi"
            wrapper.write_text(
                "#!/bin/sh\n"
                "if [ \"$1\" = --source ]; then shift 2; fi\n"
                "exec \"$CHEZMOI_TEST_REAL\" --source \"$CHEZMOI_TEST_SOURCE\" --destination \"$CHEZMOI_TEST_DESTINATION\" \"$@\"\n",
                encoding="utf-8",
            )
            wrapper.chmod(0o755)
            env = {
                key: value
                for key, value in os.environ.items()
                if key not in {"PYTHONDONTWRITEBYTECODE", "GH_TOKEN", "GITHUB_TOKEN"}
            }
            env.update({
                "HOME": str(root / "home"),
                "XDG_CONFIG_HOME": str(root / "xdg"),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "CHEZMOI_TEST_REAL": chezmoi,
                "CHEZMOI_TEST_SOURCE": str(source),
                "CHEZMOI_TEST_DESTINATION": str(destination),
            })
            (root / "home").mkdir()
            (root / "xdg").mkdir()
            def invoke(path: Path) -> subprocess.CompletedProcess[str]:
                return subprocess.run(
                    [sys.executable, str(HOOK), "--source-base64", base64.b64encode(str(source).encode()).decode()],
                    input=json.dumps({"tool_name": "Edit", "tool_input": {"file_path": str(path)}, "tool_result": {"is_error": False}}),
                    text=True, capture_output=True, env=env, check=False,
                )
            applied = invoke(managed)
            self.assertIn("Synced", applied.stdout)
            self.assertEqual((destination / "managed.txt").read_text(encoding="utf-8"), "managed content\n")
            skipped = invoke(ignored)
            self.assertIn("unmanaged", skipped.stdout.lower())
            self.assertFalse((destination / "ignored.txt").exists())

    def test_reports_managed_query_failure_without_applying(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            edited = source / "tracked.txt"
            edited.write_text("changed", encoding="utf-8")
            fake_bin, log, env = self._fake_chezmoi(root)
            env.update({**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}", "CHEZMOI_TEST_MANAGED_ERROR": "1"})
            result = subprocess.run(
                [sys.executable, str(HOOK), "--source-base64", base64.b64encode(str(source).encode()).decode()],
                input=json.dumps({"tool_name": "Edit", "tool_input": {"file_path": str(edited)}, "tool_result": {"is_error": False}}),
                text=True, capture_output=True, env=env, check=False,
            )
            self.assertIn("managed source query failed", result.stdout)
            self.assertIn("managed lookup failed", result.stdout)
            self.assertEqual(log.read_text(encoding="utf-8").splitlines(), [f"--source {source} managed --path-style=source-absolute"])

    def test_reports_managed_query_timeout_without_applying(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            edited = source / "tracked.txt"
            edited.write_text("changed", encoding="utf-8")
            payload = json.dumps({
                "tool_name": "Edit",
                "tool_input": {"file_path": str(edited)},
                "tool_result": {"is_error": False},
            })
            with patch("sys.path", [str(HOOK.parent), *sys.path]):
                main = runpy.run_path(str(HOOK))["_main"]
            with (
                patch("sys.argv", [str(HOOK), "--source-base64", base64.b64encode(str(source).encode()).decode()]),
                patch("sys.stdin", io.StringIO(payload)),
                patch("sys.stdout", io.StringIO()) as output,
                patch("subprocess.run", side_effect=subprocess.TimeoutExpired("chezmoi managed", 30)),
            ):
                main()
            self.assertIn("managed source query failed", output.getvalue())
            self.assertIn("timed out", output.getvalue())

    def test_reports_apply_failure_for_managed_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            edited = source / "tracked.txt"
            edited.write_text("changed", encoding="utf-8")
            fake_bin, log, env = self._fake_chezmoi(root)
            env.update({**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}", "CHEZMOI_TEST_MANAGED_PATHS": str(edited), "CHEZMOI_TEST_APPLY_ERROR": "1"})
            result = subprocess.run(
                [sys.executable, str(HOOK), "--source-base64", base64.b64encode(str(source).encode()).decode()],
                input=json.dumps({"tool_name": "Edit", "tool_input": {"file_path": str(edited)}, "tool_result": {"is_error": False}}),
                text=True, capture_output=True, env=env, check=False,
            )
            self.assertIn("chezmoi apply failed", result.stdout)
            self.assertIn("apply failed", result.stdout)
            self.assertEqual(
                log.read_text(encoding="utf-8").splitlines(),
                [
                    f"--source {source} managed --path-style=source-absolute",
                    f"--source {source} apply --source-path {edited}",
                ],
            )

    def test_applies_successful_source_edit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            edited = source / "tracked.txt"
            edited.write_text("changed", encoding="utf-8")
            fake_bin, log, env = self._fake_chezmoi(root)
            env.update({
                **os.environ,
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "CHEZMOI_TEST_MANAGED_PATHS": str(edited),
            })
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
                [
                    f"--source {source} managed --path-style=source-absolute",
                    f"--source {source} apply --source-path {edited}",
                ],
            )

    def test_applies_entries_that_include_an_edited_shared_template(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            (source / ".chezmoitemplates").mkdir(parents=True)
            (source / "dot_pi/private_agent").mkdir(parents=True)
            edited = source / ".chezmoitemplates/shared-fragment.json"
            edited.write_text('{"providers": {}}', encoding="utf-8")
            including = source / "dot_pi/private_agent/modify_models.json.tmpl"
            including.write_text('{{ template "shared-fragment.json" . }}\n', encoding="utf-8")
            unrelated = source / "dot_pi/private_agent/modify_settings.json.tmpl"
            unrelated.write_text('{{ template "shared-fragment.json" . }}\n', encoding="utf-8")
            fake_bin, log, env = self._fake_chezmoi(root)
            env.update({
                **os.environ,
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "CHEZMOI_TEST_MANAGED_PATHS": str(including),
            })
            result = subprocess.run(
                [sys.executable, str(HOOK), "--source-base64", base64.b64encode(str(source).encode()).decode()],
                input=json.dumps(
                    {
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
                [
                    f"--source {source} managed --path-style=source-absolute",
                    f"--source {source} apply --source-path {including}",
                ],
            )
            self.assertNotIn(str(unrelated), result.stdout)

    def test_reports_shared_template_without_including_entries(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            (source / ".chezmoitemplates").mkdir(parents=True)
            edited = source / ".chezmoitemplates/orphan.json"
            edited.write_text("{}", encoding="utf-8")
            log = root / "chezmoi.log"
            fake_bin = root / "bin"
            fake_bin.mkdir()
            fake = fake_bin / "chezmoi"
            fake.write_text(
                "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$CHEZMOI_TEST_LOG\"\n", encoding="utf-8"
            )
            fake.chmod(0o755)
            result = subprocess.run(
                [sys.executable, str(HOOK), "--source-base64", base64.b64encode(str(source).encode()).decode()],
                input=json.dumps(
                    {
                        "tool_name": "Edit",
                        "tool_input": {"file_path": str(edited)},
                        "tool_result": {"is_error": False},
                    }
                ),
                text=True,
                capture_output=True,
                env={**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}", "CHEZMOI_TEST_LOG": str(log)},
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                log.read_text(encoding="utf-8").splitlines(),
                [f"--source {source} managed --path-style=source-absolute"],
            )
            self.assertIn("nothing to apply", result.stdout)

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
