from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).parent
MANIFEST = ROOT / "dot_pi/private_agent/npm/package.json"
REMOVE = ROOT / ".chezmoiremove"


class PiMigrationFollowupsTest(unittest.TestCase):
    def test_managed_npm_manifest_includes_runtime_packages_and_host_sdk(self) -> None:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        dependencies = manifest["dependencies"]
        self.assertIn("pi-web-access", dependencies)
        self.assertIn("pi-subagents", dependencies)
        self.assertEqual(dependencies["pi-subagents"], "0.81.0")
        self.assertEqual(dependencies["pi-web-access"], "0.44.0")
        self.assertEqual(dependencies["@earendil-works/pi-coding-agent"], "1.4.0")

    def test_extension_development_sdk_matches_managed_runtime(self) -> None:
        runtime = json.loads(MANIFEST.read_text(encoding="utf-8"))
        development = json.loads(
            (ROOT / "dot_pi/private_agent/extensions/package.json").read_text(encoding="utf-8")
        )
        package = "@earendil-works/pi-coding-agent"
        self.assertEqual(development["devDependencies"][package], runtime["dependencies"][package])

    def test_agent_scan_dirs_only_use_trusted_global_location(self) -> None:
        settings = json.loads(
            (ROOT / ".chezmoitemplates/pi-settings.json").read_text(encoding="utf-8")
        )
        self.assertEqual(settings["subagents"]["agentScanDirs"], ["~/.claude/agents"])

    def test_legacy_explore_source_is_absent_and_removal_is_managed(self) -> None:
        self.assertFalse((ROOT / "dot_pi/private_agent/agents/Explore.md").exists())
        self.assertIn(".pi/agent/agents/Explore.md", REMOVE.read_text(encoding="utf-8").splitlines())


if __name__ == "__main__":
    unittest.main()
