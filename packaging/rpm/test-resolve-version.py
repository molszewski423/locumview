#!/usr/bin/env python3
"""Exercise version selection across real Git histories, without building or publishing packages."""

import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("resolve-version.py")
spec = importlib.util.spec_from_file_location("resolve_version", SCRIPT)
resolver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resolver)


class VersionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "repo"
        self.repo.mkdir()
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.write("packaging/rpm/inputs.txt", "packaging/rpm/**\npackaging/tour/**\n")
        self.write("packaging/rpm/locumview-desktop.spec", "Version: 0.1.0\n")
        self.write("packaging/tour/example", "first\n")
        self.initial = self.commit("initial")

    def git(self, *args):
        return resolver.git(self.repo, *args)

    def write(self, name, value):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)

    def commit(self, message):
        self.git("add", ".")
        subprocess.run(["git", "-C", str(self.repo), "commit", "-qm", message], check=True,
                       env={**os.environ, "GIT_AUTHOR_DATE": "2026-10-22T10:00:00+02:00",
                            "GIT_COMMITTER_DATE": "2026-10-22T10:00:00+02:00"})
        return self.git("rev-parse", "HEAD")

    def test_unrelated_and_future_commits_cannot_change_pin(self):
        first = resolver.resolve(self.repo, self.initial)
        self.write("README.md", "documentation only\n")
        docs = self.commit("docs")
        self.assertEqual(resolver.resolve(self.repo, docs), first)
        self.write("packaging/tour/example", "changed package\n")
        changed = self.commit("new package")
        self.assertEqual(resolver.resolve(self.repo, docs), first)
        self.assertEqual(resolver.resolve(self.repo, changed)["source"], changed)

    def test_release_uses_utc_and_fixed_hash(self):
        result = resolver.resolve(self.repo, "HEAD")
        self.assertEqual(result["release"], f"1.20261022080000git{self.initial[:10]}")
        self.assertEqual(result["evr"], f"0.1.0-{result['release']}.el10")

    def test_merge_selects_tree_introduced_on_build_branch(self):
        self.git("checkout", "-qb", "feature")
        self.write("packaging/tour/example", "feature\n")
        self.commit("feature package")
        self.git("checkout", "-q", "main")
        self.write("README.md", "main docs\n")
        self.commit("main docs")
        self.git("merge", "--no-ff", "--no-gpg-sign", "-qm", "merge", "feature")
        self.assertEqual(resolver.resolve(self.repo, "HEAD")["source"], self.git("rev-parse", "HEAD"))

    def test_spec_version_and_input_list_changes_select_new_source(self):
        self.write("packaging/rpm/locumview-desktop.spec", "Version: 0.2.0\n")
        rev = self.commit("version bump")
        self.assertEqual(resolver.resolve(self.repo, rev)["version"], "0.2.0")
        self.write("packaging/rpm/inputs.txt", "packaging/rpm/**\npackaging/tour/**\nLICENSE\n")
        rev = self.commit("new input")
        self.assertEqual(resolver.resolve(self.repo, rev)["source"], rev)

    def test_shallow_history_is_rejected(self):
        clone = Path(self.temp.name) / "shallow"
        subprocess.run(["git", "clone", "-q", "--depth=1", self.repo.as_uri(), str(clone)], check=True)
        with self.assertRaisesRegex(ValueError, "full Git history"):
            resolver.resolve(clone, "HEAD")

    def test_workflow_path_drift_is_rejected(self):
        self.write(".gitea/workflows/rpms.yml", "on:\n  push:\n    paths:\n"
                   "      - packaging/rpm/**\n      - packaging/tour/**\n")
        resolver.check_workflow(self.repo)
        self.write(".gitea/workflows/rpms.yml", "on:\n  push:\n    paths:\n      - packaging/rpm/**\n")
        with self.assertRaisesRegex(ValueError, "push.paths"):
            resolver.check_workflow(self.repo)

    def image_install_step(self):
        containerfile = (SCRIPT.parents[2] / "image/desktop/Containerfile").read_text()
        step = containerfile.split("RUN --mount=type=secret,id=lanca --mount=type=bind,target=/src \\\n", 1)[1]
        return step.split("\n\n", 1)[0].replace("\\\n", " ")

    def test_image_stops_before_install_when_pin_is_missing(self):
        result = subprocess.run(["bash", "-c", self.image_install_step()], text=True, capture_output=True,
                                env={key: value for key, value in os.environ.items()
                                     if key != "LOCUMVIEW_RPM_EVR"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pass the exact version-release", result.stderr)

    def run_image_install(self, dnf_exit):
        log = Path(self.temp.name) / "dnf-arguments"
        # Run the real build step with package/host commands replaced. No registry, root or container is needed.
        commands = """
install() { :; }
update-ca-trust() { :; }
rm() { :; }
gpg() { echo 'fpr:::::::::F265A948919739767055AD280F02A990167EA18E:'; }
dnf() { printf '%s\\n' "$@" >> "$RPM_TEST_LOG"; return "$RPM_TEST_DNF_EXIT"; }
rpm() { if [ "${2:-}" = --qf ]; then printf '%s' "$LOCUMVIEW_RPM_EVR"; fi; return 0; }
"""
        result = subprocess.run(["bash", "-c", commands + self.image_install_step()], text=True,
                                capture_output=True, env={**os.environ, "LOCUMVIEW_RPM_EVR": "0.1.0-1.test.el10",
                                "RPM_TEST_LOG": str(log), "RPM_TEST_DNF_EXIT": str(dnf_exit)})
        self.assertTrue(log.exists(), result.stderr)
        return result, log.read_text().splitlines()

    def test_image_requests_all_exact_versions(self):
        result, arguments = self.run_image_install(0)
        self.assertEqual(result.returncode, 0, result.stderr)
        packages = [arg for arg in arguments if arg.startswith("locumview-")]
        self.assertEqual(packages, [f"{name}-0.1.0-1.test.el10.noarch" for name in
                         ("locumview-shell-extensions", "locumview-branding", "locumview-tour",
                          "locumview-ehr-launcher")])

    def test_missing_publication_fails_without_retrying_latest(self):
        result, arguments = self.run_image_install(1)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Check the RPM publication job", result.stderr)
        self.assertIn("no newer-version fallback", result.stderr)
        self.assertEqual(arguments.count("install"), 1)


if __name__ == "__main__":
    # Also gate the real workflow against the real input list, including when run from pre-commit.
    resolver.check_workflow(SCRIPT.parents[2])
    unittest.main()
