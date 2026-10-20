#!/usr/bin/env bash
# Wait until first-boot provisioning ejects the seed (it does so only after every step succeeded), then wipe the
# seed volume, which held this desktop's secrets. Called by OpenTofu (terraform_data.provisioned).
set -euo pipefail
: "${LV_URI:?}" "${LV_POOL:?}" "${LV_NAME:?}" "${LV_SEED_TARGET:?}" "${LV_SEED_VOLUME:?}" "${LV_TIMEOUT_MIN:?}"
V=(virsh -q -c "$LV_URI")
tray_open() { "${V[@]}" dumpxml "$LV_NAME" | grep -q "<target dev='$LV_SEED_TARGET' bus='sata' tray='open'/>"; }
echo "waiting up to $LV_TIMEOUT_MIN min for $LV_NAME to install and provision"
end=$(( $(date +%s) + LV_TIMEOUT_MIN * 60 ))
until tray_open; do
  if [ "$(date +%s)" -ge "$end" ]; then
    echo "provisioning did not finish; the seed stays. On the desktop's console: journalctl -u locumview-provision" >&2
    exit 1
  fi
  sleep 10
done
"${V[@]}" vol-wipe --pool "$LV_POOL" "$LV_SEED_VOLUME" >/dev/null
echo "$LV_NAME provisioned; seed volume wiped"
