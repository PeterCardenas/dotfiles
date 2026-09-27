import unittest
from pathlib import Path


SETUP = Path(__file__).with_name("setup.sh")


class SetupDependencyTests(unittest.TestCase):
    def test_supported_setup_paths_install_shared_uv_yq_and_export_local_bin(self):
        setup = SETUP.read_text()
        self.assertIn("function install_kislyuk_yq()", setup)
        self.assertIn('uv tool install --force "yq==3.4.3"', setup)
        self.assertIn('export PATH="$HOME/.local/bin:$PATH"', setup)
        self.assertLess(
            setup.index('export PATH="$HOME/.local/bin:$PATH"'),
            setup.index("install_kislyuk_yq\n\tchezmoi init"),
        )
        self.assertEqual(setup.count("install_kislyuk_yq"), 2)
        self.assertNotIn("python3 -m pip", setup)
        self.assertNotIn("pipx", setup)
        self.assertNotIn("go install github.com/mikefarah/yq", setup)
        self.assertNotIn("PYTHONUSERBASE", setup)
        self.assertNotIn("PYTHON_USER_SCRIPTS", setup)
        self.assertNotIn("--user", setup)

    def test_macos_and_ubuntu_keep_jq_dependency(self):
        setup = SETUP.read_text()
        mac_setup = setup.split("function setup_mac() {", 1)[1].split(
            "function install_ccls_for_mac()", 1
        )[0]
        ubuntu_setup = setup.split("function setup_ubuntu() {", 1)[1].split(
            "function setup_macos_defaults()", 1
        )[0]

        self.assertIn("\t\tjq", mac_setup)
        self.assertIn("\t\tjq", ubuntu_setup)
        self.assertIn("\t\tpython3", ubuntu_setup)

    def test_macos_selects_python3_before_yq_helper_runs(self):
        setup = SETUP.read_text()
        mac_setup = setup.split("function setup_mac() {", 1)[1].split(
            "function install_ccls_for_mac()", 1
        )[0]

        self.assertIn("sudo -B port -N select --set python python312", mac_setup)
        self.assertLess(
            setup.index("sudo -B port -N select --set python python312"),
            setup.index("install_kislyuk_yq\n\tchezmoi init"),
        )


if __name__ == "__main__":
    unittest.main()
