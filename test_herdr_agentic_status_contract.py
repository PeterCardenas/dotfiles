import os
import re
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).parent
MODULE = ROOT / "dot_config/nvim_conf/kickstart.nvim/lua/utils/agentic_pending.lua"
AGENTIC_CONFIG = ROOT / "dot_config/nvim_conf/kickstart.nvim/lua/plugins/sg.lua"


class HerdrAgenticStatusContractTest(unittest.TestCase):
    def setUp(self):
        self.original_pane_id = os.environ.get("HERDR_PANE_ID")
        os.environ["HERDR_PANE_ID"] = "w1:p1"
        self.addCleanup(self._restore_pane_id)

    def _restore_pane_id(self):
        if self.original_pane_id is None:
            os.environ.pop("HERDR_PANE_ID", None)
        else:
            os.environ["HERDR_PANE_ID"] = self.original_pane_id

    def test_only_active_agentic_session_renames_a_linked_worktree_workspace_with_20_character_label(self):
        lua = textwrap.dedent(
            f"""
            package.loaded['utils.async'] = {{ void = function(func) func() end }}
            package.loaded['utils.shell'] = {{ async_cmd = function(command, args)
              local argv = {{ command }}; vim.list_extend(argv, args)
              if args[1] ~= 'api' then
                local result = vim.system(argv):wait()
                return result.code == 0, {{ stdout = {{ result.stdout }} }}
              end
              argv = {{ 'herdr', 'workspace', 'list' }}
              local result = vim.system(argv):wait()
              local decoded = vim.json.decode(result.stdout)
              decoded.result.snapshot = {{ panes = {{{{ pane_id = 'w1:p1', workspace_id = 'w1' }}}}, workspaces = decoded.result.workspaces }}
              return result.code == 0, {{ stdout = {{ vim.json.encode(decoded) }} }}
            end }}
            package.loaded['utils.workspace_context'] = {{ matches_linked_worktree = function() return true end }}
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
              if argv[2] == 'workspace' and argv[3] == 'list' then
                stdout = vim.json.encode({{ result = {{ workspaces = {{
                  {{ workspace_id = 'base', worktree = {{ repo_key = 'repo', is_linked_worktree = false }} }},
                  {{ workspace_id = 'w1', worktree = {{ repo_key = 'repo', is_linked_worktree = true }} }},
                  {{ workspace_id = 'w2', worktree = {{ repo_key = 'repo', is_linked_worktree = true }} }},
                }} }} }})
              end
              return {{ wait = function() return {{ code = 0, stdout = stdout }} end }}
            end
            local pending = dofile({str(MODULE)!r})
            pending.rename_workspace('Ignore Background', background_tab, 'background')
            pending.rename_workspace('Ignore Stale Session', current_tab, 'stale')
            pending.rename_workspace('Unicode 🐎 workspace title too long', current_tab, 'active')
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
                    "HERDR_PANE_ID": "w1:p1",
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
        self.assertEqual(renames, [["/opt/herdr", "workspace", "rename", "w1", "Unicode 🐎 workspace"]])
        config = AGENTIC_CONFIG.read_text()
        self.assertIn("Pending.rename_workspace(workspace_title, data.tab_page_id, data.session_id)", config)

    def test_checkout_visible_in_worktree_list_but_not_grouped_workspace_is_not_renamed(self):
        lua = textwrap.dedent(
            f"""
            package.loaded['utils.async'] = {{ void = function(func) func() end }}
            package.loaded['utils.shell'] = {{ async_cmd = function(command, args)
              local argv = {{ command }}; vim.list_extend(argv, args)
              if args[1] == 'api' then argv = {{ 'herdr', 'workspace', 'list' }} end
              local result = vim.system(argv):wait()
              local decoded = vim.json.decode(result.stdout)
              decoded.result.snapshot = {{ panes = {{{{ pane_id = 'w1:p1', workspace_id = 'w1' }}}}, workspaces = decoded.result.workspaces }}
              return result.code == 0, {{ stdout = {{ vim.json.encode(decoded) }} }}
            end }}
            package.loaded['utils.workspace_context'] = {{ matches_linked_worktree = function() return true end }}
            local calls = {{}}
            local tab = vim.api.nvim_get_current_tabpage()
            package.loaded['agentic.session_registry'] = {{ sessions = {{ [tab] = {{ session_id = 'active' }} }} }}
            vim.system = function(argv)
              table.insert(calls, argv)
              local stdout = vim.json.encode({{ result = {{ worktrees = {{
                {{ open_workspace_id = 'w1', is_linked_worktree = true, is_bare = false }},
                {{ open_workspace_id = 'w2', is_linked_worktree = true, is_bare = false }},
              }}, workspaces = {{
                {{ workspace_id = 'base', worktree = {{ repo_key = 'repo', is_linked_worktree = false }} }},
                {{ workspace_id = 'w2', worktree = {{ repo_key = 'repo', is_linked_worktree = true }} }},
                {{ workspace_id = 'w1', label = 'review' }},
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

    def test_linked_worktree_without_another_open_worktree_workspace_is_not_renamed(self):
        lua = textwrap.dedent(
            f"""
            package.loaded['utils.async'] = {{ void = function(func) func() end }}
            package.loaded['utils.shell'] = {{ async_cmd = function(command, args)
              local argv = {{ command }}; vim.list_extend(argv, args)
              if args[1] == 'api' then argv = {{ 'herdr', 'workspace', 'list' }} end
              local result = vim.system(argv):wait()
              local decoded = vim.json.decode(result.stdout)
              decoded.result.snapshot = {{ panes = {{{{ pane_id = 'w1:p1', workspace_id = 'w1' }}}}, workspaces = decoded.result.workspaces }}
              return result.code == 0, {{ stdout = {{ vim.json.encode(decoded) }} }}
            end }}
            package.loaded['utils.workspace_context'] = {{ matches_linked_worktree = function() return true end }}
            local calls = {{}}
            local tab = vim.api.nvim_get_current_tabpage()
            package.loaded['agentic.session_registry'] = {{ sessions = {{ [tab] = {{ session_id = 'active' }} }} }}
            vim.system = function(argv)
              table.insert(calls, argv)
              local stdout = vim.json.encode({{ result = {{ workspaces = {{
                {{ workspace_id = 'w1', worktree = {{ repo_key = 'repo', is_linked_worktree = true }} }},
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

    def test_primary_checkout_workspace_is_not_renamed(self):
        lua = textwrap.dedent(
            f"""
            package.loaded['utils.async'] = {{ void = function(func) func() end }}
            package.loaded['utils.shell'] = {{ async_cmd = function(command, args)
              local argv = {{ command }}; vim.list_extend(argv, args)
              if args[1] == 'api' then argv = {{ 'herdr', 'workspace', 'list' }} end
              local result = vim.system(argv):wait()
              local decoded = vim.json.decode(result.stdout)
              decoded.result.snapshot = {{ panes = {{{{ pane_id = 'w1:p1', workspace_id = 'w1' }}}}, workspaces = decoded.result.workspaces }}
              return result.code == 0, {{ stdout = {{ vim.json.encode(decoded) }} }}
            end }}
            package.loaded['utils.workspace_context'] = {{ matches_linked_worktree = function() return true end }}
            local calls = {{}}
            local tab = vim.api.nvim_get_current_tabpage()
            package.loaded['agentic.session_registry'] = {{ sessions = {{ [tab] = {{ session_id = 'active' }} }} }}
            vim.system = function(argv)
              table.insert(calls, argv)
              local stdout = vim.json.encode({{ result = {{ workspaces = {{
                {{ workspace_id = 'w1', worktree = {{ repo_key = 'repo', is_linked_worktree = false }} }},
                {{ workspace_id = 'w2', worktree = {{ repo_key = 'repo', is_linked_worktree = true }} }},
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
            local release_detached = false
            local release_waited = false
            vim.system = function(argv, opts)
              local command = table.concat(argv, ' ')
              table.insert(calls, command)
              local is_release = command:find(' pane release-agent ', 1, true) ~= nil
              if is_release then
                release_detached = opts and opts.detach == true
              end
              return {{
                wait = function()
                  if is_release then release_waited = true end
                  return {{ code = 0 }}
                end,
              }}
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
            vim.fn.writefile({{ vim.json.encode({{
              calls = calls,
              release_detached = release_detached,
              release_waited = release_waited,
            }}) }}, vim.env.HERDR_TEST_OUTPUT)
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
            lifecycle = __import__("json").loads(Path(output.name).read_text())
        calls = lifecycle["calls"]
        self.assertEqual(len(calls), 2)
        report = re.fullmatch(
            r"/opt/herdr pane report-agent w1:p1 --source (agentic\.nvim:\d+:[A-Za-z0-9]+) "
            r"--agent agentic\.nvim --state working --seq (\d+)",
            calls[0],
        )
        release = re.fullmatch(
            r"/opt/herdr pane release-agent w1:p1 --source (agentic\.nvim:\d+:[A-Za-z0-9]+) "
            r"--agent agentic\.nvim --seq (\d+)",
            calls[1],
        )
        self.assertIsNotNone(report)
        self.assertIsNotNone(release)
        assert report is not None and release is not None
        self.assertEqual(report.group(1), release.group(1))
        self.assertLess(int(report.group(2)), int(release.group(2)))
        self.assertTrue(lifecycle.get("release_detached", False))
        self.assertFalse(lifecycle["release_waited"])


if __name__ == "__main__":
    unittest.main()
