"""Contract tests for the approved Herdr 0.9.1 configuration boundary."""
import os
import re
import shutil
import subprocess
import tempfile
import time
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).parent
SOURCE = ROOT / "dot_config/herdr/config.toml"
README = ROOT / "dot_config/herdr/README.md"
HERDR = Path("/home/pcardenas/.local/bin/herdr")
STATUS_COMMAND = ["/bin/bash", "-lc", "~/.config/tmux/scripts/status_metrics.sh --format herdr --short"]
METRICS_SOURCE = ROOT / "dot_config/tmux/scripts/executable_status_metrics.sh"
FISH_CONFIG = ROOT / "dot_config/fish/config.fish"
FISH_INTERACTIVE_CONFIG = ROOT / "dot_config/fish/interactive_config.fish"
PLUGIN_INSTALLER = ROOT / "dot_config/herdr/run_onchange_after_herdr-plugins-install.sh.tmpl"
NAVIGATE = ROOT / "dot_local/bin/executable_herdr-navigate"
MANAGE_HERDR = ROOT / "dot_config/fish/functions/manage_herdr_sessions.fish"
PREVIEW_HERDR = ROOT / "dot_config/fish/functions/preview_herdr_target.fish"
CREATE_WORKTREE = ROOT / "dot_config/fish/functions/herdr_new_worktree.fish"
CLOSE_WORKSPACE = ROOT / "dot_config/fish/functions/herdr_close_workspace.fish"
LEAP_COMMIT = "be238808187636a080b46c547b95cbac9ee9988e"


class HerdrConfigContractTest(unittest.TestCase):
    def test_metrics_default_and_explicit_tmux_formats_are_equivalent(self):
        with tempfile.TemporaryDirectory() as scripts_dir:
            for name, output in {
                "cursor_spend.sh": "#[fg=#9ece6a]$12",
                "cpu.sh": "#[fg=#c0caf5]42%",
                "disk.sh": "#[fg=#c0caf5]7%",
                "ram.sh": "#[fg=#c0caf5]3.1G",
            }.items():
                script = Path(scripts_dir) / name
                script.write_text(f"#!/bin/bash\\nprintf '%s' '{output}'\\n")
                script.chmod(0o755)
            env = {**os.environ, "TMUX_SCRIPTS_DIR": scripts_dir}
            default = subprocess.run(["/bin/bash", str(METRICS_SOURCE)], env=env, text=True, capture_output=True)
            explicit = subprocess.run(["/bin/bash", str(METRICS_SOURCE), "--format", "tmux"], env=env, text=True, capture_output=True)
        self.assertEqual(default.returncode, 0, default.stderr)
        self.assertEqual(explicit.returncode, 0, explicit.stderr)
        self.assertEqual(default.stdout, explicit.stdout)

    def test_metrics_herdr_is_style_stripped_tmux_semantics(self):
        with tempfile.TemporaryDirectory() as scripts_dir:
            for name, output in {
                "cursor_spend.sh": "#[fg=#9ece6a]$12",
                "cpu.sh": "#[fg=#c0caf5]42%",
                "disk.sh": "#[fg=#c0caf5]7%",
                "ram.sh": "#[fg=#c0caf5]3.1G",
            }.items():
                script = Path(scripts_dir) / name
                script.write_text(f"#!/bin/bash\\nprintf '%s' '{output}'\\n")
                script.chmod(0o755)
            env = {**os.environ, "TMUX_SCRIPTS_DIR": scripts_dir}
            tmux = subprocess.run(["/bin/bash", str(METRICS_SOURCE), "--short"], env=env, text=True, capture_output=True)
            herdr = subprocess.run(["/bin/bash", str(METRICS_SOURCE), "--format", "herdr", "--short"], env=env, text=True, capture_output=True)
        self.assertEqual(tmux.returncode, 0, tmux.stderr)
        self.assertEqual(herdr.returncode, 0, herdr.stderr)
        plain_tmux = re.sub(r"#\[[^]]*\]", "", tmux.stdout)
        self.assertEqual(herdr.stdout, plain_tmux)
        self.assertTrue(herdr.stdout.strip())
        self.assertNotRegex(herdr.stdout, r"(?:#\[|\x1b\[)")

    def test_metrics_gnome_preserves_the_tmux_colors_as_ansi(self):
        with tempfile.TemporaryDirectory() as scripts_dir:
            for name, output in {
                "cursor_spend.sh": "#[fg=#9ece6a]$12",
                "cpu.sh": "42%",
                "disk.sh": "7%",
                "ram.sh": "3.1G",
            }.items():
                script = Path(scripts_dir) / name
                script.write_text(f"#!/bin/bash\nprintf '%s' '{output}'\n")
                script.chmod(0o755)
            env = {**os.environ, "TMUX_SCRIPTS_DIR": scripts_dir}
            tmux = subprocess.run(["/bin/bash", str(METRICS_SOURCE), "--short"], env=env, text=True, capture_output=True)
            gnome = subprocess.run(["/bin/bash", str(METRICS_SOURCE), "--format", "gnome", "--short"], env=env, text=True, capture_output=True)
        self.assertEqual(tmux.returncode, 0, tmux.stderr)
        self.assertEqual(gnome.returncode, 0, gnome.stderr)
        self.assertIn("\x1b[38;2;158;206;106m$12", gnome.stdout)
        self.assertIn("\x1b[38;2;255;158;100m󰍛 ", gnome.stdout)
        self.assertEqual(re.sub(r"\x1b\[[0-9;]*m", "", gnome.stdout), re.sub(r"#\[[^]]*\]", "", tmux.stdout))

    def test_metrics_protocol_is_versioned_and_shared_by_renderers(self):
        result = subprocess.run(["/bin/bash", str(METRICS_SOURCE), "--format", "protocol", "--short"], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = __import__("json").loads(result.stdout)
        self.assertEqual(payload["version"], 1)
        self.assertTrue(payload["runs"])
        self.assertTrue(all(set(run) == {"fg", "text"} for run in payload["runs"]))

    def test_metrics_invalid_format_fails_clearly(self):
        result = subprocess.run(["/bin/bash", str(METRICS_SOURCE), "--format", "invalid"], text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid format", result.stderr.lower())

    def test_installed_version_is_091(self):
        result = subprocess.run([str(HERDR), "--version"], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("herdr 0.9.1", result.stdout)

    def test_shell_drops_a_stale_inherited_tmux_socket(self):
        text = FISH_CONFIG.read_text()
        stale_socket_guard = text.index("if set -q TMUX")
        interactive_config = text.index("if status is-interactive")
        self.assertLess(stale_socket_guard, interactive_config)
        self.assertIn('test -S "$tmux_socket"', text)
        self.assertIn("set -e TMUX TMUX_PANE", text)

    def test_shell_shares_the_current_ssh_agent_with_herdr_through_a_stable_socket(self):
        text = FISH_INTERACTIVE_CONFIG.read_text()
        self.assertIn('set -l stable_ssh_auth_sock $HOME/.ssh/ssh-agent.$hostname.sock', text)
        self.assertIn('not set -q HERDR_ENV', text)
        self.assertIn('test -S "$SSH_AUTH_SOCK"', text)
        self.assertIn('ln -s "$SSH_AUTH_SOCK" "$stable_ssh_auth_sock"', text)
        self.assertIn('set -gx SSH_AUTH_SOCK $stable_ssh_auth_sock', text)

    def test_onboarding_is_disabled_at_top_level(self):
        parsed = tomllib.loads(SOURCE.read_text())
        self.assertIs(parsed["onboarding"], False)

    def test_status_contract_is_active_and_exact(self):
        parsed = tomllib.loads(SOURCE.read_text())
        entry = parsed["ui"]["tab_bar_right"]
        self.assertEqual(len(entry), 1)
        self.assertEqual(entry[0]["type"], "command")
        self.assertEqual(entry[0]["command"], "~/.config/tmux/scripts/status_metrics.sh --format herdr --short")
        self.assertEqual(entry[0]["interval_seconds"], 10)
        self.assertEqual(entry[0]["timeout_seconds"], 25)
        self.assertEqual(parsed["ui"]["tab_bar_right_separator"], " | ")

    def test_status_command_produces_plain_nonempty_output_with_30_second_timeout(self):
        started = time.monotonic()
        result = subprocess.run(STATUS_COMMAND, timeout=30, text=True, capture_output=True)
        self.assertLess(time.monotonic() - started, 30)
        self.assertEqual(result.returncode, 0, result.stderr)
        plain = re.sub(r"#\[[^ ]* ?", "", result.stdout).strip()
        self.assertTrue(plain)
        self.assertNotIn("#[", plain)

    def test_config_check_accepts_isolated_home_xdg_and_override(self):
        with tempfile.TemporaryDirectory() as home:
            xdg_config_home = Path(home) / "xdg-config"
            config = xdg_config_home / "herdr/config.toml"
            config.parent.mkdir(parents=True)
            shutil.copyfile(SOURCE, config)
            env = {"HOME": home, "XDG_CONFIG_HOME": str(xdg_config_home), "PATH": "/usr/bin:/bin"}
            result = subprocess.run([str(HERDR), "config", "check"], env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            env["HERDR_CONFIG_PATH"] = str(config)
            result = subprocess.run([str(HERDR), "config", "check"], env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)

    def test_ui_uses_the_same_tokyo_night_base_palette_as_tmux(self):
        parsed = tomllib.loads(SOURCE.read_text())
        self.assertEqual(parsed["theme"]["name"], "tokyo-night")

    def test_agent_status_indicators_are_red_when_idle_and_green_when_working(self):
        custom = tomllib.loads(SOURCE.read_text())["theme"]["custom"]
        self.assertEqual(custom["green"], "#f7768e")
        self.assertEqual(custom["yellow"], "#9ece6a")

    def test_ui_enables_native_mouse_capture_and_copy_on_select(self):
        parsed = tomllib.loads(SOURCE.read_text())
        self.assertTrue(parsed["ui"]["mouse_capture"])
        self.assertTrue(parsed["ui"]["copy_on_select"])

    def test_canonical_config_has_active_native_controls(self):
        parsed = tomllib.loads(SOURCE.read_text())
        self.assertEqual(SOURCE, ROOT / "dot_config/herdr/config.toml")
        self.assertEqual(parsed["terminal"]["new_cwd"], "follow")
        keys = {key: value for key, value in parsed["keys"].items() if key != "command"}
        self.assertEqual(keys, {
            "prefix": "ctrl+b",
            "help": "prefix+?",
            "settings": "prefix+shift+s",
            "detach": "prefix+d",
            "workspace_picker": "prefix+w",
            "new_worktree": "",
            "close_workspace": "",
            "rename_workspace": "prefix+$",
            "new_tab": "prefix+c",
            "rename_tab": "prefix+comma",
            "previous_tab": "prefix+p",
            "next_tab": "prefix+n",
            "switch_tab": "prefix+1..9",
            "close_tab": "prefix+ampersand",
            "copy_mode": "prefix+[",
            "focus_pane_left": ["prefix+h", "prefix+left"],
            "focus_pane_down": ["prefix+j", "prefix+down"],
            "focus_pane_up": ["prefix+k", "prefix+up"],
            "focus_pane_right": ["prefix+l", "prefix+right"],
            "cycle_pane_next": "prefix+o",
            "last_pane": "prefix+semicolon",
            "split_vertical": "prefix+percent",
            "split_horizontal": "prefix+double_quote",
            "close_pane": "prefix+x",
            "zoom": ["prefix+z", "prefix+ctrl+z"],
            "resize_mode": "prefix+r",
        })
        self.assertEqual({entry["key"]: (entry["type"], entry["command"]) for entry in parsed["keys"]["command"]}, {
            "ctrl+h": ("shell", "~/.local/bin/herdr-navigate left"),
            "ctrl+j": ("shell", "~/.local/bin/herdr-navigate down"),
            "ctrl+k": ("shell", "~/.local/bin/herdr-navigate up"),
            "ctrl+l": ("shell", "~/.local/bin/herdr-navigate right"),
            "prefix+s": ("plugin_action", "RooseveltAdvisors.herdr-leap.open"),
            "ctrl+f": ("popup", "fish -c manage_herdr_sessions"),
            "prefix+shift+g": ("popup", "fish -c herdr_new_worktree"),
            "prefix+shift+d": ("popup", "fish -c herdr_close_workspace"),
        })

    def test_close_workspace_key_uses_context_aware_popup(self):
        parsed = tomllib.loads(SOURCE.read_text())
        command = next(entry for entry in parsed["keys"]["command"] if entry["key"] == "prefix+shift+d")
        self.assertEqual(command["type"], "popup")
        self.assertEqual(command["command"], "fish -c herdr_close_workspace")
        self.assertEqual(parsed["keys"]["close_workspace"], "")

    def test_close_popup_removes_linked_worktree_checkout(self):
        with tempfile.TemporaryDirectory() as bin_dir:
            log = Path(bin_dir) / "calls"
            herdr = Path(bin_dir) / "herdr"
            herdr.write_text(
                "#!/bin/sh\n"
                "if [ \"$1 $2\" = 'worktree list' ]; then\n"
                "  printf '%s\\n' '{\"result\":{\"worktrees\":[{\"open_workspace_id\":\"w-linked\",\"path\":\"/repo/task\",\"is_linked_worktree\":true,\"is_bare\":false}]}}'\n"
                "else\n"
                f"  printf '%s\\n' \"$*\" >> {log}\n"
                "fi\n"
            )
            herdr.chmod(0o755)
            result = subprocess.run(
                ["fish", "--no-config", "-c", f"set fish_function_path {CLOSE_WORKSPACE.parent}; herdr_close_workspace"],
                input="y\n",
                env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "HERDR_ACTIVE_WORKSPACE_ID": "w-linked"},
                text=True,
                capture_output=True,
                timeout=10,
            )
            calls = log.read_text().splitlines() if log.exists() else []
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ["worktree remove --workspace w-linked"])

    def test_close_popup_uses_normal_close_for_non_git_workspace(self):
        with tempfile.TemporaryDirectory() as bin_dir:
            log = Path(bin_dir) / "calls"
            herdr = Path(bin_dir) / "herdr"
            herdr.write_text(
                "#!/bin/sh\n"
                "if [ \"$1 $2\" = 'worktree list' ]; then exit 1; fi\n"
                f"printf '%s\\n' \"$*\" >> {log}\n"
            )
            herdr.chmod(0o755)
            result = subprocess.run(
                ["fish", "--no-config", "-c", f"set fish_function_path {CLOSE_WORKSPACE.parent}; herdr_close_workspace"],
                input="y\n",
                env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "HERDR_ACTIVE_WORKSPACE_ID": "w-plain"},
                text=True,
                capture_output=True,
                timeout=10,
            )
            calls = log.read_text().splitlines() if log.exists() else []
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ["workspace close w-plain"])

    def test_linked_worktree_key_opens_branch_creation_popup(self):
        parsed = tomllib.loads(SOURCE.read_text())
        command = next(entry for entry in parsed["keys"]["command"] if entry["key"] == "prefix+shift+g")
        self.assertEqual(command["type"], "popup")
        self.assertEqual(command["command"], "fish -c herdr_new_worktree")
        self.assertEqual(parsed["keys"]["new_worktree"], "")

    def test_worktree_popup_branches_from_remote_default_branch(self):
        with tempfile.TemporaryDirectory() as bin_dir:
            log = Path(bin_dir) / "calls"
            herdr = Path(bin_dir) / "herdr"
            herdr.write_text(
                "#!/bin/sh\n"
                "if [ \"$1 $2\" = 'worktree list' ]; then\n"
                "  printf '%s\\n' '{\"result\":{\"source\":{\"source_workspace_id\":\"w-parent\"},\"worktrees\":[{\"open_workspace_id\":\"w-linked\",\"path\":\"/repo/task\",\"is_linked_worktree\":true,\"is_bare\":false}]}}'\n"
                "else\n"
                f"  printf '%s\\n' \"$*\" >> {log}\n"
                "fi\n"
            )
            herdr.chmod(0o755)
            git = Path(bin_dir) / "git"
            git.write_text("#!/bin/sh\nprintf '%s\\n' origin/trunk\n")
            git.chmod(0o755)
            result = subprocess.run(
                ["fish", "--no-config", "-c", f"set fish_function_path {CREATE_WORKTREE.parent}; herdr_new_worktree"],
                input="feature/new-worktree\n",
                env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "HERDR_ACTIVE_WORKSPACE_ID": "w-linked"},
                text=True,
                capture_output=True,
                timeout=10,
            )
            calls = log.read_text().splitlines() if log.exists() else []
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            calls,
            ["worktree create --workspace w-parent --branch feature/new-worktree --base origin/trunk --focus"],
        )

    def test_herdr_session_popup_searches_and_focuses_spaces_and_agents(self):
        manage = MANAGE_HERDR.read_text()
        preview = PREVIEW_HERDR.read_text()
        self.assertIn("herdr workspace list", manage)
        self.assertIn("herdr agent list", manage)
        self.assertIn("fzf", manage)
        self.assertIn("--header", manage)
        self.assertIn("TYPE", manage)
        self.assertIn("STATUS", manage)
        self.assertIn("SPACE", manage)
        self.assertIn("TARGET", manage)
        self.assertIn("herdr workspace focus", manage)
        self.assertIn("herdr agent focus", manage)
        self.assertIn("preview_herdr_target", manage)
        self.assertIn("herdr pane read", preview)

    def test_shell_navigation_forwards_to_the_active_nvim_pane(self):
        with tempfile.TemporaryDirectory() as bin_dir:
            herdr = Path(bin_dir) / "herdr"
            herdr.write_text(
                "#!/bin/sh\n"
                "if [ \"$1 $2\" = 'pane process-info' ]; then\n"
                "  printf '%s\\n' '{\"result\":{\"process_info\":{\"foreground_processes\":[{\"name\":\"nvim\"}]}}}'\n"
                "else\n"
                "  printf '%s\\n' \"$*\"\n"
                "fi\n"
            )
            herdr.chmod(0o755)
            env = {
                **os.environ,
                "HERDR_BIN_PATH": str(herdr),
                "HERDR_ACTIVE_PANE_ID": "w-test:p1",
            }
            env.pop("HERDR_PANE_ID", None)
            result = subprocess.run(
                ["/bin/bash", str(NAVIGATE), "left"],
                env=env,
                text=True,
                capture_output=True,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "pane send-keys w-test:p1 ctrl+h\n")
        self.assertNotIn("--current", result.stdout)

    def test_direct_navigation_unzooms_only_when_crossing_herdr_panes(self):
        parsed = tomllib.loads(SOURCE.read_text())
        navigation = {
            entry["key"]: entry
            for entry in parsed["keys"]["command"]
            if entry["key"] in {"ctrl+h", "ctrl+j", "ctrl+k", "ctrl+l"}
        }
        self.assertEqual(
            {key: (entry["type"], entry["command"]) for key, entry in navigation.items()},
            {
                "ctrl+h": ("shell", "~/.local/bin/herdr-navigate left"),
                "ctrl+j": ("shell", "~/.local/bin/herdr-navigate down"),
                "ctrl+k": ("shell", "~/.local/bin/herdr-navigate up"),
                "ctrl+l": ("shell", "~/.local/bin/herdr-navigate right"),
            },
        )
        script = NAVIGATE.read_text()
        self.assertLess(script.index("pane zoom --off"), script.index("pane focus"))
        self.assertLess(script.index('if [ "$forward" -eq 1 ]'), script.index("pane zoom --off"))

    def test_herdr_plugins_are_pinned_and_installed_canonically(self):
        installer_text = PLUGIN_INSTALLER.read_text()
        self.assertIn("herdr plugin install paulbkim-dev/vim-herdr-navigation --ref 79679dacc791f70fc34de8b29a3cf9706c0f5b2f -y", installer_text)
        self.assertIn(f"herdr plugin install RooseveltAdvisors/herdr-leap --ref {LEAP_COMMIT} -y", installer_text)
        self.assertNotRegex(installer_text, r"--ref (main|master|latest)\\b")

    def test_easyjump_migration_keeps_prefix_s_and_jump_mode(self):
        parsed = tomllib.loads(SOURCE.read_text())
        leap = next(entry for entry in parsed["keys"]["command"] if entry["command"] == "RooseveltAdvisors.herdr-leap.open")
        self.assertEqual(leap["key"], "prefix+s")

    def test_readme_records_navigation_scope_and_mit_pin(self):
        text = README.read_text()
        for requirement in ("Navigation: **SUPPORTED**", "prefix+h/j/k/l", "explicit escape hatch", "Ctrl-B", "ctrl+b", "MIT", "79679dacc791f70fc34de8b29a3cf9706c0f5b2f"):
            self.assertIn(requirement, text)

    def test_plugin_list_json_records_exact_pin_version_and_enabled_actions(self):
        result = subprocess.run([str(HERDR), "plugin", "list", "--json"], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        plugin = __import__("json").loads(result.stdout)["result"]["plugins"]
        self.assertEqual({entry["plugin_id"] for entry in plugin}, {"vim-herdr-navigation", "RooseveltAdvisors.herdr-leap"})
        navigation = next(entry for entry in plugin if entry["plugin_id"] == "vim-herdr-navigation")
        self.assertEqual(navigation["source"]["requested_ref"], "79679dacc791f70fc34de8b29a3cf9706c0f5b2f")
        self.assertEqual(navigation["source"]["resolved_commit"], "79679dacc791f70fc34de8b29a3cf9706c0f5b2f")
        self.assertEqual(navigation["version"], "0.1.0")
        self.assertTrue(navigation["enabled"])
        self.assertEqual({action["id"] for action in navigation["actions"]}, {"down", "left", "right", "up"})
        leap = next(entry for entry in plugin if entry["plugin_id"] == "RooseveltAdvisors.herdr-leap")
        self.assertEqual(leap["source"]["requested_ref"], LEAP_COMMIT)
        self.assertEqual(leap["source"]["resolved_commit"], LEAP_COMMIT)
        self.assertEqual(leap["version"], "0.2.1")
        self.assertTrue(leap["enabled"])
        self.assertIn("open", {action["id"] for action in leap["actions"]})


    def test_cursor_spend_output_is_present_in_aggregate_status_when_nonempty(self):
        cursor = subprocess.run(["/bin/bash", "-lc", "~/.config/tmux/scripts/cursor_spend.sh --short"], text=True, capture_output=True)
        self.assertEqual(cursor.returncode, 0, cursor.stderr)
        aggregate = subprocess.run(STATUS_COMMAND, timeout=30, text=True, capture_output=True)
        self.assertEqual(aggregate.returncode, 0, aggregate.stderr)
        aggregate_plain = re.sub(r"#\[[^]]*\]", "", aggregate.stdout).strip()
        self.assertTrue(aggregate_plain)
        self.assertNotIn("#[", aggregate_plain)
        self.assertNotRegex(aggregate_plain, r"\x1b\[")


    def test_policy_and_readme_match_091_contract(self):
        parsed = tomllib.loads(SOURCE.read_text())
        self.assertFalse(parsed["session"]["resume_agents_on_restore"])
        self.assertFalse(parsed["experimental"]["pane_history"])
        self.assertEqual(parsed["update"], {"channel": "stable", "version_check": False, "manifest_check": False})
        text = README.read_text()
        for requirement in ("0.9.1", "CPU/disk/RAM", "Cursor", "SUPPORTED", "VALIDATED", "SUPPORTED NATIVELY", "session snapshots", "process", "agent", "screen", "pane_history", "Ghostty", "clipboard", "--ref", "requested_ref", "resolved_commit", "version", "actions", "enabled", "no tmux fallback", "no external picker", "no process replay", "no agent replay", "no screen replay", "mouse selection", "clipboard write", "ordinary paste", "remote image paste", "UNVERIFIED", "BLOCKED", "OSC52"):
            self.assertIn(requirement, text)

    def test_config_contains_no_unsupported_fallback_or_replay_features(self):
        text = SOURCE.read_text().lower()
        for forbidden in ("@agentic_pending", "fzf", "osc52", "fallback", "replay"):
            self.assertNotIn(forbidden, text)

    def test_installed_native_integrations_match_current_versions(self):
        expected = {"pi": 9, "claude": 10, "codex": 8, "opencode": 12, "cursor": 1}
        result = subprocess.run([str(HERDR), "integration", "status"], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for agent, version in expected.items():
            self.assertRegex(result.stdout, re.compile(rf"^{agent}: current \(v{version}\) ", re.MULTILINE))

    def test_readme_documents_exact_current_integration_versions(self):
        text = README.read_text()
        for agent, version in (("pi", 9), ("claude", 10), ("codex", 8), ("opencode", 12), ("cursor", 1)):
            self.assertRegex(text, rf"(?i)\b{agent}\b[^\n]*\bv{version}\b")
        self.assertIn("no fallback", text.lower())


if __name__ == "__main__":
    unittest.main()
