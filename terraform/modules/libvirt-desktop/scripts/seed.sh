#!/usr/bin/env bash
# Build a desktop's NoCloud seed ISO and upload it into its (empty) seed volume. Called by OpenTofu
# (terraform_data.seed); every value comes from the environment, never from arguments. Same layout as
# hypervisor/new-desktop.sh: meta-data and user-data for cloud-init (the host name only), locumview/provision.env
# for locumview-provision.service (read straight from the seed on the desktop, never copied).
set -euo pipefail
: "${LV_URI:?}" "${LV_POOL:?}" "${LV_SEED_VOLUME:?}" "${LV_NAME:?}" "${LV_FQDN:?}"
T=$(mktemp -d); chmod 700 "$T"
trap 'find "$T" -type f -exec shred -u {} + 2>/dev/null; rm -rf "$T"' EXIT
umask 077
mkdir -p "$T/seed/locumview"
for k in LV_FQDN IDM_DOMAIN IDM_REALM IDM_SERVER IDM_OTP LVADMIN_PASSWORD GRUB_PASSWORD LUKS_RECOVERY_PASSPHRASE \
         K3S_NODE_CIDRS DNS_IP DESKTOP_USER DESKTOP_RDP_USER DESKTOP_RDP_PASSWORD DEMO_RDP_USER DEMO_RDP_PASSWORD; do
  printf '%s=%s\n' "$k" "${!k-}"
done > "$T/seed/locumview/provision.env"
printf 'instance-id: %s-%s\nlocal-hostname: %s\n' "$LV_NAME" "$(date +%Y%m%d%H%M%S)" "$LV_FQDN" > "$T/seed/meta-data"
printf '#cloud-config\nfqdn: %s\nprefer_fqdn_over_hostname: true\n' "$LV_FQDN" > "$T/seed/user-data"
xorriso -as mkisofs -quiet -o "$T/seed.iso" -V cidata -J -R "$T/seed" 2>/dev/null
virsh -q -c "$LV_URI" vol-upload --pool "$LV_POOL" "$LV_SEED_VOLUME" "$T/seed.iso"
echo "seed uploaded to $LV_POOL/$LV_SEED_VOLUME"
