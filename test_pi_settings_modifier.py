from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parent
MODIFIER = ROOT / "dot_pi/private_agent/modify_settings.json.tmpl"


class PiSettingsModifierTest(unittest.TestCase):
    def render_modifier(self) -> str:
        return subprocess.run(
            ["chezmoi", "execute-template"],
            input=MODIFIER.read_text(encoding="utf-8"),
            text=True,
            capture_output=True,
            check=True,
        ).stdout

    def test_overlays_managed_settings_and_preserves_other_fields(self) -> None:
        rendered = self.render_modifier()
        existing = {
            "quietStartup": False,
            "packages": ["local-package"],
            "extensions": ["local-extension"],
            "theme": "dark",
            "editor": {"fontSize": 14, "wordWrap": True},
        }

        with tempfile.TemporaryDirectory() as home:
            result = subprocess.run(
                ["bash", "-c", rendered],
                input=json.dumps(existing),
                text=True,
                capture_output=True,
                env={**os.environ, "HOME": home},
                check=True,
            )

            settings = json.loads(result.stdout)
            self.assertTrue(settings["quietStartup"])
            self.assertEqual(settings["packages"], ["npm:pi-web-access", "npm:@tintinweb/pi-subagents"])
            self.assertEqual(settings["extensions"], ["~/.pi/agent/extensions/claude-compat.ts"])
            self.assertEqual(settings["theme"], "dark")
            self.assertEqual(settings["editor"], {"fontSize": 14, "wordWrap": True})
            self.assertFalse((Path(home) / ".pi/agent/settings.json").exists())

    def test_initializes_settings_when_target_does_not_exist(self) -> None:
        with tempfile.TemporaryDirectory() as home:
            result = subprocess.run(
                ["bash", "-c", self.render_modifier()],
                input="",
                text=True,
                capture_output=True,
                env={**os.environ, "HOME": home},
                check=True,
            )

        settings = json.loads(result.stdout)
        self.assertTrue(settings["quietStartup"])
        self.assertEqual(settings["packages"], ["npm:pi-web-access", "npm:@tintinweb/pi-subagents"])
        self.assertEqual(settings["extensions"], ["~/.pi/agent/extensions/claude-compat.ts"])


if __name__ == "__main__":
    unittest.main()
