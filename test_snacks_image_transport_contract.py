"""Contract tests for Snacks image transport inside Herdr."""
import unittest
from pathlib import Path

ROOT = Path(__file__).parent
SNACKS_CONFIG = ROOT / "dot_config/nvim_conf/kickstart.nvim/lua/plugins/misc.lua"


class SnacksImageTransportContractTest(unittest.TestCase):
    def test_herdr_uses_server_local_file_transport_even_over_ssh(self):
        text = SNACKS_CONFIG.read_text()
        override = "if vim.env.HERDR_ENV == '1' then\n        vim.env.SNACKS_SSH = 'false'\n      end"
        self.assertIn(override, text)
        self.assertLess(text.index(override), text.index("require('snacks.image.terminal').envs()"))


if __name__ == "__main__":
    unittest.main()
