#!/usr/bin/env bash
# Build a Catalyst VM's NoCloud seed ISO and upload it into its (empty) seed volume. Called by OpenTofu
# (terraform_data.seed); every value comes from the environment. cloud-init gets only what is not secret: the host
# name, the break-glass account with its keys, the home disk, and one command that runs catalyst/provision.sh from the
# seed. The secrets sit in catalyst/provision.env, read from the seed by provision.sh and never copied; the seed is
# wiped once provisioning has finished.
set -euo pipefail
: "${LV_URI:?}" "${LV_POOL:?}" "${LV_SEED_VOLUME:?}" "${LV_NAME:?}" "${LV_FQDN:?}" "${LV_PROVISION:?}" "${CATALYST_BUNDLE:?}"
: "${IDM_DOMAIN:?}" "${IDM_REALM:?}" "${IDM_SERVER:?}" "${IDM_OTP:?}" "${LVADMIN_PASSWORD:?}" "${ADMIN_SSH_KEYS:?}" "${INVENTORY:?}"
git bundle verify -q "$CATALYST_BUNDLE" || { echo "not a valid git bundle: $CATALYST_BUNDLE" >&2; exit 1; }
T=$(mktemp -d); chmod 700 "$T"
trap 'find "$T" -type f -exec shred -u {} + 2>/dev/null; rm -rf "$T"' EXIT
umask 077
mkdir -p "$T/seed/catalyst"
for k in LV_FQDN IDM_DOMAIN IDM_REALM IDM_SERVER IDM_OTP LVADMIN_PASSWORD; do printf '%s=%s\n' "$k" "${!k}"; done > "$T/seed/catalyst/provision.env"
printf '%s\n' "$INVENTORY" > "$T/seed/catalyst/inventory.yml"
cp "$LV_PROVISION" "$T/seed/catalyst/provision.sh"
cp "$CATALYST_BUNDLE" "$T/seed/catalyst/catalyst.bundle"
printf 'instance-id: %s-%s\nlocal-hostname: %s\n' "$LV_NAME" "$(date +%Y%m%d%H%M%S)" "$LV_FQDN" > "$T/seed/meta-data"
{
  printf '#cloud-config\nfqdn: %s\nprefer_fqdn_over_hostname: true\n' "$LV_FQDN"
  printf 'users:\n  - name: lvadmin\n    gecos: Catalyst break-glass admin (local)\n    shell: /bin/bash\n    groups: [sudo]\n'
  printf '    lock_passwd: true\n    ssh_authorized_keys:\n'
  while IFS= read -r key; do [ -n "$key" ] && printf '      - %s\n' "$key"; done <<<"$ADMIN_SSH_KEYS"
  # The home disk: formatted only when blank, so a rebuilt system disk finds the contributor's work again.
  printf 'disk_setup:\n  /dev/vdb: {table_type: gpt, layout: true, overwrite: false}\n'
  printf 'fs_setup:\n  - {label: catalyst-home, filesystem: ext4, device: /dev/vdb, partition: auto, overwrite: false}\n'
  printf 'mounts:\n  - [LABEL=catalyst-home, /home, ext4, "defaults,nofail", "0", "2"]\n'
  printf 'runcmd:\n  - [bash, -c, "mkdir -p /run/catalyst-seed && mount -o ro LABEL=cidata /run/catalyst-seed && bash /run/catalyst-seed/catalyst/provision.sh"]\n'
} > "$T/seed/user-data"
xorriso -as mkisofs -quiet -o "$T/seed.iso" -V cidata -J -R "$T/seed" 2>/dev/null
virsh -q -c "$LV_URI" vol-upload --pool "$LV_POOL" "$LV_SEED_VOLUME" "$T/seed.iso"
echo "seed uploaded to $LV_POOL/$LV_SEED_VOLUME"
