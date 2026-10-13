"""Keep browser shortcuts clear of terminal and multiplexer bindings."""

import json
import re
import shutil
import subprocess
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).parent
SHORTCUTS = ROOT / "dot_config/terminal-browser/shortcuts.json"


def normalize(chord):
    parts = chord.lower().replace("arrow_", "").replace("cmd+", "super+").split("+")
    return tuple(sorted(parts[:-1])), parts[-1]


class TerminalBrowserConfigTest(unittest.TestCase):
    def load_shortcuts(self):
        self.assertTrue(
            SHORTCUTS.is_file(), "terminal-browser shortcuts must be managed by chezmoi"
        )
        return json.loads(SHORTCUTS.read_text())

    def test_zen_bindings_and_terminal_safe_alternatives(self):
        shortcuts = self.load_shortcuts()
        for command, keys in {
            "tab.new": "ctrl+p",
            "tab.close": "ctrl+w",
            "url.edit": "alt+d",
            "find": "alt+f",
            "palette": "alt+k",
            "devtools.console": "ctrl+shift+k",
            "quit": "alt+q",
        }.items():
            self.assertEqual(shortcuts[command], keys)

    def test_shortcuts_are_unique_and_avoid_repo_terminal_bindings(self):
        shortcuts = self.load_shortcuts()
        keys = tomllib.loads((ROOT / "dot_config/herdr/config.toml").read_text())[
            "keys"
        ]
        reserved = {normalize(keys["prefix"])}
        for name, value in keys.items():
            if name == "command":
                reserved.update(normalize(command["key"]) for command in value)
            else:
                reserved.update(
                    normalize(chord)
                    for chord in (value if isinstance(value, list) else [value])
                    if chord
                )
        for config in (ROOT / "dot_config/ghostty").glob("config*"):
            for chord, action in re.findall(
                r"^keybind\s*=\s*(.+?)=(.+)$", config.read_text(), re.MULTILINE
            ):
                if action != "unbind":
                    reserved.add(normalize(chord.removeprefix("global:")))
        assigned = set()
        for command, value in shortcuts.items():
            for chord in value if isinstance(value, list) else [value]:
                normalized = normalize(chord)
                self.assertNotIn(
                    normalized, reserved, f"{command}: {chord} conflicts with terminal"
                )
                self.assertNotIn(
                    normalized, assigned, f"duplicate browser binding: {chord}"
                )
                assigned.add(normalized)

    @unittest.skipUnless(shutil.which("ghostty"), "Ghostty is not installed")
    def test_shortcuts_avoid_effective_ghostty_defaults(self):
        shortcuts = self.load_shortcuts()
        result = subprocess.run(
            ["ghostty", "+list-keybinds"],
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
        reserved = {
            normalize(chord)
            for chord, action in re.findall(
                r"^keybind\s*=\s*(.+?)=(.+)$", result.stdout, re.MULTILINE
            )
            if action != "unbind"
        }
        for command, value in shortcuts.items():
            for chord in value if isinstance(value, list) else [value]:
                self.assertNotIn(
                    normalize(chord),
                    reserved,
                    f"{command}: {chord} conflicts with Ghostty",
                )


if __name__ == "__main__":
    unittest.main()
