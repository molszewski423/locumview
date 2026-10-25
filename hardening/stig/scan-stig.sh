#!/usr/bin/env bash
# Owner-run read-only assessment; writes and fetches scan evidence, with one sudo prompt on the target.
set -euo pipefail
usage() { echo 'usage: scan-stig.sh [--profile auto|image|reference|<tailoring-profile-id>] user@host [output-dir]'; }
profile=auto
while [[ ${1:-} == --* ]]; do
  case "$1" in
    --profile) [[ $# -ge 2 ]] || { usage >&2; exit 1; }; profile=$2; shift 2 ;;
    --help) usage; exit 0 ;;
    --) shift; break ;;
    *) usage >&2; exit 1 ;;
  esac
done
[[ $# -ge 1 && $# -le 2 ]] || { usage >&2; exit 1; }
TARGET=$1
[[ "$TARGET" =~ ^[A-Za-z0-9_.-]+@[A-Za-z0-9_.:-]+$ && "$TARGET" != -* ]] \
  || { echo 'Expected user@host, without shell metacharacters.' >&2; exit 1; }
case "$profile" in
  auto|image|reference|xccdf_org.locumview_profile_stig_gui|xccdf_org.locumview_profile_stig_gui_image) ;;
  *) echo 'Unknown profile; choose auto, image, reference, or one of the two tailoring profile IDs.' >&2; exit 1 ;;
esac
if [[ "$profile" == auto ]]; then
  profile=$(ssh "$TARGET" 'if test -e /run/ostree-booted; then echo image; else echo reference; fi')
fi
case "$profile" in
  image) profile=xccdf_org.locumview_profile_stig_gui_image ;;
  reference) profile=xccdf_org.locumview_profile_stig_gui ;;
  xccdf_org.locumview_profile_stig_gui|xccdf_org.locumview_profile_stig_gui_image) ;;
  *) echo 'Target returned an invalid desktop type.' >&2; exit 1 ;;
esac
HERE=$(cd "$(dirname "$0")" && pwd)
STAMP=$(date +%Y%m%d-%H%M%S)
OUT=${2:-$PWD/stig-scan-${TARGET#*@}-$STAMP}
R=$(ssh "$TARGET" 'mktemp -d /var/tmp/locumview-stig-scan.XXXXXXXX')
[[ "$R" =~ ^/var/tmp/locumview-stig-scan\.[A-Za-z0-9]+$ ]] \
  || { echo 'Target returned an invalid scan directory.' >&2; exit 1; }
echo "profile: $profile"
scp -q "$HERE/locumview-stig-gui-tailoring.xml" "$HERE/scan-stig-remote.sh" "$TARGET:$R/"
status=0
ssh -t "$TARGET" "sudo bash '$R/scan-stig-remote.sh' '$profile' '$R'" || status=$?
if [[ "$status" != 0 && "$status" != 2 ]]; then
  echo "Remote scan failed (exit $status); attempting to fetch diagnostics." >&2
fi
mkdir -p "$OUT"
if scp -q "$TARGET:$R/*" "$OUT/"; then
  # Results are fetched; the private ARF and report should not stay on the desktop. $R is validated above.
  # shellcheck disable=SC2029
  ssh "$TARGET" "rm -rf -- '$R'" || echo "Could not remove $R on the target; remove it by hand." >&2
else
  echo "Could not fetch results; they remain on the target in $R." >&2
  [[ "$status" != 0 ]] || status=1
fi
echo "pass: $(grep -c '^Result.*pass$' "$OUT/stdout.txt" || true)  fail: $(grep -c '^Result.*fail$' "$OUT/stdout.txt" || true)"
echo "profile: $profile; oscap/remote exit: $status (0 = all pass, 2 = failed rules, other = error)"
echo "results: $OUT"
exit "$status"
