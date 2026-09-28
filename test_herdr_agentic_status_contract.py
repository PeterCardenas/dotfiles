import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).parent
MODULE = ROOT / "dot_config/nvim_conf/kickstart.nvim/lua/utils/agentic_pending.lua"
AGENTIC_CONFIG = ROOT / "dot_config/nvim_conf/kickstart.nvim/lua/plugins/sg.lua"


class HerdrAgenticStatusContractTest(unittest.TestCase):
    def test_only_active_agentic_session_renames_a_linked_worktree_workspace(self):
        lua = textwrap.dedent(
            f"""
            local calls = {{}}
            local current_tab = vim.api.nvim_get_current_tabpage()
            vim.cmd.tabnew()
            local background_tab = vim.api.nvim_get_current_tabpage()
            vim.api.nvim_set_current_tabpage(current_tab)
            package.loaded['agentic.session_registry'] = {{ sessions = {{
              [current_tab] = {{ session_id = 'active' }},
              [background_tab] = {{ session_id = 'background' }},
            }} }}
            vim.system = function(argv)
              table.insert(calls, argv)
              local stdout = ''
              if argv[2] == 'worktree' then
                stdout = vim.json.encode({{ result = {{ worktrees = {{
                  {{ open_workspace_id = 'w1', is_linked_worktree = true, is_bare = false }},
                }} }} }})
              end
              return {{ wait = function() return {{ code = 0, stdout = stdout }} end }}
            end
            local pending = dofile({str(MODULE)!r})
            pending.rename_workspace('Ignore Background', background_tab, 'background')
            pending.rename_workspace('Ignore Stale Session', current_tab, 'stale')
            pending.rename_workspace('Active Session Title', current_tab, 'active')
            vim.fn.writefile({{ vim.json.encode(calls) }}, vim.env.HERDR_TEST_OUTPUT)
            """
        )
        with tempfile.NamedTemporaryFile("w", suffix=".lua") as script, tempfile.NamedTemporaryFile() as output:
            script.write(lua)
            script.flush()
            result = subprocess.run(
                ["nvim", "--clean", "--headless", "-u", "NONE", "-i", "NONE", "-l", script.name],
                env={
                    **os.environ,
                    "HERDR_ENV": "1",
                    "HERDR_WORKSPACE_ID": "w1",
                    "HERDR_BIN_PATH": "/opt/herdr",
                    "HERDR_TEST_OUTPUT": output.name,
                },
                text=True,
                capture_output=True,
                timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = __import__("json").loads(Path(output.name).read_text())
        renames = [call for call in calls if call[1:3] == ["workspace", "rename"]]
        self.assertEqual(renames, [["/opt/herdr", "workspace", "rename", "w1", "Active Session Title"]])
        config = AGENTIC_CONFIG.read_text()
        self.assertIn("Pending.rename_workspace(title, data.tab_page_id, data.session_id)", config)
        self.assertIn("nvim_create_autocmd('TabEnter'", config)

    def test_primary_checkout_workspace_is_not_renamed(self):
        lua = textwrap.dedent(
            f"""
            local calls = {{}}
            local tab = vim.api.nvim_get_current_tabpage()
            package.loaded['agentic.session_registry'] = {{ sessions = {{ [tab] = {{ session_id = 'active' }} }} }}
            vim.system = function(argv)
              table.insert(calls, argv)
              local stdout = vim.json.encode({{ result = {{ worktrees = {{
                {{ open_workspace_id = 'w1', is_linked_worktree = false, is_bare = false }},
              }} }} }})
              return {{ wait = function() return {{ code = 0, stdout = stdout }} end }}
            end
            dofile({str(MODULE)!r}).rename_workspace('Do Not Rename', tab, 'active')
            vim.fn.writefile({{ vim.json.encode(calls) }}, vim.env.HERDR_TEST_OUTPUT)
            """
        )
        with tempfile.NamedTemporaryFile("w", suffix=".lua") as script, tempfile.NamedTemporaryFile() as output:
            script.write(lua)
            script.flush()
            result = subprocess.run(
                ["nvim", "--clean", "--headless", "-u", "NONE", "-i", "NONE", "-l", script.name],
                env={**os.environ, "HERDR_ENV": "1", "HERDR_WORKSPACE_ID": "w1", "HERDR_TEST_OUTPUT": output.name},
                text=True,
                capture_output=True,
                timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = __import__("json").loads(Path(output.name).read_text())
        self.assertFalse(any(call[1:3] == ["workspace", "rename"] for call in calls))

    def test_agentic_lifecycle_is_reported_to_the_enclosing_herdr_pane(self):
        lua = textwrap.dedent(
            f"""
            local calls = {{}}
            vim.system = function(argv)
              table.insert(calls, table.concat(argv, ' '))
              return {{ wait = function() return {{ code = 0 }} end }}
            end
            local tab = vim.api.nvim_get_current_tabpage()
            package.loaded['agentic.session_registry'] = {{ sessions = {{
              [tab] = {{ session_id = 'session-1', is_generating = true }},
            }} }}
            local pending = dofile({str(MODULE)!r})
            pending.mark_prompt({{ session_id = 'session-1', tab_page_id = tab }})
            package.loaded['agentic.session_registry'].sessions[tab].is_generating = false
            pending.recompute()
            pending.clear()
            vim.fn.writefile({{ vim.json.encode(calls) }}, vim.env.HERDR_TEST_OUTPUT)
            """
        )
        with tempfile.NamedTemporaryFile("w", suffix=".lua") as script, tempfile.NamedTemporaryFile() as output:
            script.write(lua)
            script.flush()
            result = subprocess.run(
                ["nvim", "--clean", "--headless", "-u", "NONE", "-i", "NONE", "-l", script.name],
                env={
                    **os.environ,
                    "HERDR_ENV": "1",
                    "HERDR_PANE_ID": "w1:p1",
                    "HERDR_BIN_PATH": "/opt/herdr",
                    "HERDR_TEST_OUTPUT": output.name,
                    "TMUX": "",
                    "TMUX_PANE": "",
                },
                text=True,
                capture_output=True,
                timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = __import__("json").loads(Path(output.name).read_text())
        self.assertIn(
            "/opt/herdr pane report-agent w1:p1 --source agentic.nvim --agent agentic.nvim --state working",
            calls,
        )
        self.assertIn(
            "/opt/herdr pane report-agent w1:p1 --source agentic.nvim --agent agentic.nvim --state idle",
            calls,
        )
        self.assertIn(
            "/opt/herdr pane release-agent w1:p1 --source agentic.nvim --agent agentic.nvim",
            calls,
        )


if __name__ == "__main__":
    unittest.main()
