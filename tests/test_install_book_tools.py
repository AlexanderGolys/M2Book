"""Exercise dependency setup without installing into the user's environment."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/install_book_tools.sh"
RENDERER = '''#!/bin/bash
mkdir -p "$2/book"
printf '%s\n' '<span class="katex">math</span><pre class="treesitter">code</pre>' > "$2/book/check.html"
printf '%s\n' "$2" >> "$BUILD_LOG"
'''


class BookToolsFixture(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="m2book-setup-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for command in ["bash", "sh", "mkdir", "mktemp", "rm", "grep", "cp", "cat", "dirname", "date", "sleep"]:
            (self.bin / command).symlink_to(shutil.which(command))
        self.env = dict(os.environ, PATH=str(self.bin),
                        M2BOOK_TOOLS_ROOT=str(self.root / "installed tools"),
                        CARGO_HOME=str(self.root / "cargo home"),
                        RUSTUP_HOME=str(self.root / "rustup home"),
                        RUSTUP_LOG=str(self.root / "rustup.log"),
                        INSTALL_LOG=str(self.root / "install.log"),
                        BUILD_LOG=str(self.root / "build.log"))

    def executable(self, name, contents):
        path = self.bin / name
        path.write_text(contents)
        path.chmod(0o755)
        return path

    def cargo(self):
        self.executable("cargo", '''#!/bin/bash
printf '%s\n' "$*" >> "$INSTALL_LOG"
while (( $# )); do
    if [[ "$1" == --root ]]; then root="$2"; shift; fi
    tool="$1"
    shift
done
mkdir -p "$root/bin"
if [[ "$tool" == mdbook ]]; then
    cp "$RENDERER_FIXTURE" "$root/bin/$tool"
else
    printf '#!/bin/bash\nexit 0\n' > "$root/bin/$tool"
fi
chmod +x "$root/bin/$tool"
''')
        (self.bin / "chmod").symlink_to(shutil.which("chmod"))
        fixture = self.root / "renderer"
        fixture.write_text(RENDERER)
        fixture.chmod(0o755)
        self.env["RENDERER_FIXTURE"] = str(fixture)

    def preprocessors(self):
        for tool in ["mdbook-tsitter", "mdbook-katex"]:
            self.executable(tool, "#!/bin/bash\nexit 0\n")

    def rustup(self):
        self.cargo()
        cargo_fixture = self.root / "cargo-fixture"
        (self.bin / "cargo").rename(cargo_fixture)
        self.env["CARGO_FIXTURE"] = str(cargo_fixture)
        installer = self.root / "rustup-fixture"
        installer.write_text('''#!/bin/sh
printf '%s\n' "$*" > "$RUSTUP_LOG"
mkdir -p "$CARGO_HOME/bin"
cp "$CARGO_FIXTURE" "$CARGO_HOME/bin/cargo"
chmod +x "$CARGO_HOME/bin/cargo"
''')
        self.env["RUSTUP_FIXTURE"] = str(installer)
        self.executable("curl", '''#!/bin/bash
while (( $# )); do
    if [[ "$1" == --output ]]; then cp "$RUSTUP_FIXTURE" "$2"; exit; fi
    shift
done
exit 1
''')

    def run_setup(self):
        return subprocess.run([str(SCRIPT)], env=self.env, capture_output=True, text=True)

class InstallBookToolsTest(BookToolsFixture):
    def test_cargo_installs_missing_tools_and_checks_parsers(self):
        self.cargo()
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = Path(self.env["INSTALL_LOG"]).read_text().splitlines()
        self.assertEqual([line.split()[-1] for line in commands],
                         ["mdbook", "mdbook-tsitter", "mdbook-katex"])
        self.assertTrue(all("install --locked --root" in line for line in commands))
        self.assertTrue(Path(self.env["BUILD_LOG"]).exists())
        self.assertIn("Book tools and parsers are ready", result.stdout)
        self.assertIn("export PATH=", result.stdout)

    def test_existing_tools_are_preserved_without_cargo(self):
        renderer = self.executable("mdbook", RENDERER)
        self.preprocessors()
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(renderer.read_text(), RENDERER)
        self.assertFalse((self.root / "installed tools").exists())

    def test_cargo_only_installs_missing_preprocessors(self):
        self.cargo()
        self.executable("mdbook", RENDERER)
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = Path(self.env["INSTALL_LOG"]).read_text().splitlines()
        self.assertEqual([line.split()[-1] for line in commands],
                         ["mdbook-tsitter", "mdbook-katex"])

    def test_missing_cargo_is_bootstrapped_before_book_tools(self):
        self.rustup()
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = Path(self.env["RUSTUP_LOG"]).read_text()
        self.assertIn("--profile minimal", arguments)
        self.assertIn("--default-toolchain stable", arguments)
        self.assertIn("--no-modify-path", arguments)
        self.assertEqual(len(Path(self.env["INSTALL_LOG"]).read_text().splitlines()), 3)
        self.assertTrue(Path(self.env["BUILD_LOG"]).exists())

    def test_rustup_failure_stops_before_installing_book_tools(self):
        self.rustup()
        Path(self.env["RUSTUP_FIXTURE"]).write_text("#!/bin/sh\nexit 9\n")
        result = self.run_setup()
        self.assertEqual(result.returncode, 9)
        self.assertFalse(Path(self.env["INSTALL_LOG"]).exists())

    def test_missing_curl_reports_how_to_continue(self):
        result = self.run_setup()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Installing Rust and Cargo requires curl", result.stderr)

    def test_failed_cargo_install_does_not_report_success(self):
        self.executable("cargo", "#!/bin/bash\nexit 7\n")
        result = self.run_setup()
        self.assertEqual(result.returncode, 7)
        self.assertNotIn("parsers are ready", result.stdout)

    def test_missing_rendering_is_a_setup_failure(self):
        self.preprocessors()
        self.executable("mdbook", '''#!/bin/bash
mkdir -p "$2/book"
printf 'plain text' > "$2/book/check.html"
''')
        result = self.run_setup()
        self.assertEqual(result.returncode, 1)
        self.assertIn("highlighting is missing", result.stderr)


@unittest.skipUnless(shutil.which(os.environ.get("M2_BIN", "M2")), "Macaulay2 is required")
class M2BookToolsTest(BookToolsFixture):
    def run_m2(self, program, answer=""):
        source = self.root / "setup.m2"
        loader = SCRIPT.parents[1] / "scripts/load_package.m2"
        source.write_text("load " + json.dumps(str(loader)) + ";\n" + program + "\nexit 0\n")
        executable = shutil.which(os.environ.get("M2_BIN", "M2"))
        return subprocess.run([executable, "--script", str(source)],
                              cwd=SCRIPT.parents[1], env=self.env, input=answer,
                              capture_output=True, text=True, timeout=60)

    def test_declining_or_eof_does_not_install(self):
        self.cargo()
        for answer in ["n\n", "\n", "", "maybe\n"]:
            with self.subTest(answer=answer):
                result = self.run_m2("assert(installBookTools() === false);", answer)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Install the missing book tools now?", result.stdout)
                self.assertFalse(Path(self.env["INSTALL_LOG"]).exists())

    def test_approved_install_is_available_in_the_same_session(self):
        self.cargo()
        self.env["M2BOOK_TOOLS_ROOT"] = str(self.root / "installed ' tools")
        result = self.run_m2(
            "assert(installBookTools() === true); assert(installBookTools() === true);",
            "yes\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count("Install the missing book tools now?"), 1)
        commands = Path(self.env["INSTALL_LOG"]).read_text().splitlines()
        self.assertEqual(len(commands), 3)

    def test_rust_installation_requires_explicit_approval(self):
        self.rustup()
        result = self.run_m2("assert(installBookTools() === false);", "n\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Install Rust/Cargo and the missing book tools now?", result.stdout)
        self.assertFalse(Path(self.env["RUSTUP_LOG"]).exists())
        result = self.run_m2("assert(installBookTools() === true);", "yes\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(Path(self.env["RUSTUP_LOG"]).exists())
        self.assertEqual(len(Path(self.env["INSTALL_LOG"]).read_text().splitlines()), 3)

    def test_opening_a_book_asks_and_stops_when_declined(self):
        self.cargo()
        result = self.run_m2('assert((try mdBook "Graphs" else "cancelled") === "cancelled");', "n\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Install the missing book tools now?", result.stdout)
        self.assertFalse(Path(self.env["INSTALL_LOG"]).exists())

    def test_existing_tools_can_be_checked_without_a_prompt(self):
        self.preprocessors()
        self.executable("mdbook", RENDERER)
        result = self.run_m2("assert(installBookTools() === true);")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("Install the missing book tools now?", result.stdout)

    def test_opening_a_book_installs_then_serves_with_the_managed_path(self):
        self.cargo()
        renderer = Path(self.env["RENDERER_FIXTURE"])
        renderer.write_text(RENDERER.replace(
            'mkdir -p "$2/book"',
            'if [[ "$1" == serve ]]; then\n'
            '    printf "%s\\n" "$@" > "$SERVE_LOG"\n'
            '    sleep 5\n'
            '    exit 0\n'
            'fi\nmkdir -p "$2/book"'))
        self.env["SERVE_LOG"] = str(self.root / "serve.log")
        self.env["BROWSER_LOG"] = str(self.root / "browser.log")
        self.env["WWWBROWSER"] = str(self.executable("browser", '''#!/bin/bash
printf '%s\n' "$@" > "$BROWSER_LOG"
'''))
        suffix = os.path.relpath(self.root / "application", os.environ["HOME"]) + "/"
        result = self.run_m2(
            "applicationDirectorySuffix = " + json.dumps(suffix) + ";\n"
            'assert(mdBook "JSON" === "http://127.0.0.1:3000/");', "y\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("serve", Path(self.env["SERVE_LOG"]).read_text())
        self.assertIn("http://127.0.0.1:3000/", Path(self.env["BROWSER_LOG"]).read_text())
        self.assertTrue((self.root / "application/M2Book/markdown/JSON/book.toml").is_file())

    def test_installation_failure_is_reported_to_m2(self):
        self.executable("cargo", "#!/bin/bash\nexit 7\n")
        result = self.run_m2("assert((try installBookTools() else false) === false);", "y\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("Book tools and parsers are ready", result.stdout)


if __name__ == "__main__":
    unittest.main()
