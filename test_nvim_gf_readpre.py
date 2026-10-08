"""Keep widget file navigation safe from buffer-switching plugin startup in BufReadPre."""
import re
import unittest
from pathlib import Path


MISC = Path(__file__).parent / "dot_config/nvim_conf/kickstart.nvim/lua/plugins/misc.lua"


class GfReadPreTest(unittest.TestCase):
    def test_buffer_scanning_plugins_load_before_gf_triggers_bufreadpre(self):
        source = MISC.read_text()
        for plugin in ("PeterCardenas/nvim-highlight-colors", "lukas-reineke/indent-blankline.nvim"):
            spec = re.search(r"'" + re.escape(plugin) + r"'.*?\n\s*event = ([^,\n]+)", source, re.S)
            self.assertIsNotNone(spec, plugin)
            self.assertEqual("'VeryLazy'", spec.group(1), plugin)


if __name__ == "__main__":
    unittest.main()
