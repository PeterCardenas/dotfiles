from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


BRIDGE = Path(__file__).parent / "dot_local/bin/executable_pi-claude-hook-bridge"
EXTENSION = Path(__file__).parent / "dot_pi/private_agent/extensions/claude-compat.ts"
PI_SETTINGS = Path(__file__).parent / "dot_pi/private_agent/settings.json"


class PiClaudeHookBridgeTest(unittest.TestCase):
    def test_pi_settings_registers_extension_for_rpc_processes(self) -> None:
        settings = json.loads(PI_SETTINGS.read_text(encoding="utf-8"))
        self.assertEqual(settings["extensions"], ["~/.pi/agent/extensions/claude-compat.ts"])
        self.assertEqual(settings["defaultProvider"], "applied")
        self.assertEqual(settings["defaultModel"], "gpt-5-6-terra")
        self.assertTrue(settings["quietStartup"])
        self.assertEqual(settings["packages"], ["npm:pi-web-access", "npm:@tintinweb/pi-subagents"])
        self.assertEqual(settings["steeringMode"], "all")
        self.assertNotIn("lastChangelogVersion", settings)
        self.assertNotIn("theme", settings)
        self.assertNotIn("/home/pcardenas", PI_SETTINGS.read_text(encoding="utf-8"))

    def test_claude_stop_reason_maps_pi_stop_reasons(self) -> None:
        source = EXTENSION.read_text(encoding="utf-8")
        self.assertIn("function claudeStopReason", source)
        for pi_reason, claude_reason in (
            ("stop", "end_turn"),
            ("length", "end_turn"),
            ("toolUse", "tool_use"),
            ("error", "error"),
            ("aborted", "aborted"),
            ("pending", "pending"),
        ):
            self.assertIn(f'case "{pi_reason}": return "{claude_reason}";', source)

    def test_agent_end_stop_follow_up_awaits_send_user_message(self) -> None:
        source = EXTENSION.read_text(encoding="utf-8")
        self.assertIn(
            'await pi.sendUserMessage(`Address all Stop-hook feedback by continuing the prior task:',
            source,
        )

    def test_agent_end_bridges_empty_text_with_session_context(self) -> None:
        source = EXTENSION.read_text(encoding="utf-8")
        self.assertNotIn('if (!text.trim()) return undefined;', source)
        self.assertIn("last_assistant_message: text", source)
        self.assertIn("session_id: sessionId", source)

    def test_real_link_hook_runs_from_absolute_source_path(self) -> None:
        command = f"{sys.executable} {str(Path(__file__).parent / 'dot_claude/hooks/executable_stop_check_links.py')}"
        settings = {"hooks": {"Stop": [{"hooks": [{"command": command}]}]}}
        long_message = "A response with enough detail to exceed one hundred and twenty characters without including any URL or references heading, so the link hook should request a follow-up."
        blocked = self._run("stop", {"last_assistant_message": long_message, "stop_reason": "end_turn"}, settings)
        self.assertEqual(blocked["action"], "follow_up")
        self.assertTrue(blocked["reasons"])

        allowed = self._run("stop", {"last_assistant_message": long_message + "\n\nKey References:", "stop_reason": "end_turn"}, settings)
        self.assertEqual(allowed, {"action": "allow"})

    def _run(self, event_type: str, event: dict[str, object], settings: dict[str, object]) -> dict[str, object]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".claude").mkdir()
            (root / ".claude/settings.json").write_text(json.dumps(settings), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(BRIDGE)],
                input=json.dumps({"event_type": event_type, "event": event, "cwd": str(root)}),
                text=True,
                capture_output=True,
                check=True,
                env={**os.environ, "HOME": str(root)},
            )
            return json.loads(result.stdout)

    def test_stop_hook_receives_direct_context_and_follow_up(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "payload.json"
            script = "import json,sys; from pathlib import Path; Path(sys.argv[1]).write_text(sys.stdin.read()); print(json.dumps({'decision':'block','reason':'fix links'}))"
            command = f"{sys.executable} -c {json.dumps(script)} {marker}"
            response = self._run("stop", {"last_assistant_message": "answer", "session_id": "s1"}, {"hooks": {"Stop": [{"hooks": [{"command": command}]}]}})
            payload = json.loads(marker.read_text())
            self.assertEqual(payload["last_assistant_message"], "answer")
            self.assertEqual(payload["session_id"], "s1")
            self.assertEqual(payload["conversation_id"], "s1")
            self.assertEqual(payload["working_directory"], payload["cwd"])
            self.assertEqual(payload["workspace_roots"], [payload["cwd"]])
            self.assertEqual(response, {"action": "follow_up", "reasons": ["fix links"]})

    def test_stop_matcher_does_not_skip_configured_command(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "ran"
            command = f"python3 -c \"from pathlib import Path; Path('{marker}').write_text('ran')\""
            response = self._run("stop", {"last_assistant_message": "answer"}, {"hooks": {"Stop": [{"matcher": "NeverMatches", "hooks": [{"command": command}]}]}})
            self.assertTrue(marker.exists())
            self.assertEqual(response, {"action": "allow"})

    def test_stop_hooks_all_run_and_dedupe_reasons_in_order(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "runs"
            commands = []
            for reason in ("first", "first", "third"):
                script = "from pathlib import Path; import sys; Path(sys.argv[1]).open('a').write(sys.argv[2]+'\\n'); print('{\\\"decision\\\":\\\"block\\\",\\\"reason\\\":\\\"'+sys.argv[2]+'\\\"}')"
                commands.append(f"{sys.executable} -c {json.dumps(script)} {marker} {reason}")
            response = self._run("stop", {"last_assistant_message": "answer", "session_id": "s1"}, {"hooks": {"Stop": [{"hooks": [{"command": command}]} for command in commands]}})
            self.assertEqual(marker.read_text().splitlines(), ["first", "first", "third"])
            self.assertEqual(response, {"action": "follow_up", "reasons": ["first", "third"]})

    def test_stop_hook_failure_does_not_skip_later_hook(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "ran"
            failing = f"{sys.executable} -c {json.dumps('import sys; sys.exit(3)')}"
            later_script = "from pathlib import Path; import sys; Path(sys.argv[1]).write_text('later'); print('not json')"
            commands = [failing, f"{sys.executable} -c {json.dumps(later_script)} {marker}"]
            response = self._run("stop", {"last_assistant_message": "answer", "session_id": "s1"}, {"hooks": {"Stop": [{"hooks": [{"command": command}]} for command in commands]}})
            self.assertTrue(marker.exists())
            self.assertEqual(len(response["reasons"]), 2)

    def test_stop_non_object_json_is_visible_error_and_later_hooks_run(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "ran"
            command = f"python3 -c \"from pathlib import Path; Path('{marker}').write_text('ran')\""
            settings = {"hooks": {"Stop": [{"hooks": [{"command": "python3 -c 'print(42)'"}]}, {"hooks": [{"command": command}]}]}}
            response = self._run("stop", {"last_assistant_message": "answer"}, settings)
            self.assertTrue(marker.exists())
            self.assertEqual(len(response["reasons"]), 1)
            self.assertIn("non-object JSON", response["reasons"][0])


    def test_tool_call_runs_pretooluse_and_maps_deny_to_block(self) -> None:
        command = 'python3 -c "import json; print(json.dumps({\'hookSpecificOutput\': {\'permissionDecision\': \'deny\', \'permissionDecisionReason\': \'nope\'}}))"'
        response = self._run("tool_call", {"toolName": "bash", "input": {}}, {"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"command": command}]}]}})
        self.assertEqual(response, {"action": "block", "reason": "nope"})

    def test_tool_result_runs_posttooluse_and_maps_context(self) -> None:
        command = 'python3 -c "import json; print(json.dumps({\'hookSpecificOutput\': {\'additionalContext\': \'extra\'}}))"'
        response = self._run("tool_result", {"toolName": "bash", "content": []}, {"hooks": {"PostToolUse": [{"matcher": "Bash", "hooks": [{"command": command}]}]}})
        self.assertEqual(response, {"action": "context", "messages": ["extra"]})

    def test_stop_hooks_without_matchers_do_not_run_for_supported_events(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "marker"
            command = f"python3 -c \"from pathlib import Path; Path('{marker}').write_text('ran')\""
            settings = {"hooks": {"Stop": [{"hooks": [{"command": command}]}]}}
            for event_type, event in (("tool_call", {"toolName": "bash", "input": {}}), ("tool_result", {"toolName": "bash", "content": []})):
                response = self._run(event_type, event, settings)
                self.assertEqual(response, {"action": "allow"})
                self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
