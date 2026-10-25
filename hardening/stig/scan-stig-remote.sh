#!/usr/bin/env bash
# Copied by scan-stig.sh and run by the owner with sudo. No remediation is performed.
set -euo pipefail
profile=${1:?profile required}
out=${2:?output directory required}
case "$profile" in
  xccdf_org.locumview_profile_stig_gui|xccdf_org.locumview_profile_stig_gui_image) ;;
  *) echo 'Unsupported tailoring profile.' >&2; exit 1 ;;
esac
[[ -d "$out" && -f "$out/locumview-stig-gui-tailoring.xml" ]]
owner="${SUDO_UID:?run through sudo}:${SUDO_GID:?run through sudo}"
# Hand everything back to the invoking user on any exit, so scan-stig.sh can fetch results and diagnostics.
trap 'chown -R "$owner" "$out"' EXIT
umask 077
printf '%s\n' "$profile" > "$out/profile.txt"
status=0
oscap xccdf eval \
  --tailoring-file "$out/locumview-stig-gui-tailoring.xml" \
  --profile "$profile" \
  --results-arf "$out/arf.xml" --report "$out/report.html" \
  /usr/share/xml/scap/ssg/content/ssg-rhel10-ds.xml > "$out/stdout.txt" 2>&1 || status=$?
printf '%s\n' "$status" > "$out/oscap-exit-code.txt"
# A missing package is recorded ("package ... is not installed"), not allowed to replace the scan result.
rpm -q openscap-scanner scap-security-guide > "$out/versions.txt" || true
echo "oscap exit $status (0 = all pass, 2 = failed rules, other = error)"
exit "$status"
