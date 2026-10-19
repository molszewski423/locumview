#!/usr/bin/env bash
# Scan a desktop against the LocumView STIG tailoring (read-only) and fetch the results.
# Usage: hardening/stig/scan-stig.sh <user@host> [output dir]
# Asks for the target's sudo password once.
set -euo pipefail
TARGET=${1:?usage: scan-stig.sh user@host [output dir]}
HERE=$(cd "$(dirname "$0")" && pwd)
STAMP=$(date +%Y%m%d-%H%M%S)
OUT=${2:-$PWD/stig-scan-${TARGET#*@}-$STAMP}
R=/var/tmp/locumview-stig-scan-$STAMP

scp -q "$HERE/locumview-stig-gui-tailoring.xml" "$TARGET:/var/tmp/"
ssh -t "$TARGET" "sudo bash -c '
  mkdir -p $R
  oscap xccdf eval \
    --tailoring-file /var/tmp/locumview-stig-gui-tailoring.xml \
    --profile xccdf_org.locumview_profile_stig_gui \
    --results-arf $R/arf.xml --report $R/report.html \
    /usr/share/xml/scap/ssg/content/ssg-rhel10-ds.xml > $R/stdout.txt 2>&1
  echo \"oscap exit \$? (0 = all pass, 2 = some rules failed)\"
  rpm -q openscap-scanner scap-security-guide > $R/versions.txt
  chown -R \$SUDO_USER: $R'"
mkdir -p "$OUT"
scp -q "$TARGET:$R/*" "$OUT/"
echo "pass: $(grep -c '^Result.*pass$' "$OUT/stdout.txt")  fail: $(grep -c '^Result.*fail$' "$OUT/stdout.txt")"
echo "results: $OUT"
