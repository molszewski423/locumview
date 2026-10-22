#!/usr/bin/env python3
"""Resolve the same RPM source and version for package and image builds, using Git only."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def input_paths(text):
    paths = [line.strip() for line in text.splitlines() if line.strip() and not line.startswith("#")]
    if not paths or len(paths) != len(set(paths)):
        raise ValueError("RPM input list must be nonempty and contain no duplicates")
    return paths


def check_workflow(repo):
    """Read the deliberately simple YAML paths list without needing a YAML dependency."""
    expected = input_paths((Path(repo) / "packaging/rpm/inputs.txt").read_text())
    workflow = (Path(repo) / ".gitea/workflows/rpms.yml").read_text()
    match = re.search(r"(?m)^    paths:\n((?:      - [^\n]+\n)+)", workflow)
    if not match:
        raise ValueError("cannot find rpms.yml push.paths list")
    actual = [line.strip()[2:].strip("\"'") for line in match[1].splitlines()]
    if actual != expected:
        raise ValueError("rpms.yml push.paths must match packaging/rpm/inputs.txt in order")


def resolve(repo, revision):
    if git(repo, "rev-parse", "--is-shallow-repository") != "false":
        raise ValueError("RPM version resolution requires full Git history; fetch --unshallow first")
    revision = git(repo, "rev-parse", "--verify", f"{revision}^{{commit}}")
    paths = input_paths(git(repo, "show", f"{revision}:packaging/rpm/inputs.txt"))
    # First-parent history represents the input tree actually introduced on the build branch, including merges.
    source = git(repo, "log", "--first-parent", "-1", "--format=%H", revision, "--", *paths)
    if not source:
        raise ValueError("no RPM input commit found")
    spec = git(repo, "show", f"{source}:packaging/rpm/locumview-desktop.spec")
    version = re.search(r"(?m)^Version:\s*([0-9][A-Za-z0-9._+]*)\s*$", spec)
    if not version:
        raise ValueError("RPM spec must have a literal Version")
    timestamp = int(git(repo, "show", "-s", "--format=%ct", source))
    stamp = datetime.fromtimestamp(timestamp, timezone.utc).strftime("%Y%m%d%H%M%S")
    # Fixed hash length: adding unrelated objects must not change Git's abbreviation and hence the release.
    release = f"1.{stamp}git{source[:10]}"
    return {"source": source, "version": version[1], "release": release,
            "evr": f"{version[1]}-{release}.el10"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("revision", nargs="?", default="HEAD")
    parser.add_argument("--format", choices=["json", "tsv"], default="json")
    parser.add_argument("--check-inputs", action="store_true")
    args = parser.parse_args()
    try:
        repo = git(".", "rev-parse", "--show-toplevel")
        if args.check_inputs:
            check_workflow(repo)
        result = resolve(repo, args.revision)
        print("\t".join(result.values()) if args.format == "tsv" else json.dumps(result, sort_keys=True))
    except (ValueError, subprocess.CalledProcessError) as error:
        print(f"RPM version resolution failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
