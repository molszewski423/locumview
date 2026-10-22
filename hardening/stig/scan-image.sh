#!/bin/bash
# Scan a desktop image against the image STIG profile, inside the image itself (changelog #62). Used by CI on every
# build; the summary becomes a signed attestation on the image, which promotion to "stable" requires.
#   hardening/stig/scan-image.sh <image> <output-dir>
# Writes <output-dir>/arf.xml (full results), scan.txt (oscap's output) and summary.json (the attestation's
# predicate). Exits 1 if a rule fails or errors that image-scan-runtime-only.txt does not list: those rules can only
# be judged on an installed desktop (scan-stig.sh), so everything else must pass here.
set -euo pipefail
IMG=${1:?image}; OUT=${2:?output directory}
HERE=$(cd "$(dirname "$0")" && pwd)
PROFILE=xccdf_org.locumview_profile_stig_gui_image
# 0755, not world-writable: rootless podman maps the container's root to this user, and the directory is mounted
# into the scanned container, where a world-writable directory without the sticky bit fails
# dir_perms_world_writable_sticky_bits (seen in CI on ext4; tmpfs is not checked, which hid it locally).
install -d -m 0755 "$OUT"
# No network: the scan needs none, and remote content (OVAL from the internet) must not be fetched.
podman run --rm --network none -v "$HERE:/t:ro,Z" -v "$OUT:/out:Z" "$IMG" bash -c '
  oscap xccdf eval --profile '"$PROFILE"' --tailoring-file /t/locumview-stig-gui-tailoring.xml \
    --results-arf /out/arf.xml /usr/share/xml/scap/ssg/content/ssg-rhel10-ds.xml > /out/scan.txt 2>&1
  rc=$?; [ "$rc" = 0 ] || [ "$rc" = 2 ] || { echo "oscap exited $rc"; tail -5 /out/scan.txt; exit 1; }
  rpm -q --qf "%{VERSION}-%{RELEASE}\n" scap-security-guide > /out/ssg-version
  rpm -q --qf "%{VERSION}-%{RELEASE}\n" openscap-scanner > /out/oscap-version'
python3 -I - "$OUT" "$HERE/image-scan-runtime-only.txt" "$PROFILE" <<'PY'
import datetime, fnmatch, json, sys
out, listing, profile = sys.argv[1:4]
patterns = [l.split()[0] for l in open(listing) if l.strip() and not l.startswith("#")]
results, rule = {}, None
for line in open(f"{out}/scan.txt", encoding="utf-8", errors="replace", newline="\n"):  # oscap writes "Rule\r\t..."
    key, _, val = line.replace("\r", "").rstrip("\n").partition("\t")
    if key == "Rule":
        rule = val.removeprefix("xccdf_org.ssgproject.content_rule_")
    elif key == "Result" and rule:
        results[rule] = val
        rule = None
if len(results) < 300:
    sys.exit(f"only {len(results)} results: the scan did not run as expected")
counts = {}
for r in results.values():
    counts[r] = counts.get(r, 0) + 1
bad = sorted(r for r, v in results.items() if v in ("fail", "error"))
runtime_only = [r for r in bad if any(fnmatch.fnmatchcase(r, p) for p in patterns)]
unexpected = [r for r in bad if r not in runtime_only]
summary = {
    "profile": profile,
    "tailoring": "hardening/stig/locumview-stig-gui-tailoring.xml",
    "scanner": "openscap-scanner " + open(f"{out}/oscap-version").read().strip(),
    "content": "scap-security-guide " + open(f"{out}/ssg-version").read().strip(),
    "scannedOn": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "counts": counts,
    "runtimeOnly": runtime_only,
    "unexpected": unexpected,
    "result": "pass" if not unexpected else "fail",
}
json.dump(summary, open(f"{out}/summary.json", "w"), indent=1)
print("image scan:", ", ".join(f"{v} {k}" for k, v in sorted(counts.items())),
      f"| {len(runtime_only)} judged on installed desktops only | unexpected: {unexpected or 'none'}")
sys.exit(1 if unexpected else 0)
PY
