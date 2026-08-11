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

    def test_claude_compat_reads_home_claude_instructions(self) -> None:
        source = EXTENSION.read_text(encoding="utf-8")
        self.assertIn('const claudeInstructionsPath = join(homedir(), "CLAUDE.md");', source)
        self.assertNotIn('join(homedir(), ".claude", "CLAUDE.md")', source)

    def test_claude_compat_appends_managed_context_without_local_instructions(self) -> None:
        source = EXTENSION.read_text(encoding="utf-8")
        function_source = source[source.index('async function appendClaudeInstructions'):]
        managed_call = function_source.index('managed = await runBridge')
        local_guard = function_source.index('const localAlreadyLoaded')
        self.assertGreater(managed_call, local_guard)
        self.assertIn('return managedText ? { systemPrompt: `${event.systemPrompt}${managedText}` } : undefined;', function_source)

    def test_claude_compat_managed_context_failure_preserves_home_claude_behavior(self) -> None:
        source = EXTENSION.read_text(encoding="utf-8")
        function_source = source[source.index('async function appendClaudeInstructions'):]
        managed_call = function_source.index('managed = await runBridge')
        managed_statement = function_source[function_source.rfind('try', 0, managed_call):function_source.index('const managedText', managed_call)]
        self.assertIn('try', managed_statement)
        self.assertIn('catch', managed_statement)
        self.assertIn('managed = { action: "allow" }', managed_statement)
        self.assertIn('const claudeInstructionsPath = join(homedir(), "CLAUDE.md");', source)
        self.assertIn('readFileSync(claudeInstructionsPath, "utf8")', function_source)

    def test_claude_compat_does_not_duplicate_local_instructions(self) -> None:
        source = EXTENSION.read_text(encoding="utf-8")
        self.assertIn('contextFiles.some((file) => file.path === claudeInstructionsPath)', source)
        self.assertIn('const managedText = managed.action === "managed_context"', source)


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

    def _run(
        self,
        event_type: str,
        event: dict[str, object],
        settings: dict[str, object],
        *,
        remote: dict[str, object] | str | None = None,
        endpoint: dict[str, object] | str | None = None,
    ) -> dict[str, object]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".claude").mkdir()
            (root / ".claude/settings.json").write_text(json.dumps(settings), encoding="utf-8")
            if remote is not None:
                (root / ".claude/remote-settings.json").write_text(
                    remote if isinstance(remote, str) else json.dumps(remote), encoding="utf-8"
                )
            endpoint_path = root / "settings.json"
            if endpoint is not None:
                endpoint_path.write_text(
                    endpoint if isinstance(endpoint, str) else json.dumps(endpoint), encoding="utf-8"
                )
            env = {**os.environ, "HOME": str(root)}
            if endpoint is not None:
                env["PI_CLAUDE_MANAGED_SETTINGS_PATH"] = str(endpoint_path)
            result = subprocess.run(
                [sys.executable, str(BRIDGE)],
                input=json.dumps({"event_type": event_type, "event": event, "cwd": str(root)}),
                text=True,
                capture_output=True,
                check=True,
                env=env,
            )
            return json.loads(result.stdout)

    def test_managed_hooks_run_endpoint_then_remote_then_user(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "runs"
            script = "from pathlib import Path; import sys; Path(sys.argv[1]).open('a').write(sys.argv[2]+'\\n')"
            def command(label: str) -> str:
                return f"{sys.executable} -c {json.dumps(script)} {marker} {label}"
            make = lambda label: {"hooks": [{"command": command(label)}]}
            response = self._run("tool_call", {"toolName": "bash", "input": {}}, {"hooks": {"PreToolUse": [{"matcher": ".*", "hooks": make("user")["hooks"]}]}}, remote={"hooks": {"PreToolUse": [{"matcher": ".*", "hooks": make("remote")["hooks"]}]}}, endpoint={"hooks": {"PreToolUse": [{"matcher": ".*", "hooks": make("endpoint")["hooks"]}]}})
            self.assertEqual(response, {"action": "allow"})
            self.assertEqual(marker.read_text().splitlines(), ["endpoint", "remote", "user"])

    def test_endpoint_override_named_settings_json_is_managed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            endpoint = {"allowManagedHooksOnly": True, "hooks": {"PreToolUse": [{"matcher": ".*", "hooks": []}]}}
            user_marker = Path(directory) / "user"
            user_script = f"from pathlib import Path; Path('{user_marker}').write_text('ran')"
            user_command = f"{sys.executable} -c {json.dumps(user_script)}"
            user = {"hooks": {"PreToolUse": [{"matcher": ".*", "hooks": [{"command": user_command}]}]}}
            response = self._run("tool_call", {"toolName": "bash", "input": {}}, user, endpoint=endpoint)
            self.assertEqual(response, {"action": "allow"})
            self.assertFalse(user_marker.exists())

    def test_managed_hooks_only_skips_user_for_tools_and_stop(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            endpoint_marker = Path(directory) / "endpoint"
            user_marker = Path(directory) / "user"
            endpoint_script = "from pathlib import Path; Path('MARKER').write_text('ran')".replace('MARKER', str(endpoint_marker))
            user_script = "from pathlib import Path; Path('MARKER').write_text('ran')".replace('MARKER', str(user_marker))
            endpoint_command = f"{sys.executable} -c {json.dumps(endpoint_script)}"
            user_command = f"{sys.executable} -c {json.dumps(user_script)}"
            managed = {"allowManagedHooksOnly": True, "hooks": {"PreToolUse": [{"matcher": ".*", "hooks": [{"command": endpoint_command}]}], "Stop": [{"hooks": [{"command": endpoint_command}]}]}}
            user = {"hooks": {"PreToolUse": [{"matcher": ".*", "hooks": [{"command": user_command}]}], "Stop": [{"hooks": [{"command": user_command}]}]}}
            self._run("tool_call", {"toolName": "bash", "input": {}}, user, endpoint=managed)
            self.assertTrue(endpoint_marker.exists())
            self.assertFalse(user_marker.exists())
            self._run("stop", {"last_assistant_message": "x"}, user, endpoint=managed)
            self.assertFalse(user_marker.exists())

    def test_malformed_remote_does_not_hide_user_hooks(self) -> None:
        marker = Path(tempfile.gettempdir()) / f"pi-claude-{os.getpid()}"
        try:
            script = "from pathlib import Path; Path('MARKER').write_text('ran')".replace('MARKER', str(marker))
            command = f"{sys.executable} -c {json.dumps(script)}"
            self._run("tool_call", {"toolName": "bash", "input": {}}, {"hooks": {"PreToolUse": [{"matcher": ".*", "hooks": [{"command": command}]}]}}, remote="not json")
            self.assertTrue(marker.exists())
        finally:
            marker.unlink(missing_ok=True)

    def test_managed_context_prefers_endpoint_and_ignores_user(self) -> None:
        response = self._run("managed_context", {}, {"claudeMd": "user"}, remote={"claudeMd": "remote"}, endpoint={"claudeMd": "endpoint"})
        self.assertEqual(response, {"action": "managed_context", "instructions": "endpoint"})

    def test_managed_context_uses_remote_when_endpoint_empty(self) -> None:
        response = self._run("managed_context", {}, {}, remote={"claudeMd": "remote"}, endpoint={"claudeMd": ""})
        self.assertEqual(response, {"action": "managed_context", "instructions": "remote"})

    def test_managed_context_ignores_user_when_endpoint_absent_and_remote_has_no_claude_md(self) -> None:
        response = self._run("managed_context", {}, {"claudeMd": "user"}, remote={})
        self.assertEqual(response, {"action": "allow"})

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
