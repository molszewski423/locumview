#!/usr/bin/env bash
# First boot of a Catalyst VM, run once by cloud-init from the seed (mounted read-only at /run/catalyst-seed).
# Sets the break-glass password, joins IdM with the one-time password, applies Catalyst's headless profile from the
# bundle, and ejects the seed only when every step has succeeded; OpenTofu then wipes it. Secrets are read from the
# seed and never written to disk or the log.
set -euo pipefail
SEED=/run/catalyst-seed/catalyst
exec >>/var/log/catalyst-provision.log 2>&1
log() { echo "--- $(date -Is) $*"; }
log start
get() { sed -n "s/^$1=//p" "$SEED/provision.env"; }
FQDN=$(get LV_FQDN)

log break-glass password
printf 'lvadmin:%s\n' "$(get LVADMIN_PASSWORD)" | chpasswd
passwd -u lvadmin >/dev/null

log packages
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q freeipa-client git eject

log join IdM as "$FQDN"
hostnamectl set-hostname "$FQDN"
ipa-client-install --unattended --domain="$(get IDM_DOMAIN)" --realm="$(get IDM_REALM)" --server="$(get IDM_SERVER)" \
  --hostname="$FQDN" --password="$(get IDM_OTP)" --mkhomedir --no-ntp
getent passwd admin >/dev/null && echo "IdM accounts resolve through SSSD"

log Catalyst checkout and inventory
install -d -o lvadmin -g lvadmin -m 0755 /home/lvadmin
# The seed's files are root-only, so root fetches and then hands the checkout over. The bundle holds one ref, which
# need not be a branch (tofu.sh bundles origin/main), so it is fetched by name rather than cloned.
C=/home/lvadmin/catalyst
if ! git -C "$C" rev-parse -q --verify HEAD >/dev/null 2>&1; then
  rm -rf "$C"
  git init -q -b main "$C"
  git -C "$C" fetch -q "$SEED/catalyst.bundle" "$(git bundle list-heads "$SEED/catalyst.bundle" | awk 'NR == 1 {print $2}')"
  git -C "$C" reset -q --hard FETCH_HEAD
fi
chown -R lvadmin:lvadmin "$C"
install -o lvadmin -g lvadmin -m 0600 "$SEED/inventory.yml" /home/lvadmin/catalyst-inventory.yml

log apply the headless profile
SUDO_USER=lvadmin bash "$C/scripts/bare-metal-apply.sh" --activate
log "provisioning complete"
eject /dev/sr0 || eject "$(blkid -L cidata)"
