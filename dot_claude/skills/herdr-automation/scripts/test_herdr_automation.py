import contextlib
import importlib.util
import io
import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

SOURCE_SCRIPT = Path(__file__).with_name("executable_herdr_automation.py")
INSTALLED_SCRIPT = Path(__file__).with_name("herdr_automation.py")
SCRIPT = SOURCE_SCRIPT if SOURCE_SCRIPT.is_file() else INSTALLED_SCRIPT
spec = importlib.util.spec_from_file_location("herdr_automation", SCRIPT)
module = importlib.util.module_from_spec(spec)


class HerdrAutomationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec.loader.exec_module(module)

    def test_default_root_is_distinct_from_tmux_automation(self):
        with patch.dict(os.environ, {"XDG_RUNTIME_DIR": "/run/user/test"}, clear=False):
            self.assertEqual(module.default_runtime_root(), Path("/run/user/test/herdr-automation"))

    def test_isolated_environment_removes_ambient_multiplexer_context(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as parent:
            wrapper = module.Wrapper(Path(parent) / "runtime", "demo")
            with patch.dict(
                os.environ,
                {
                    "HERDR_ENV": "1",
                    "HERDR_SOCKET_PATH": "/real/herdr.sock",
                    "HERDR_PANE_ID": "w1:p1",
                    "HERDR_CONFIG_PATH": "/real/config.toml",
                    "TMUX": "/real/tmux",
                    "TMUX_PANE": "%7",
                },
                clear=False,
            ):
                environment = wrapper.isolated_env()
            for variable in module.AMBIENT_MULTIPLEXER_VARIABLES:
                if variable != "HERDR_CONFIG_PATH":
                    self.assertNotIn(variable, environment)
            self.assertNotEqual(environment["HERDR_CONFIG_PATH"], "/real/config.toml")
            self.assertEqual(environment["HOME"], str(wrapper.home))
            self.assertEqual(environment["SHELL"], str(wrapper.pane_shell_path))
            self.assertEqual(environment["XDG_CONFIG_HOME"], str(wrapper.config_home))
            self.assertEqual(environment["XDG_DATA_HOME"], str(wrapper.data_home))
            self.assertEqual(environment["XDG_CACHE_HOME"], str(wrapper.cache_home))
            self.assertEqual(environment["HERDR_CONFIG_PATH"], str(wrapper.config_path))
            self.assertEqual(wrapper.config_home, wrapper.state_dir / "c")

    def test_names_are_short_enough_for_herdr_unix_sockets(self):
        self.assertEqual(module.validate_name("abcdefghijklmnop"), "abcdefghijklmnop")
        with self.assertRaises(module.AutomationError):
            module.validate_name("abcdefghijklmnopq")

    def test_long_custom_runtime_root_fails_before_creating_state(self):
        wrapper = module.Wrapper(Path("/tmp") / ("x" * 90), "demo")
        with self.assertRaisesRegex(module.AutomationError, "socket path"):
            wrapper.validate_socket_capacity()
        self.assertFalse(wrapper.state_dir.exists())

    def test_transport_uses_separate_tmux_runtime_and_prefixed_name(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as parent:
            wrapper = module.Wrapper(Path(parent) / "runtime", "demo")
            command = wrapper.transport_argv("info")
            self.assertIn(str(wrapper.tmux_runtime), command)
            self.assertEqual(command[-1], "herdr-demo")
            self.assertNotIn("/tmux-automation/", str(wrapper.root))

    def test_herdr_command_targets_exact_named_session(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as parent:
            wrapper = module.Wrapper(Path(parent) / "runtime", "demo")
            wrapper.run = Mock(return_value=subprocess.CompletedProcess([], 0, "{}\n", ""))
            result = wrapper.run_herdr(["workspace", "list"])
            self.assertEqual(result.returncode, 0)
            argv = wrapper.run.call_args.args[0]
            self.assertEqual(argv[:3], ["herdr", "--session", wrapper.session_name])
            self.assertEqual(argv[3:], ["workspace", "list"])
            environment = wrapper.run.call_args.kwargs["env"]
            self.assertNotIn("HERDR_SOCKET_PATH", environment)

    def test_create_records_owned_session_and_transport(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as parent:
            root = Path(parent) / "runtime"
            wrapper = module.Wrapper(root, "demo")
            responses = [
                subprocess.CompletedProcess([], 0, json.dumps({"status": "active", "pane_id": "%1"}) + "\n", ""),
                subprocess.CompletedProcess([], 0, '{"id":"cli:workspace:list","result":{"workspaces":[]}}\n', ""),
            ]
            wrapper.run = Mock(side_effect=responses)
            metadata = wrapper.create()
            self.assertEqual(metadata["kind"], "herdr-automation")
            self.assertEqual(metadata["session_name"], "ha-demo")
            self.assertEqual(metadata["transport_name"], "herdr-demo")
            self.assertEqual(stat.S_IMODE(wrapper.state_dir.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE(wrapper.metadata_path.stat().st_mode), 0o600)
            launch = wrapper.run.call_args_list[0].args[0]
            self.assertIn("herdr", launch)
            self.assertIn("--session", launch)
            self.assertIn("ha-demo", launch)
            launch_environment = wrapper.run.call_args_list[0].kwargs["env"]
            self.assertNotIn("HERDR_ENV", launch_environment)
            self.assertNotIn("TMUX", launch_environment)

    def test_private_home_exists_and_dot_config_resolves_to_private_xdg_config(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as parent:
            wrapper = module.Wrapper(Path(parent) / "runtime", "demo")
            wrapper.initialize_state()
            self.assertTrue(wrapper.home.is_dir())
            self.assertEqual(stat.S_IMODE(wrapper.home.stat().st_mode), 0o700)
            self.assertEqual((wrapper.home / ".config").resolve(), wrapper.config_home.resolve())

    def test_pane_shell_uses_real_home_while_herdr_keeps_private_state(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as parent:
            wrapper = module.Wrapper(Path(parent) / "runtime", "demo")
            wrapper.initialize_state()
            result = subprocess.run(
                [str(wrapper.pane_shell_path), "-c", "printf '%s\\n' \"$HOME\" \"$XDG_CONFIG_HOME\" \"$HERDR_CONFIG_PATH\""],
                env=wrapper.isolated_env(), capture_output=True, text=True, check=True,
            )
            self.assertEqual(result.stdout.splitlines(), [
                str(Path.home()), str(Path.home() / ".config"), str(wrapper.config_path),
            ])
            self.assertEqual(stat.S_IMODE(wrapper.pane_shell_path.stat().st_mode), 0o700)

    def test_wait_transport_places_options_before_name(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as parent:
            wrapper = module.Wrapper(Path(parent) / "runtime", "demo")
            command = wrapper.wait_transport_argv("READY", 0.2, 5)
            wait_index = command.index("wait")
            name_index = command.index("herdr-demo")
            self.assertLess(command.index("--regex"), name_index)
            self.assertLess(wait_index, command.index("--regex"))
            self.assertEqual(command[name_index + 1 :], ["--", "capture-pane", "-p"])

    def test_close_stops_deletes_and_closes_only_owned_resources(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as parent:
            root = Path(parent) / "runtime"
            wrapper = module.Wrapper(root, "demo")
            wrapper.initialize_state()
            wrapper.write_metadata(wrapper.active_metadata("%1"))
            wrapper.run = Mock(
                side_effect=[
                    subprocess.CompletedProcess([], 0, '{"stopped":true}\n', ""),
                    subprocess.CompletedProcess([], 0, '{"deleted":true}\n', ""),
                    subprocess.CompletedProcess([], 0, '{"fallback":false}\n', ""),
                ]
            )
            result = wrapper.close()
            self.assertEqual(result, {"deleted": True, "fallback": False})
            commands = [call.args[0] for call in wrapper.run.call_args_list]
            self.assertEqual(commands[0][:4], ["herdr", "session", "stop", "ha-demo"])
            self.assertEqual(commands[1][:4], ["herdr", "session", "delete", "ha-demo"])
            self.assertIn("close", commands[2])
            self.assertGreater(wrapper.run.call_args_list[2].kwargs["timeout"], wrapper.timeout * 2)
            self.assertFalse(wrapper.state_dir.exists())

    def test_close_removes_read_only_package_directories(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as parent:
            wrapper = module.Wrapper(Path(parent) / "runtime", "demo")
            wrapper.initialize_state()
            wrapper.write_metadata(wrapper.active_metadata("%1"))
            package = wrapper.home / "go/pkg/mod/example@v1"
            package.mkdir(parents=True)
            package.joinpath("source.go").write_text("package example\n")
            package.chmod(0o555)
            wrapper.run = Mock(side_effect=[
                subprocess.CompletedProcess([], 0, "", ""),
                subprocess.CompletedProcess([], 0, "", ""),
                subprocess.CompletedProcess([], 0, '{"fallback":false}\n', ""),
            ])
            try:
                self.assertTrue(wrapper.close()["deleted"])
                self.assertFalse(wrapper.state_dir.exists())
            finally:
                if package.exists():
                    package.chmod(0o755)

    def test_close_can_retry_after_partial_removal_of_metadata(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as parent:
            wrapper = module.Wrapper(Path(parent) / "runtime", "demo")
            wrapper.initialize_state()
            wrapper.write_metadata(wrapper.active_metadata("%1"))
            wrapper.run = Mock(side_effect=[
                subprocess.CompletedProcess([], 0, "", ""),
                subprocess.CompletedProcess([], 0, "", ""),
                subprocess.CompletedProcess([], 0, '{"fallback":false}\n', ""),
            ])

            def fail_after_partial_removal(path):
                wrapper.metadata_path.unlink()
                raise PermissionError("temporary removal failure")

            with patch.object(module.shutil, "rmtree", side_effect=fail_after_partial_removal):
                with self.assertRaises(PermissionError):
                    wrapper.close()
            self.assertTrue(wrapper.state_dir.exists())
            wrapper.run.reset_mock()
            self.assertEqual(wrapper.close(), {"deleted": True, "fallback": False})
            wrapper.run.assert_not_called()
            self.assertFalse(wrapper.state_dir.exists())

    def test_close_is_idempotent_when_state_is_absent(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as parent:
            wrapper = module.Wrapper(Path(parent) / "runtime", "demo")
            self.assertEqual(wrapper.close(), {"deleted": False, "fallback": False})

    def test_disposable_tui_guidance_prefers_herdr_without_weakening_isolation(self):
        skills = SOURCE_SCRIPT.parents[2]
        herdr = (skills / "herdr-automation/SKILL.md").read_text().lower()
        tmux = (skills / "tmux-automation/SKILL.md").read_text().lower()
        nvim = (skills / "nvim-config/SKILL.md").read_text().lower()
        self.assertIn("prefer herdr-automation", herdr)
        self.assertIn("private home", herdr)
        self.assertIn("prefer herdr-automation", tmux)
        self.assertIn("tmux-specific", tmux)
        self.assertIn("prefer herdr-automation", nvim)

    def test_cli_names_herdr_operations_without_overloading_exec(self):
        parser = module.build_parser()
        self.assertEqual(parser.parse_args(["herdr", "demo", "--", "workspace", "list"]).action, "herdr")
        self.assertEqual(parser.parse_args(["terminal", "demo", "--", "capture-pane", "-p"]).action, "terminal")
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            parser.parse_args(["exec", "demo", "--", "workspace", "list"])


if __name__ == "__main__":
    unittest.main()
