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
HERDR = Path.home() / ".local/bin/herdr"
HERDR_AUTOMATION = Path.home() / ".claude/skills/herdr-automation/scripts/herdr_automation.py"
STATUS_COMMAND = ["/bin/bash", "-lc", "~/.config/tmux/scripts/status_metrics.sh --format herdr --short"]
METRICS_SOURCE = ROOT / "dot_config/tmux/scripts/executable_status_metrics.sh"
FISH_CONFIG = ROOT / "dot_config/fish/config.fish"
FISH_INTERACTIVE_CONFIG = ROOT / "dot_config/fish/interactive_config.fish"
WORKTREE_PLUGIN = ROOT / "dot_config/herdr/plugins/worktree-tools/herdr-plugin.toml"
NAVIGATE = ROOT / "dot_local/bin/executable_herdr-navigate"
MANAGE_HERDR = ROOT / "dot_config/fish/functions/manage_herdr_sessions.fish"
PREVIEW_HERDR = ROOT / "dot_config/fish/functions/preview_herdr_target.fish"
CREATE_WORKTREE = ROOT / "dot_config/fish/functions/herdr_new_worktree.fish"
CLOSE_WORKSPACE = ROOT / "dot_config/fish/functions/herdr_close_workspace.fish"
POPUP_READ = ROOT / "dot_config/fish/functions/herdr_popup_read.fish"
LEAP_COMMIT = "be238808187636a080b46c547b95cbac9ee9988e"


class HerdrConfigContractTest(unittest.TestCase):
    def test_native_workspace_picker_uses_arrows_and_jk_for_workspace_navigation(self):
        keys = tomllib.loads(SOURCE.read_text())["keys"]
        self.assertEqual(keys["workspace_picker"], "prefix+w")
        self.assertEqual(keys.get("navigate_workspace_up"), ["up", "k"])
        self.assertEqual(keys.get("navigate_workspace_down"), ["down", "j"])
        self.assertEqual(keys.get("navigate_pane_down"), "ctrl+j")
        self.assertEqual(keys.get("navigate_pane_up"), "ctrl+k")

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

    def test_installed_herdr_reports_a_version(self):
        result = subprocess.run([str(HERDR), "--version"], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRegex(result.stdout, r"^herdr \d+\.\d+\.\d+\s*$")

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

    def test_selected_agents_are_readable_without_brightening_tree_connectors(self):
        parsed = tomllib.loads(SOURCE.read_text())
        custom = parsed["theme"]["custom"]
        self.assertNotIn("overlay0", custom)  # Herdr also uses overlay0 for tree connectors.
        self.assertNotIn("overlay1", custom)
        self.assertNotIn("spaces", parsed["ui"].get("sidebar", {}))

        def luminance(color):
            channels = (int(color[index:index + 2], 16) / 255 for index in (1, 3, 5))
            linear = (value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in channels)
            return sum(value * weight for value, weight in zip(linear, (0.2126, 0.7152, 0.0722)))

        background = luminance(custom["active_row_bg"])
        self.assertGreater((background + 0.05) / (luminance("#24283b") + 0.05), 1.2)
        rows = parsed["ui"]["sidebar"]["agents"]["rows"]
        self.assertEqual([[item if isinstance(item, str) else item["token"] for item in row] for row in rows],
                         [["state_icon", "machine", "workspace"], ["tab"]])
        style = rows[1][0]
        muted = luminance(style["fg"])
        self.assertGreaterEqual((muted + 0.05) / (background + 0.05), 3)
        self.assertLess(muted, luminance("#a9b1d6"))  # Tokyo Night subtext0

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
            "navigate_workspace_up": ["up", "k"],
            "navigate_workspace_down": ["down", "j"],
            "navigate_pane_up": "ctrl+k",
            "navigate_pane_down": "ctrl+j",
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
            "focus_pane_left": "",
            "focus_pane_down": "",
            "focus_pane_up": "",
            "focus_pane_right": "",
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
            "prefix+h": ("shell", "~/.local/bin/herdr-navigate left --force"),
            "prefix+j": ("shell", "~/.local/bin/herdr-navigate down --force"),
            "prefix+k": ("shell", "~/.local/bin/herdr-navigate up --force"),
            "prefix+l": ("shell", "~/.local/bin/herdr-navigate right --force"),
            "prefix+left": ("shell", "~/.local/bin/herdr-navigate left --force"),
            "prefix+down": ("shell", "~/.local/bin/herdr-navigate down --force"),
            "prefix+up": ("shell", "~/.local/bin/herdr-navigate up --force"),
            "prefix+right": ("shell", "~/.local/bin/herdr-navigate right --force"),
            "prefix+s": ("plugin_action", "RooseveltAdvisors.herdr-leap.open"),
            "ctrl+f": ("shell", "herdr plugin pane open --plugin local.worktree-tools --entrypoint workspace-switcher"),
            "prefix+shift+g": ("shell", "herdr plugin pane open --plugin local.worktree-tools --entrypoint new-worktree"),
            "prefix+shift+d": ("shell", "herdr plugin pane open --plugin local.worktree-tools --entrypoint close-workspace"),
        })

    def test_custom_herdr_popups_use_named_plugin_panes(self):
        parsed = tomllib.loads(SOURCE.read_text())
        commands = {entry["key"]: entry for entry in parsed["keys"]["command"]}
        panes = {pane["id"]: pane for pane in tomllib.loads(WORKTREE_PLUGIN.read_text())["panes"]}
        self.assertNotIn("popup", {command["type"] for command in commands.values()})

        expected = {
            "ctrl+f": ("workspace-switcher", "Workspace switcher", ""),
            "prefix+shift+d": ("close-workspace", "Close workspace", ""),
            "prefix+shift+g": ("new-worktree", "New linked worktree", ""),
        }
        for key, (pane_id, title, arguments) in expected.items():
            self.assertEqual(
                commands[key]["command"],
                f"herdr plugin pane open --plugin local.worktree-tools --entrypoint {pane_id}{arguments}",
            )
            self.assertEqual(panes[pane_id]["title"], title)
            self.assertEqual(panes[pane_id]["placement"], "popup")

    def test_popup_prompts_share_wrapping_and_cancel_behavior(self):
        for source in (CREATE_WORKTREE, CLOSE_WORKSPACE):
            text = source.read_text()
            self.assertIn("herdr_popup_read", text)
            self.assertNotIn("read --prompt-str", text)
        helper = POPUP_READ.read_text()
        self.assertIn("bind escape exit", helper)
        self.assertIn("bind ctrl-c exit", helper)
        self.assertIn("printf '%s\\n'", helper)
        self.assertIn("--prompt-str '> '", helper)

    def test_workspace_switcher_wraps_labels_but_clips_wide_pane_preview(self):
        picker = MANAGE_HERDR.read_text()
        self.assertIn("--wrap=word", picker)
        self.assertIn('border-left,nowrap,follow,<65(down,50%,border-top)', picker)

    def test_close_workspace_key_uses_context_aware_popup(self):
        parsed = tomllib.loads(SOURCE.read_text())
        command = next(entry for entry in parsed["keys"]["command"] if entry["key"] == "prefix+shift+d")
        self.assertEqual(command["type"], "shell")
        self.assertEqual(
            command["command"],
            "herdr plugin pane open --plugin local.worktree-tools --entrypoint close-workspace",
        )
        self.assertEqual(parsed["keys"]["close_workspace"], "")
        pane = next(
            pane
            for pane in tomllib.loads(WORKTREE_PLUGIN.read_text())["panes"]
            if pane["id"] == "close-workspace"
        )
        self.assertIn("HERDR_PLUGIN_CONTEXT_JSON", " ".join(pane["command"]))
        self.assertIn(".workspace_id", " ".join(pane["command"]))

    def test_close_popup_removes_linked_worktree_checkout_end_to_end(self):
        name = f"wtclose{os.getpid() % 100000}"
        controller = ["python3", str(HERDR_AUTOMATION)]
        created = None
        try:
            create = subprocess.run(
                [*controller, "create", name, "--config", str(SOURCE)],
                text=True,
                capture_output=True,
                timeout=20,
            )
            self.assertEqual(create.returncode, 0, create.stderr)
            created = __import__("json").loads(create.stdout)
            home = Path(created["home"])
            config_home = home.parent / "c"
            repository = home / "repo"
            linked_checkout = home / ("linked-" + "long-path-segment-" * 12)
            repository.mkdir(parents=True)
            subprocess.run(["git", "-C", str(repository), "init", "-b", "main"], check=True, capture_output=True)
            subprocess.run(
                ["git", "-C", str(repository), "-c", "user.name=E2E", "-c", "user.email=e2e@example.com", "commit", "--allow-empty", "-m", "test: initialize fixture"],
                check=True,
                capture_output=True,
            )
            subprocess.run(
                ["git", "-C", str(repository), "worktree", "add", "-b", "linked", str(linked_checkout)],
                check=True,
                capture_output=True,
            )
            plugin = config_home / "herdr/plugins/worktree-tools"
            shutil.copytree(WORKTREE_PLUGIN.parent, plugin)
            functions = config_home / "fish/functions"
            functions.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(CLOSE_WORKSPACE, functions / CLOSE_WORKSPACE.name)
            shutil.copyfile(CREATE_WORKTREE, functions / CREATE_WORKTREE.name)
            shutil.copyfile(POPUP_READ, functions / POPUP_READ.name)

            def herdr(*arguments):
                return subprocess.run(
                    [*controller, "herdr", name, "--", *arguments],
                    text=True,
                    capture_output=True,
                    timeout=20,
                )

            linked = herdr("plugin", "link", str(plugin))
            self.assertEqual(linked.returncode, 0, linked.stderr)
            base_workspace = herdr("workspace", "create", "--cwd", str(repository), "--label", "repo")
            self.assertEqual(base_workspace.returncode, 0, base_workspace.stderr)
            opened = herdr("worktree", "open", "--cwd", str(repository), "--path", str(linked_checkout), "--focus")
            self.assertEqual(opened.returncode, 0, opened.stderr)
            workspace_id = __import__("json").loads(opened.stdout)["result"]["workspace"]["workspace_id"]
            create_popup = herdr("plugin", "pane", "open", "--plugin", "local.worktree-tools", "--entrypoint", "new-worktree", "--focus")
            self.assertEqual(create_popup.returncode, 0, create_popup.stderr)
            group_prompt = subprocess.run(
                [*controller, "wait-screen", "--regex", "Group>", "--duration", "0.2", "--wait-timeout", "5", name],
                text=True, capture_output=True, timeout=10,
            )
            self.assertEqual(group_prompt.returncode, 0, group_prompt.stderr or group_prompt.stdout)
            subprocess.run([*controller, "terminal", name, "--", "send-keys", "-t", created["pane_id"], "Enter"], check=True, capture_output=True, timeout=10)
            branch_prompt = subprocess.run(
                [*controller, "wait-screen", "--regex", "Branch name:", "--duration", "0.2", "--wait-timeout", "5", name],
                text=True, capture_output=True, timeout=10,
            )
            self.assertEqual(branch_prompt.returncode, 0, branch_prompt.stderr or branch_prompt.stdout)
            for cancel_key in ("Escape", "C-c"):
                dismissed = subprocess.run(
                    [*controller, "terminal", name, "--", "send-keys", "-t", created["pane_id"], cancel_key],
                    text=True, capture_output=True, timeout=10,
                )
                self.assertEqual(dismissed.returncode, 0, dismissed.stderr)
                deadline = time.monotonic() + 5
                while True:
                    reopened = herdr("plugin", "pane", "open", "--plugin", "local.worktree-tools", "--entrypoint", "new-worktree", "--focus")
                    if reopened.returncode == 0 or time.monotonic() >= deadline:
                        break
                    time.sleep(0.1)
                self.assertEqual(reopened.returncode, 0, reopened.stderr)
                group_prompt = subprocess.run(
                    [*controller, "wait-screen", "--regex", "Group>", "--duration", "0.2", "--wait-timeout", "5", name],
                    text=True, capture_output=True, timeout=10,
                )
                self.assertEqual(group_prompt.returncode, 0, group_prompt.stderr or group_prompt.stdout)
                subprocess.run([*controller, "terminal", name, "--", "send-keys", "-t", created["pane_id"], "Enter"], check=True, capture_output=True, timeout=10)
                branch_prompt = subprocess.run(
                    [*controller, "wait-screen", "--regex", "Branch name:", "--duration", "0.2", "--wait-timeout", "5", name],
                    text=True, capture_output=True, timeout=10,
                )
                self.assertEqual(branch_prompt.returncode, 0, branch_prompt.stderr or branch_prompt.stdout)
            subprocess.run([*controller, "terminal", name, "--", "send-keys", "-t", created["pane_id"], "Escape"], check=True, capture_output=True, timeout=10)
            deadline = time.monotonic() + 5
            while True:
                popup = herdr("plugin", "pane", "open", "--plugin", "local.worktree-tools", "--entrypoint", "close-workspace", "--focus")
                if popup.returncode == 0 or time.monotonic() >= deadline:
                    break
                time.sleep(0.1)
            self.assertEqual(popup.returncode, 0, popup.stderr)
            prompt = subprocess.run(
                [*controller, "wait-screen", "--regex", "Remove linked worktree", "--duration", "0.2", "--wait-timeout", "5", name],
                text=True,
                capture_output=True,
                timeout=10,
            )
            self.assertEqual(prompt.returncode, 0, prompt.stderr or prompt.stdout)
            screen = subprocess.run(
                [*controller, "terminal", name, "--", "capture-pane", "-p", "-t", created["pane_id"]],
                text=True, capture_output=True, timeout=10,
            )
            self.assertEqual(screen.returncode, 0, screen.stderr)
            prompt_lines = screen.stdout.split("Remove linked worktree ", 1)[1].split("? [y/N]", 1)[0]
            path_lines = prompt_lines.splitlines()
            wrapped_path = path_lines[0].split("│", 1)[0].rstrip() + "".join(
                line.rsplit("│", 2)[-2].strip() for line in path_lines[1:-1]
            ) + path_lines[-1].rsplit("│", 1)[-1].strip()
            self.assertEqual(wrapped_path, str(linked_checkout))
            self.assertGreaterEqual(len(path_lines), 3)
            self.assertNotIn("…", prompt_lines)
            for cancel_key in ("Escape", "C-c"):
                cancelled = subprocess.run(
                    [*controller, "terminal", name, "--", "send-keys", "-t", created["pane_id"], cancel_key],
                    text=True, capture_output=True, timeout=10,
                )
                self.assertEqual(cancelled.returncode, 0, cancelled.stderr)
                deadline = time.monotonic() + 5
                while True:
                    popup = herdr("plugin", "pane", "open", "--plugin", "local.worktree-tools", "--entrypoint", "close-workspace", "--focus")
                    if popup.returncode == 0 or time.monotonic() >= deadline:
                        break
                    time.sleep(0.1)
                self.assertEqual(popup.returncode, 0, popup.stderr)
                prompt = subprocess.run(
                    [*controller, "wait-screen", "--regex", "Remove linked worktree", "--duration", "0.2", "--wait-timeout", "5", name],
                    text=True, capture_output=True, timeout=10,
                )
                self.assertEqual(prompt.returncode, 0, prompt.stderr or prompt.stdout)
                self.assertTrue(linked_checkout.exists())
            confirmed = subprocess.run(
                [*controller, "terminal", name, "--", "send-keys", "-t", created["pane_id"], "y", "Enter"],
                text=True,
                capture_output=True,
                timeout=10,
            )
            self.assertEqual(confirmed.returncode, 0, confirmed.stderr)
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                workspaces = herdr("workspace", "list")
                self.assertEqual(workspaces.returncode, 0, workspaces.stderr)
                ids = {entry["workspace_id"] for entry in __import__("json").loads(workspaces.stdout)["result"]["workspaces"]}
                if workspace_id not in ids and not linked_checkout.exists():
                    break
                time.sleep(0.1)
            self.assertNotIn(workspace_id, ids)
            self.assertFalse(linked_checkout.exists())
        finally:
            if created is not None:
                closed = subprocess.run([*controller, "close", name], text=True, capture_output=True, timeout=20)
                self.assertEqual(closed.returncode, 0, closed.stderr)

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

    def test_linked_worktree_key_opens_titled_branch_creation_popup(self):
        parsed = tomllib.loads(SOURCE.read_text())
        command = next(entry for entry in parsed["keys"]["command"] if entry["key"] == "prefix+shift+g")
        self.assertEqual(command["type"], "shell")
        self.assertEqual(
            command["command"],
            "herdr plugin pane open --plugin local.worktree-tools --entrypoint new-worktree",
        )
        self.assertEqual(parsed["keys"]["new_worktree"], "")

        plugin = tomllib.loads(WORKTREE_PLUGIN.read_text())
        pane = next(entry for entry in plugin["panes"] if entry["id"] == "new-worktree")
        self.assertEqual(pane["id"], "new-worktree")
        self.assertEqual(pane["title"], "New linked worktree")
        self.assertEqual(pane["placement"], "popup")
        self.assertEqual(pane["width"], "60%")
        self.assertEqual(pane["height"], "40%")
        self.assertIn("herdr_new_worktree", " ".join(pane["command"]))

    def test_worktree_popup_excludes_git_workspaces_without_linked_children(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            herdr = bin_dir / "herdr"
            herdr.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  'workspace list') printf '%s\\n' '{\"result\":{\"workspaces\":[{\"workspace_id\":\"w-standalone\",\"label\":\"config\",\"worktree\":{\"repo_key\":\"config\",\"is_linked_worktree\":false}},{\"workspace_id\":\"w-group\",\"label\":\"project\",\"worktree\":{\"repo_key\":\"project\",\"is_linked_worktree\":false}},{\"workspace_id\":\"w-child\",\"label\":\"task\",\"worktree\":{\"repo_key\":\"project\",\"is_linked_worktree\":true}}]}}' ;;\n"
                "  'worktree list --workspace w-standalone') printf '%s\\n' '{\"result\":{\"source\":{\"source_workspace_id\":\"w-standalone\",\"source_checkout_path\":\"/repo/config\"}}}' ;;\n"
                "  'worktree list --workspace w-group'|'worktree list --workspace w-child') printf '%s\\n' '{\"result\":{\"source\":{\"source_workspace_id\":\"w-group\",\"source_checkout_path\":\"/repo/project\"}}}' ;;\n"
                "esac\n"
            )
            herdr.chmod(0o755)
            choices = root / "choices"
            fzf = bin_dir / "fzf"
            fzf.write_text(f"#!/bin/sh\ntee {choices} >/dev/null\nexit 130\n")
            fzf.chmod(0o755)
            result = subprocess.run(
                ["fish", "--no-config", "-c", f"set fish_function_path {CREATE_WORKTREE.parent}; herdr_new_worktree"],
                env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "HERDR_ACTIVE_WORKSPACE_ID": "w-standalone"},
                text=True, capture_output=True, timeout=10,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(choices.read_text().splitlines(), ["\tChoose a group", "w-group\tproject — /repo/project"])

    def test_worktree_popup_requires_explicit_group_when_active_workspace_has_no_base(self):
        with tempfile.TemporaryDirectory() as bin_dir:
            log = Path(bin_dir) / "calls"
            herdr = Path(bin_dir) / "herdr"
            herdr.write_text(
                "#!/bin/sh\n"
                f"printf '%s\\n' \"$*\" >> {log}\n"
                "if [ \"$1 $2\" = 'workspace list' ]; then\n"
                "  printf '%s\\n' '{\"result\":{\"workspaces\":[{\"workspace_id\":\"w-plain\",\"label\":\"outside\"},{\"workspace_id\":\"w-parent\",\"label\":\"repo\"}]}}'\n"
                "elif [ \"$1 $2 $3 $4\" = 'worktree list --workspace w-parent' ]; then\n"
                "  printf '%s\\n' '{\"result\":{\"source\":{\"source_workspace_id\":\"w-parent\",\"source_checkout_path\":\"/repo\"},\"worktrees\":[]}}'\n"
                "fi\n"
            )
            herdr.chmod(0o755)
            fzf = Path(bin_dir) / "fzf"
            fzf.write_text("#!/bin/sh\nIFS= read -r choice\nprintf '%s\\n' \"$choice\"\n")
            fzf.chmod(0o755)
            result = subprocess.run(
                ["fish", "--no-config", "-c", f"set fish_function_path {CREATE_WORKTREE.parent}; herdr_new_worktree"],
                input="\n",
                env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "HERDR_ACTIVE_WORKSPACE_ID": "w-plain"},
                text=True,
                capture_output=True,
                timeout=10,
            )
            calls = log.read_text().splitlines()
        self.assertNotIn("not a linked worktree", result.stderr)
        self.assertIn("Group:", result.stderr)
        self.assertNotIn("Branch name:", result.stderr)
        self.assertNotIn("worktree create", "\n".join(calls))

    def test_worktree_popup_plain_checkout_offers_group_before_branch_end_to_end(self):
        name = f"wtguard{os.getpid() % 100000}"
        controller = ["python3", str(HERDR_AUTOMATION)]
        created = None
        try:
            create = subprocess.run(
                [*controller, "create", name, "--config", str(SOURCE)],
                text=True,
                capture_output=True,
                timeout=20,
            )
            self.assertEqual(create.returncode, 0, create.stderr)
            created = __import__("json").loads(create.stdout)
            home = Path(created["home"])
            config_home = home.parent / "c"
            repository = home / "repo"
            linked_checkout = home / "review"
            repository.mkdir(parents=True)
            subprocess.run(["git", "-C", str(repository), "init", "-b", "main"], check=True, capture_output=True)
            subprocess.run(
                ["git", "-C", str(repository), "-c", "user.name=E2E", "-c", "user.email=e2e@example.com", "commit", "--allow-empty", "-m", "test: initialize fixture"],
                check=True,
                capture_output=True,
            )
            subprocess.run(
                ["git", "-C", str(repository), "worktree", "add", "-b", "review", str(linked_checkout)],
                check=True,
                capture_output=True,
            )
            plugin = config_home / "herdr/plugins/worktree-tools"
            shutil.copytree(WORKTREE_PLUGIN.parent, plugin)
            functions = config_home / "fish/functions"
            functions.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(CREATE_WORKTREE, functions / CREATE_WORKTREE.name)
            shutil.copyfile(POPUP_READ, functions / POPUP_READ.name)

            def herdr(*arguments):
                return subprocess.run(
                    [*controller, "herdr", name, "--", *arguments],
                    text=True,
                    capture_output=True,
                    timeout=20,
                )

            linked = herdr("plugin", "link", str(plugin))
            self.assertEqual(linked.returncode, 0, linked.stderr)
            base_workspace = herdr("workspace", "create", "--cwd", str(repository), "--label", "repo")
            self.assertEqual(base_workspace.returncode, 0, base_workspace.stderr)
            base_id = __import__("json").loads(base_workspace.stdout)["result"]["workspace"]["workspace_id"]
            grouped = herdr("worktree", "open", "--workspace", base_id, "--path", str(linked_checkout))
            self.assertEqual(grouped.returncode, 0, grouped.stderr)
            workspace = herdr("workspace", "create", "--cwd", str(linked_checkout), "--label", "review", "--focus")
            self.assertEqual(workspace.returncode, 0, workspace.stderr)
            workspace_id = __import__("json").loads(workspace.stdout)["result"]["workspace"]["workspace_id"]
            inspected = herdr("workspace", "get", workspace_id)
            self.assertEqual(inspected.returncode, 0, inspected.stderr)
            self.assertNotIn("worktree", __import__("json").loads(inspected.stdout)["result"]["workspace"])
            popup = herdr("plugin", "pane", "open", "--plugin", "local.worktree-tools", "--entrypoint", "new-worktree", "--focus")
            self.assertEqual(popup.returncode, 0, popup.stderr)
            prompted = subprocess.run(
                [*controller, "wait-screen", "--regex", "Group>", "--duration", "0.2", "--wait-timeout", "5", name],
                text=True,
                capture_output=True,
                timeout=10,
            )
            self.assertEqual(prompted.returncode, 0, prompted.stderr or prompted.stdout)
            screen = subprocess.run(
                [*controller, "terminal", name, "--", "capture-pane", "-p", "-t", created["pane_id"]],
                text=True,
                capture_output=True,
                timeout=10,
            )
            self.assertEqual(screen.returncode, 0, screen.stderr)
            self.assertIn("repo", screen.stdout)
            self.assertNotIn("Branch name:", screen.stdout)
            chosen = subprocess.run([*controller, "terminal", name, "--", "send-keys", "-t", created["pane_id"], "Enter"], capture_output=True, timeout=10)
            self.assertEqual(chosen.returncode, 0, chosen.stderr)
            branch = subprocess.run([*controller, "wait-screen", "--regex", "Branch name:", "--duration", "0.2", "--wait-timeout", "5", name], capture_output=True, timeout=10)
            self.assertEqual(branch.returncode, 0, branch.stderr)
            self.assertFalse((home / "new-branch").exists())
        finally:
            if created is not None:
                closed = subprocess.run([*controller, "close", name], text=True, capture_output=True, timeout=20)
                self.assertEqual(closed.returncode, 0, closed.stderr)

    def test_worktree_popup_from_non_git_workspace_with_no_group_does_not_create(self):
        with tempfile.TemporaryDirectory() as bin_dir:
            herdr = Path(bin_dir) / "herdr"
            herdr.write_text(
                "#!/bin/sh\n"
                "if [ \"$1 $2\" = 'workspace list' ]; then\n"
                "  printf '%s\\n' '{\"result\":{\"workspaces\":[{\"workspace_id\":\"w-primary\",\"label\":\"outside\"}]}}'\n"
                "fi\n"
            )
            herdr.chmod(0o755)
            fzf = Path(bin_dir) / "fzf"
            fzf.write_text("#!/bin/sh\nIFS= read -r choice\nprintf '%s\\n' \"$choice\"\n")
            fzf.chmod(0o755)
            result = subprocess.run(
                ["fish", "--no-config", "-c", f"set fish_function_path {CREATE_WORKTREE.parent}; herdr_new_worktree"],
                input="\n",
                env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "HERDR_ACTIVE_WORKSPACE_ID": "w-primary"},
                text=True,
                capture_output=True,
                timeout=10,
            )
        self.assertIn("Group:", result.stderr)
        self.assertNotIn("cannot overwrite", result.stderr)
        self.assertNotIn("Branch name:", result.stderr)

    def test_worktree_popup_escape_cancels(self):
        with tempfile.TemporaryDirectory() as bin_dir:
            log = Path(bin_dir) / "calls"
            herdr = Path(bin_dir) / "herdr"
            herdr.write_text(
                "#!/bin/sh\n"
                "if [ \"$1 $2\" = 'workspace list' ]; then\n"
                "  printf '%s\\n' '{\"result\":{\"workspaces\":[{\"workspace_id\":\"w-linked\",\"label\":\"task\",\"worktree\":{\"repo_key\":\"repo\"}},{\"workspace_id\":\"w-parent\",\"label\":\"repo\"}]}}'\n"
                "elif [ \"$1 $2\" = 'worktree list' ]; then\n"
                "  printf '%s\\n' '{\"result\":{\"source\":{\"source_workspace_id\":\"w-parent\",\"source_checkout_path\":\"/repo\"},\"worktrees\":[]}}'\n"
                "else\n"
                f"  printf '%s\\n' \"$*\" >> {log}\n"
                "fi\n"
            )
            herdr.chmod(0o755)
            fzf = Path(bin_dir) / "fzf"
            fzf.write_text("#!/bin/sh\nexit 130\n")
            fzf.chmod(0o755)
            result = subprocess.run(
                ["fish", "--no-config", "-c", f"set fish_function_path {CREATE_WORKTREE.parent}; herdr_new_worktree"],
                env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "HERDR_ACTIVE_WORKSPACE_ID": "w-linked"},
                text=True, capture_output=True, timeout=10,
            )
            calls = log.read_text().splitlines() if log.exists() else []
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Group:", result.stderr)
        self.assertEqual(calls, [])

    def test_worktree_popup_branches_from_remote_default_branch(self):
        with tempfile.TemporaryDirectory() as bin_dir:
            log = Path(bin_dir) / "calls"
            herdr = Path(bin_dir) / "herdr"
            herdr.write_text(
                "#!/bin/sh\n"
                "if [ \"$1 $2\" = 'workspace list' ]; then\n"
                "  printf '%s\\n' '{\"result\":{\"workspaces\":[{\"workspace_id\":\"w-linked\",\"label\":\"task\",\"worktree\":{\"repo_key\":\"repo\",\"is_linked_worktree\":true}},{\"workspace_id\":\"w-parent\",\"label\":\"repo\",\"worktree\":{\"repo_key\":\"repo\",\"is_linked_worktree\":false}}]}}'\n"
                "elif [ \"$1 $2\" = 'worktree list' ]; then\n"
                "  printf '%s\\n' '{\"result\":{\"source\":{\"source_workspace_id\":\"w-parent\",\"source_checkout_path\":\"/repo\"},\"worktrees\":[]}}'\n"
                "else\n"
                f"  printf '%s\\n' \"$*\" >> {log}\n"
                "fi\n"
            )
            herdr.chmod(0o755)
            fzf = Path(bin_dir) / "fzf"
            fzf.write_text("#!/bin/sh\nIFS= read -r choice\nprintf '%s\\n' \"$choice\"\n")
            fzf.chmod(0o755)
            git = Path(bin_dir) / "git"
            git.write_text(
                "#!/bin/sh\n"
                "if [ \"$3\" = 'symbolic-ref' ]; then\n"
                "  printf '%s\\n' origin/trunk\n"
                "elif [ \"$3 $4\" = 'rev-parse --path-format=absolute' ]; then\n"
                "  printf '%s\\n' /repo/.bare\n"
                "fi\n"
            )
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
            [
                "worktree create --workspace w-parent --branch feature/new-worktree --base origin/trunk "
                "--path /repo/feature-new-worktree --focus"
            ],
        )

    def test_worktree_popup_can_override_default_group(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repos = [root / "first", root / "second"]
            for repo in repos:
                subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
                subprocess.run(["git", "-C", str(repo), "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-q", "--allow-empty", "-m", "init"], check=True)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            calls = root / "calls"
            herdr = bin_dir / "herdr"
            herdr.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  'workspace list') printf '%s\\n' '{\"result\":{\"workspaces\":[{\"workspace_id\":\"active\",\"label\":\"child\",\"worktree\":{\"repo_key\":\"first\",\"is_linked_worktree\":true}},{\"workspace_id\":\"first\",\"label\":\"first\",\"worktree\":{\"repo_key\":\"first\",\"is_linked_worktree\":false}},{\"workspace_id\":\"second\",\"label\":\"second\",\"worktree\":{\"repo_key\":\"second\",\"is_linked_worktree\":false}},{\"workspace_id\":\"second-child\",\"label\":\"other task\",\"worktree\":{\"repo_key\":\"second\",\"is_linked_worktree\":true}}]}}' ;;\n"
                "  'worktree list --workspace active'|'worktree list --workspace first') printf '%s\\n' \"{\\\"result\\\":{\\\"source\\\":{\\\"source_workspace_id\\\":\\\"first\\\",\\\"source_checkout_path\\\":\\\"$FIRST\\\"}}}\" ;;\n"
                "  'worktree list --workspace second') printf '%s\\n' \"{\\\"result\\\":{\\\"source\\\":{\\\"source_workspace_id\\\":\\\"second\\\",\\\"source_checkout_path\\\":\\\"$SECOND\\\"}}}\" ;;\n"
                f"  *) printf '%s\\n' \"$*\" >> {calls} ;;\n"
                "esac\n"
            )
            herdr.chmod(0o755)
            fzf = bin_dir / "fzf"
            fzf.write_text(f"#!/bin/sh\nIFS= read -r first\nprintf '%s\\n' \"$first\" > {root / 'default'}\ntail -n 1\n")
            fzf.chmod(0o755)
            result = subprocess.run(
                ["fish", "--no-config", "-c", f"set fish_function_path {CREATE_WORKTREE.parent}; herdr_new_worktree"],
                input="cross/repo\n", text=True, capture_output=True, timeout=10,
                env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "FIRST": str(repos[0]), "SECOND": str(repos[1]), "HERDR_ACTIVE_WORKSPACE_ID": "active"},
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((root / "default").read_text().startswith("first\t"))
            self.assertEqual(calls.read_text().splitlines(), [
                f"worktree create --workspace second --branch cross/repo --base main --path {repos[1] / 'cross-repo'} --focus"
            ])

    def test_herdr_session_popup_lists_only_workspaces_by_most_recent_access(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            bin_dir = temp / "bin"
            bin_dir.mkdir()
            calls = temp / "calls"
            captured = temp / "captured"
            herdr = bin_dir / "herdr"
            herdr.write_text(
                "#!/bin/sh\n"
                f"printf '%s\\n' \"$*\" >> {calls}\n"
                "if [ \"$1 $2\" = 'workspace list' ]; then\n"
                "  printf '%s\\n' '{\"result\":{\"workspaces\":[{\"workspace_id\":\"w1\",\"label\":\"Older\",\"number\":1,\"agent_status\":\"idle\",\"focused\":false},{\"workspace_id\":\"w2\",\"label\":\"Recent\",\"number\":2,\"agent_status\":\"working\",\"focused\":false},{\"workspace_id\":\"w3\",\"label\":\"Current\",\"number\":3,\"agent_status\":\"blocked\",\"focused\":true},{\"workspace_id\":\"w4\",\"label\":\"Bare group\",\"number\":4,\"worktree\":{\"repo_key\":\"bare-repo\",\"is_linked_worktree\":false,\"checkout_path\":\"/repo/.bare\"}},{\"workspace_id\":\"w5\",\"label\":\"Bare child\",\"number\":5,\"worktree\":{\"repo_key\":\"bare-repo\",\"is_linked_worktree\":true}},{\"workspace_id\":\"w6\",\"label\":\"Primary group\",\"number\":6,\"worktree\":{\"repo_key\":\"primary-repo\",\"is_linked_worktree\":false,\"checkout_path\":\"/repo/main\"}},{\"workspace_id\":\"w7\",\"label\":\"Primary child\",\"number\":7,\"worktree\":{\"repo_key\":\"primary-repo\",\"is_linked_worktree\":true}},{\"workspace_id\":\"w8\",\"label\":\"Standalone\",\"number\":8,\"worktree\":{\"repo_key\":\"standalone\",\"is_linked_worktree\":false}}]}}'\n"
                "elif [ \"$1 $2\" = 'agent list' ]; then\n"
                "  printf '%s\\n' '{\"result\":{\"agents\":[{\"pane_id\":\"w1:p1\",\"agent_status\":\"idle\",\"workspace_id\":\"w1\",\"agent\":\"pi\"}]}}'\n"
                "fi\n"
            )
            herdr.chmod(0o755)
            fzf = bin_dir / "fzf"
            fzf.write_text(f"#!/bin/sh\nprintf '%s\\n' \"$@\" > {temp / 'fzf-args'}\ntee {captured} | head -n 1\n")
            fzf.chmod(0o755)
            tput = bin_dir / "tput"
            tput.write_text("#!/bin/sh\nprintf '%s\\n' \"${TEST_COLS:-100}\"\n")
            tput.chmod(0o755)
            log_dir = temp / ".config" / "herdr"
            log_dir.mkdir(parents=True)
            (log_dir / "herdr-server.log").write_text(
                '2026-01-01 workspace focused event="workspace.focus" workspace_id="w1"\n'
                '2026-01-02 workspace focused event="workspace.focus" workspace_id="w2"\n'
                '2026-01-03 workspace focused event="workspace.focus" workspace_id="w3"\n'
                '2026-01-04 workspace focused event="workspace.focus" workspace_id="w1"\n'
            )
            result = subprocess.run(
                ["fish", "--no-config", "-c", f"set fish_function_path {MANAGE_HERDR.parent}; manage_herdr_sessions"],
                env={**os.environ, "HOME": temp_dir, "PATH": f"{bin_dir}:{os.environ['PATH']}"},
                text=True,
                capture_output=True,
                timeout=10,
            )
            rows = captured.read_text().splitlines() if captured.exists() else []
            invoked = calls.read_text().splitlines() if calls.exists() else []
            fzf_args = (temp / "fzf-args").read_text().splitlines()
            session_result = subprocess.run(
                ["fish", "--no-config", "-c", f"set fish_function_path {MANAGE_HERDR.parent}; manage_herdr_sessions"],
                env={**os.environ, "HOME": temp_dir, "PATH": f"{bin_dir}:{os.environ['PATH']}", "TEST_COLS": "80"},
                text=True, capture_output=True, timeout=10,
            )
            session_fzf_args = (temp / "fzf-args").read_text().splitlines()
            narrow_result = subprocess.run(
                ["fish", "--no-config", "-c", f"set fish_function_path {MANAGE_HERDR.parent}; manage_herdr_sessions"],
                env={**os.environ, "HOME": temp_dir, "PATH": f"{bin_dir}:{os.environ['PATH']}", "TEST_COLS": "30"},
                text=True, capture_output=True, timeout=10,
            )
            narrow_fzf_args = (temp / "fzf-args").read_text().splitlines()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(session_result.returncode, 0, session_result.stderr)
        self.assertEqual(narrow_result.returncode, 0, narrow_result.stderr)
        self.assertEqual([row.split("\t")[0] for row in rows], ["w1", "w2", "w5", "w7", "w8"])
        self.assertTrue(all(len(row.split("\t")) == 2 for row in rows))
        self.assertIn("\x1b[38;2;158;206;106mRecent\x1b[0m", rows[1])
        self.assertNotIn("working", rows[0])
        self.assertNotIn("Current", "\n".join(rows))
        self.assertEqual(invoked, ["workspace list", "workspace focus w1"])
        picker = MANAGE_HERDR.read_text()
        self.assertIn("jq -R -n", picker)
        self.assertNotIn("--rawfile log", picker)
        self.assertIn("preview_herdr_target", picker)
        self.assertNotIn("--border=rounded", picker)
        self.assertNotIn("--input-border", picker)
        self.assertNotIn("--list-border", picker)
        self.assertIn("--preview-window=right,78%,border-left,nowrap,follow,<65(down,50%,border-top)", fzf_args)
        self.assertIn("--preview-window=right,72%,border-left,nowrap,follow,<65(down,50%,border-top)", session_fzf_args)
        self.assertIn("--preview-window=right,60%,border-left,nowrap,follow,<65(down,50%,border-top)", narrow_fzf_args)
        self.assertIn('width = "90%"', WORKTREE_PLUGIN.read_text())
        self.assertIn("herdr pane read", PREVIEW_HERDR.read_text())

    def test_workspace_preview_removes_terminal_padding_without_losing_ansi_colors(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            herdr = Path(temp_dir) / "herdr"
            calls = Path(temp_dir) / "calls"
            herdr.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$*\" >> \"$CALLS\"\n"
                "if [ \"$1 $2\" = 'pane read' ]; then\n"
                "  printf '\\033[31mHeading\\033[0m\\033[48;2;36;40;59m       \\033[0m\\r\\n\\033[32mstatus bar\\033[0m\\r\\n'\n"
                "else\n  printf '%s\\n' \"$*\"\nfi\n"
            )
            herdr.chmod(0o755)
            result = subprocess.run(
                ["fish", "--no-config", "-c", f"set fish_function_path {PREVIEW_HERDR.parent}; preview_herdr_target agent w1:p1"],
                env={**os.environ, "PATH": f"{temp_dir}:{os.environ['PATH']}", "CALLS": str(calls)},
                text=True, capture_output=True,
            )
            invoked = calls.read_text().splitlines()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(invoked, ["pane read w1:p1 --source recent-unwrapped --lines 200 --format ansi"])
        self.assertEqual(result.stdout, "\x1b[31mHeading\x1b[0m\n\x1b[32mstatus bar\x1b[0m\n")

    def test_workspace_switcher_wraps_long_labels_and_cancels_end_to_end(self):
        name = f"wtswitch{os.getpid() % 100000}"
        controller = ["python3", str(HERDR_AUTOMATION)]
        created = None
        try:
            create = subprocess.run([*controller, "create", name, "--config", str(SOURCE)], text=True, capture_output=True, timeout=20)
            self.assertEqual(create.returncode, 0, create.stderr)
            created = __import__("json").loads(create.stdout)
            config_home = Path(created["home"]).parent / "c"
            plugin = config_home / "herdr/plugins/worktree-tools"
            shutil.copytree(WORKTREE_PLUGIN.parent, plugin)
            functions = config_home / "fish/functions"
            functions.mkdir(parents=True, exist_ok=True)
            for source in (MANAGE_HERDR, PREVIEW_HERDR):
                shutil.copyfile(source, functions / source.name)

            def herdr(*arguments):
                return subprocess.run([*controller, "herdr", name, "--", *arguments], text=True, capture_output=True, timeout=20)

            linked = herdr("plugin", "link", str(plugin))
            self.assertEqual(linked.returncode, 0, linked.stderr)
            label = "long-workspace-name-" * 10
            workspace = herdr("workspace", "create", "--label", label)
            self.assertEqual(workspace.returncode, 0, workspace.stderr)
            for cancel_key in ("Escape", "C-c"):
                deadline = time.monotonic() + 5
                while True:
                    popup = herdr("plugin", "pane", "open", "--plugin", "local.worktree-tools", "--entrypoint", "workspace-switcher", "--focus")
                    if popup.returncode == 0 or time.monotonic() >= deadline:
                        break
                    time.sleep(0.1)
                self.assertEqual(popup.returncode, 0, popup.stderr)
                shown = subprocess.run([*controller, "wait-screen", "--regex", "long-workspace-name", "--duration", "0.2", "--wait-timeout", "5", name], text=True, capture_output=True, timeout=10)
                self.assertEqual(shown.returncode, 0, shown.stderr or shown.stdout)
                screen = subprocess.run([*controller, "terminal", name, "--", "capture-pane", "-p", "-t", created["pane_id"]], text=True, capture_output=True, timeout=10)
                self.assertEqual(screen.returncode, 0, screen.stderr)
                row_lines = [line.split("│▌ ", 1)[-1].split(" │", 1)[0].rstrip() for line in screen.stdout.splitlines() if "│▌ " in line]
                wrapped_label = "".join(line.removeprefix("↳ ") for line in row_lines)
                self.assertEqual(wrapped_label, label)
                self.assertGreater(len(row_lines), 1)
                cancelled = subprocess.run([*controller, "terminal", name, "--", "send-keys", "-t", created["pane_id"], cancel_key], text=True, capture_output=True, timeout=10)
                self.assertEqual(cancelled.returncode, 0, cancelled.stderr)
            deadline = time.monotonic() + 5
            while True:
                reopened = herdr("plugin", "pane", "open", "--plugin", "local.worktree-tools", "--entrypoint", "workspace-switcher", "--focus")
                if reopened.returncode == 0 or time.monotonic() >= deadline:
                    break
                time.sleep(0.1)
            self.assertEqual(reopened.returncode, 0, reopened.stderr)
        finally:
            if created is not None:
                closed = subprocess.run([*controller, "close", name], text=True, capture_output=True, timeout=20)
                self.assertEqual(closed.returncode, 0, closed.stderr)

    def test_herdr_session_popup_uses_most_of_the_terminal(self):
        plugin = tomllib.loads(WORKTREE_PLUGIN.read_text())
        pane = next(entry for entry in plugin["panes"] if entry["id"] == "workspace-switcher")
        self.assertEqual(pane["width"], "90%")
        self.assertEqual(pane["height"], "85%")

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

    def test_prefix_hjkl_forces_unzoom_before_focusing_even_with_nvim_foreground(self):
        parsed = tomllib.loads(SOURCE.read_text())
        keys = parsed["keys"]
        commands = {entry["key"]: (entry["type"], entry["command"]) for entry in keys["command"]}
        directions = {"h": "left", "j": "down", "k": "up", "l": "right"}
        for key, direction in directions.items():
            self.assertEqual(commands[f"prefix+{key}"], ("shell", f"~/.local/bin/herdr-navigate {direction} --force"))

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
            env = {**os.environ, "HERDR_BIN_PATH": str(herdr), "HERDR_ACTIVE_PANE_ID": "w-test:p1"}
            env.pop("HERDR_PANE_ID", None)
            for direction in directions.values():
                with self.subTest(direction=direction):
                    result = subprocess.run(
                        ["/bin/bash", str(NAVIGATE), direction, "--force"],
                        env=env, text=True, capture_output=True,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, f"pane zoom --off --pane w-test:p1\npane focus --direction {direction} --pane w-test:p1\n")

    def test_prefix_arrows_force_unzoom_before_focusing(self):
        keys = tomllib.loads(SOURCE.read_text())["keys"]
        commands = {entry["key"]: (entry["type"], entry["command"]) for entry in keys["command"]}
        for direction in ("left", "down", "up", "right"):
            with self.subTest(direction=direction):
                self.assertEqual(keys[f"focus_pane_{direction}"], "")
                self.assertEqual(
                    commands[f"prefix+{direction}"],
                    ("shell", f"~/.local/bin/herdr-navigate {direction} --force"),
                )

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
        self.assertEqual(
            {entry["plugin_id"] for entry in plugin},
            {"vim-herdr-navigation", "RooseveltAdvisors.herdr-leap", "local.worktree-tools", "local.recent-worktrees"},
        )
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
        worktree_tools = next(entry for entry in plugin if entry["plugin_id"] == "local.worktree-tools")
        self.assertTrue(worktree_tools["enabled"])
        self.assertEqual(worktree_tools["source"]["kind"], "local")
        self.assertEqual(
            {pane["title"] for pane in worktree_tools["panes"]},
            {"Workspace switcher", "Close workspace", "New linked worktree"},
        )
        recent_worktrees = next(entry for entry in plugin if entry["plugin_id"] == "local.recent-worktrees")
        self.assertTrue(recent_worktrees["enabled"])
        self.assertEqual(recent_worktrees["startup"][0]["command"], ["python3", "watch.py"])


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
        self.assertTrue(parsed["session"]["resume_agents_on_restore"])
        self.assertFalse(parsed["experimental"]["pane_history"])
        self.assertEqual(parsed["update"], {"channel": "stable", "version_check": False, "manifest_check": False})
        text = README.read_text()
        for requirement in ("0.9.1", "CPU/disk/RAM", "Cursor", "SUPPORTED", "VALIDATED", "SUPPORTED NATIVELY", "session snapshots", "process", "agent", "screen", "pane_history", "Ghostty", "clipboard", "requested_ref", "resolved_commit", "version", "actions", "enabled", "no tmux fallback", "no external picker", "no process replay", "saved sessions", "screen replay", "mouse selection", "clipboard write", "ordinary paste", "remote image paste", "UNVERIFIED", "BLOCKED", "OSC52"):
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
