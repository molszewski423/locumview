#!/usr/bin/env bash
# Apply the LocumView STIG tailoring to a desktop over SSH with Ansible.
# Usage: hardening/stig/apply-stig.sh <user@host> [extra ansible-playbook args]
# The playbook is generated on the target from its own installed SSG content,
# so the remediation always matches the scanner version there. Asks for the
# target's sudo password once (-K).
set -euo pipefail
TARGET=${1:?usage: apply-stig.sh user@host [ansible args]}; shift
HOST=${TARGET#*@}; USER_=${TARGET%@*}
HERE=$(cd "$(dirname "$0")" && pwd)
DS=/usr/share/xml/scap/ssg/content/ssg-rhel10-ds.xml
PROFILE=xccdf_org.locumview_profile_stig_gui
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

scp -q "$HERE/locumview-stig-gui-tailoring.xml" "$TARGET:/var/tmp/"
ssh "$TARGET" "oscap xccdf generate fix --fix-type ansible \
  --tailoring-file /var/tmp/locumview-stig-gui-tailoring.xml \
  --profile $PROFILE --output /var/tmp/locumview-stig-playbook.yml $DS"
scp -q "$TARGET:/var/tmp/locumview-stig-playbook.yml" "$WORK/"

ANSIBLE_PIPELINING=1 ANSIBLE_HOST_KEY_CHECKING=1 \
  ansible-playbook -i "$HOST," -u "$USER_" -b -K "$@" \
  "$HERE/pre-authselect.yml" "$WORK/locumview-stig-playbook.yml" | tee "locumview-stig-$HOST-$(date +%Y%m%d-%H%M%S).log"
