#!/usr/bin/env python3
"""Exercise scan orchestration and scanner exit propagation without SSH, sudo or OpenSCAP."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
IMAGE = "xccdf_org.locumview_profile_stig_gui_image"
REFERENCE = "xccdf_org.locumview_profile_stig_gui"


class ScanTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = {**os.environ, "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
                    "TEST_ROOT": str(self.root), "DESKTOP_TYPE": "image", "SCAN_EXIT": "0"}
        self.mock("ssh", """
import json, os, pathlib, shlex, sys
root = pathlib.Path(os.environ['TEST_ROOT'])
with (root/'calls').open('a') as log: log.write(json.dumps(sys.argv[1:])+'\\n')
command = sys.argv[-1]
if command.startswith('if test'):
    if os.environ.get('DETECT_EXIT'): sys.exit(int(os.environ['DETECT_EXIT']))
    print(os.environ['DESKTOP_TYPE'])
elif command.startswith('mktemp'):
    print(os.environ.get('REMOTE_DIR', '/var/tmp/locumview-stig-scan.test1234'))
elif command.startswith('rm '):
    (root/'removed').write_text(shlex.split(command)[-1])
else:
    (root/'profile').write_text(shlex.split(command)[3])
    sys.exit(int(os.environ['SCAN_EXIT']))
""")
        self.mock("scp", """
import os, pathlib, sys
if ':' in sys.argv[-2]:
    if os.environ.get('FETCH_EXIT'): sys.exit(int(os.environ['FETCH_EXIT']))
    root = pathlib.Path(os.environ['TEST_ROOT'])
    out = pathlib.Path(sys.argv[-1]); out.mkdir(parents=True, exist_ok=True)
    (out/'stdout.txt').write_text('Result fail\\n' if os.environ['SCAN_EXIT']=='2' else 'Result pass\\n')
    (out/'profile.txt').write_text((root/'profile').read_text()+'\\n')
    (out/'oscap-exit-code.txt').write_text(os.environ['SCAN_EXIT']+'\\n')
""")

    def mock(self, name, code):
        path = self.bin / name
        path.write_text("#!/usr/bin/env python3\n" + code)
        path.chmod(0o755)

    def scan(self, *flags):
        out = self.root / "results with spaces and 'quotes'"
        result = subprocess.run(["bash", str(HERE / "scan-stig.sh"), *flags,
                                 "operator@desktop", str(out)], env=self.env, text=True, capture_output=True)
        return result, out

    def test_auto_detects_both_desktop_types(self):
        for desktop, expected in (("image", IMAGE), ("reference", REFERENCE)):
            self.env["DESKTOP_TYPE"] = desktop
            result, out = self.scan()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((out / "profile.txt").read_text().strip(), expected)

    def test_explicit_overrides_skip_detection(self):
        self.env["DETECT_EXIT"] = "255"
        for profile, expected in (("image", IMAGE), ("reference", REFERENCE), (IMAGE, IMAGE),
                                  (REFERENCE, REFERENCE)):
            result, out = self.scan("--profile", profile)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((out / "profile.txt").read_text().strip(), expected)

    def test_failures_and_errors_fetch_results_but_remain_nonzero(self):
        for code in (2, 1, 255):
            self.env["SCAN_EXIT"] = str(code)
            result, out = self.scan()
            self.assertEqual(result.returncode, code)
            self.assertEqual((out / "oscap-exit-code.txt").read_text().strip(), str(code))

    def test_fetched_results_are_removed_from_target(self):
        result, _ = self.scan()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "removed").read_text(), "/var/tmp/locumview-stig-scan.test1234")

    def test_failed_fetch_keeps_target_results_and_is_never_success(self):
        self.env["FETCH_EXIT"] = "1"
        for code, expected in ((0, 1), (2, 2), (255, 255)):
            self.env["SCAN_EXIT"] = str(code)
            result, _ = self.scan()
            self.assertEqual(result.returncode, expected, result.stderr)
            self.assertIn("remain on the target", result.stderr)
            self.assertFalse((self.root / "removed").exists())

    def test_unknown_profile_rejected_before_network(self):
        result, _ = self.scan("--profile", "image;false")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "calls").exists())

    def test_failed_detection_does_not_silently_use_reference(self):
        self.env["DETECT_EXIT"] = "255"
        result, out = self.scan()
        self.assertEqual(result.returncode, 255)
        self.assertFalse(out.exists())

    def test_remote_path_cannot_inject_commands(self):
        self.env["REMOTE_DIR"] = "/var/tmp/scan;false"
        result, out = self.scan()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(out.exists())

    def test_remote_helper_records_profile_and_preserves_oscap_result(self):
        self.mock("oscap", """
import os, pathlib, sys
args=sys.argv[1:]
pathlib.Path(os.environ['TEST_ROOT'], 'oscap-args').write_text('\\n'.join(args))
for flag in ('--results-arf', '--report'): pathlib.Path(args[args.index(flag)+1]).write_text('fixture')
print('Result fail' if os.environ['SCAN_EXIT']=='2' else 'Result pass')
sys.exit(int(os.environ['SCAN_EXIT']))
""")
        self.mock("rpm", "print('fixture versions')")
        self.mock("chown", "import os, pathlib, sys; pathlib.Path(os.environ['TEST_ROOT'], 'chowned').write_text(sys.argv[-1])")
        out = self.root / "remote results"
        out.mkdir()
        (out / "locumview-stig-gui-tailoring.xml").write_text("fixture")
        for code in (0, 2, 1):
            env = {**self.env, "SCAN_EXIT": str(code), "SUDO_UID": str(os.getuid()),
                   "SUDO_GID": str(os.getgid())}
            result = subprocess.run(["bash", str(HERE / "scan-stig-remote.sh"), IMAGE, str(out)],
                                    env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, code, result.stderr)
            self.assertEqual((out / "profile.txt").read_text().strip(), IMAGE)
            self.assertEqual((out / "oscap-exit-code.txt").read_text().strip(), str(code))
            self.assertIn(IMAGE, (self.root / "oscap-args").read_text().splitlines())
        # A missing scanner package must not stop the hand-back of results or replace the scan result.
        self.mock("rpm", "print('package scap-security-guide is not installed'); raise SystemExit(1)")
        for code in (0, 1):
            (self.root / "chowned").unlink(missing_ok=True)
            env = {**self.env, "SCAN_EXIT": str(code), "SUDO_UID": str(os.getuid()),
                   "SUDO_GID": str(os.getgid())}
            result = subprocess.run(["bash", str(HERE / "scan-stig-remote.sh"), IMAGE, str(out)],
                                    env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, code, result.stderr)
            self.assertEqual((self.root / "chowned").read_text(), str(out))
            self.assertIn("not installed", (out / "versions.txt").read_text())


if __name__ == "__main__":
    unittest.main()
