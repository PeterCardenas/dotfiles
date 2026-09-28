"""Contract tests for the pending Herdr-native Neovim navigation change."""
import unittest
from pathlib import Path

ROOT = Path(__file__).parent
TMUX = ROOT / "dot_config/nvim_conf/kickstart.nvim/lua/plugins/tmux.lua"
GHOSTTY = ROOT / "dot_config/nvim_conf/kickstart.nvim/lua/local/ghostty_navigation.lua"
INIT = ROOT / "dot_config/nvim_conf/kickstart.nvim/init.lua"
MODULE = ROOT / "dot_config/nvim_conf/kickstart.nvim/lua/local/herdr_navigation.lua"


class HerdrNvimNavigationContractTest(unittest.TestCase):
    def test_tmux_integration_is_disabled_in_herdr(self):
        text = TMUX.read_text()
        self.assertIn("vim.env.HERDR_ENV ~= '1'", text)

    def test_herdr_module_loads_only_with_required_environment(self):
        self.assertIn("HERDR_ENV", INIT.read_text())
        text = MODULE.read_text()
        self.assertIn("HERDR_ENV", text)
        self.assertIn("HERDR_PANE_ID", text)
        self.assertNotIn("tmux", text.lower())

    def test_navigation_moves_in_nvim_before_focusing_at_edge(self):
        text = MODULE.read_text()
        for direction in ("left", "down", "up", "right"):
            self.assertIn(direction, text)
            self.assertIn("'pane', 'focus'", text)
            self.assertIn("'--direction', direction", text)
            self.assertIn("'--pane', pane_id", text)
        self.assertIn("wincmd", text)
        self.assertLess(text.index("'pane', 'zoom', '--off'"), text.index("'pane', 'focus'"))

    def test_herdr_port_preserves_tmux_navigation_behavior(self):
        text = MODULE.read_text()
        self.assertIn("HERDR_BIN_PATH", text)
        self.assertIn("is_floating_non_fzf", text)
        self.assertIn("vim.bo.filetype == 'fzf'", text)
        self.assertIn("vim.api.nvim_feedkeys", text)
        self.assertIn("vim.keymap.set({ 'n', 'i' }", text)
        self.assertIn("vim.keymap.set('t'", text)

    def test_herdr_port_refreshes_ssh_connection(self):
        text = MODULE.read_text()
        self.assertIn("sync_herdr_ssh_connection", text)
        self.assertIn("vim.env.SSH_CONNECTION", text)
        self.assertIn("Shell.sleep(1000)", text)
        self.assertIn("Async.void", text)

    def test_ghostty_navigation_does_not_compete_inside_herdr(self):
        self.assertIn("vim.env.HERDR_ENV", GHOSTTY.read_text())


if __name__ == "__main__":
    unittest.main()
