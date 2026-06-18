from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path


HOOK_PATH = (
    Path(__file__).parent
    / "dot_claude/hooks/executable_pretooluse_block_py_compile.py"
)


class PyCompileBlockHookTest(unittest.TestCase):
    def _run_hook(self, command: str) -> dict[str, object]:
        self.assertTrue(HOOK_PATH.exists(), f"missing hook: {HOOK_PATH}")
        payload = {"tool_input": {"command": command}}
        result = subprocess.run(
            [sys.executable, str(HOOK_PATH)],
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            check=True,
        )
        return json.loads(result.stdout)

    def test_blocks_python_module_py_compile(self) -> None:
        output = self._run_hook("python3 -m py_compile path/to/file.py")

        hook_output = output["hookSpecificOutput"]
        self.assertEqual(hook_output["permissionDecision"], "deny")
        self.assertIn("compile(", hook_output["permissionDecisionReason"])
        self.assertNotIn("PYTHONPYCACHEPREFIX", hook_output["permissionDecisionReason"])

    def test_blocks_direct_py_compile_command(self) -> None:
        output = self._run_hook("py_compile path/to/file.py")

        hook_output = output["hookSpecificOutput"]
        self.assertEqual(hook_output["permissionDecision"], "deny")

    def test_allows_compile_builtin_syntax_check(self) -> None:
        command = (
            "python3 -c 'import sys, tokenize; "
            "[compile(tokenize.open(p).read(), p, \"exec\") for p in sys.argv[1:]]' "
            "path/to/file.py"
        )

        self.assertEqual(self._run_hook(command), {})

    def test_ignores_py_compile_inside_quoted_string(self) -> None:
        self.assertEqual(self._run_hook("python3 -c 'print(\"py_compile\")'"), {})


if __name__ == "__main__":
    unittest.main()
