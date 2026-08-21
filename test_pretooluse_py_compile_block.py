from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path


HOOK_PATH = Path(__file__).parent / "dot_claude/hooks/executable_pretooluse_block_py_compile.py"


class PyCompileBlockHookTest(unittest.TestCase):
    def _run_hook(self, command: str) -> dict[str, object]:
        payload = {"tool_input": {"command": command}}
        result = subprocess.run(
            [sys.executable, str(HOOK_PATH)],
            input=json.dumps(payload), text=True, capture_output=True, check=True,
        )
        return json.loads(result.stdout)

    def test_denies_literal_compiler_names_anywhere_in_raw_command(self) -> None:
        commands = (
            "python -m py_compile file.py", "'py_compile'", '"compileall"',
            "COMPILER=py_compile", "sudo -n env compileall .", "command -- py_compile .",
            "{ py_compile; }", "if true; then compileall .; fi", "! py_compile .",
            "echo $(py_compile) && echo $(compileall)", "echo python -m compileall .",
            "echo 'python -m py_compile file.py'", "python -c 'print(\"compileall\")'",
        )
        for command in commands:
            with self.subTest(command=command):
                output = self._run_hook(command)
                hook_output = output["hookSpecificOutput"]
                self.assertEqual(hook_output["permissionDecision"], "deny")
                reason = hook_output["permissionDecisionReason"]
                self.assertIn("py_compile", reason)
                self.assertIn("compileall", reason)

    def test_allows_commands_without_literal_compiler_names(self) -> None:
        for command in ("python3 main.py", "uv run python main.py", "python-config --version", "pythonista"):
            with self.subTest(command=command):
                self.assertEqual(self._run_hook(command), {})

    def test_shell_sources_export_no_bytecode_on_first_line(self) -> None:
        fish = Path(__file__).parent / "dot_config/fish/config.fish"
        nvim = Path(__file__).parent / "dot_config/nvim_conf/kickstart.nvim/init.lua"
        self.assertEqual(fish.read_text().splitlines()[0], "set -gx PYTHONDONTWRITEBYTECODE 1")
        self.assertEqual(nvim.read_text().splitlines()[0], "vim.env.PYTHONDONTWRITEBYTECODE = '1'")


if __name__ == "__main__":
    unittest.main()
