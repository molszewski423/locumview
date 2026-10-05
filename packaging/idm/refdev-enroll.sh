#!/bin/bash
# LocumView reference desktop: join IdM, add break-glass lvadmin, retire the local personal account (changelog #36).
# Start as root, detached (it ends the old molszewski session):
#   sudo systemd-run --unit=lv-idm-enroll --collect bash /var/tmp/lv-idm/refdev-enroll.sh
# Reads REFDEV_ENROLL_OTP and LVADMIN_PASSWORD from /var/tmp/lv-idm/secrets.env and shreds it.
# Log: /var/log/lv-idm-enroll.log
set -euo pipefail
exec >>/var/log/lv-idm-enroll.log 2>&1
echo "=== START $(date -Is)"
DIR=/var/tmp/lv-idm
. "$DIR/secrets.env"; shred -u "$DIR/secrets.env"
FQDN=locumview-ref-dev.corp.locumview.com
# No xtrace: tracing echoed the lvadmin password into the log on the first run (#36). Log steps explicitly.
log() { echo "--- $*"; }

log dns
# 1. DNS: only AdGuard (router advertisements also hand out the ISP's IPv6 resolvers; changelog #15).
C=$(nmcli -t -f NAME,DEVICE con show --active | awk -F: '$2 ~ /^(enp|eth)/{print $1; exit}')
nmcli con mod "$C" ipv6.ignore-auto-dns yes
nmcli con up "$C"
sleep 3
grep -v '^#' /etc/resolv.conf
getent hosts idm01.corp.locumview.com

log hostname
# 2. Hostname in the IdM domain.
hostnamectl set-hostname "$FQDN"

log ipa-client-install
# 3. Join IdM (one-time host password, no admin credentials on the desktop). Keep the existing chrony config.
dnf -y -q install ipa-client
ipa-client-install --unattended --domain=corp.locumview.com --realm=CORP.LOCUMVIEW.COM \
  --server=idm01.corp.locumview.com --hostname="$FQDN" --password="$REFDEV_ENROLL_OTP" \
  --mkhomedir --no-ntp
authselect current

log lvadmin
# 4. Generic local break-glass admin (outside IdM; docs/break-glass.md).
id lvadmin >/dev/null 2>&1 || useradd -m -c "LocumView break-glass admin (local)" -G wheel lvadmin
printf 'lvadmin:%s\n' "$LVADMIN_PASSWORD" | chpasswd
unset LVADMIN_PASSWORD REFDEV_ENROLL_OTP

log retire-local-account
# 5. Retire the local personal account so the IdM account owns the name "molszewski".
systemctl disable --now gnome-headless-session@molszewski.service || true
loginctl terminate-user molszewski || true
sleep 5
pkill -KILL -u molszewski || true
sleep 2
# usermod warns "Failed to change ownership of the home directory" after moving it (#36); the move succeeds, so carry on.
usermod -l molszewski-legacy -d /home/molszewski-legacy -m -c "Pre-IdM local account (retired, changelog #36)" molszewski || true
groupmod -n molszewski-legacy molszewski
restorecon -R /home/molszewski-legacy

log checks
# 6. Checks.
id molszewski-legacy
getent passwd molszewski        # must now come from SSSD (IdM)
id molszewski
sss_cache -E || true
echo "=== DONE $(date -Is)"
