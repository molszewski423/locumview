#!/bin/bash
# First IdM server (ADR 0006, changelog #32). Run on idm01 as root:
#   ipa-install.sh /root/idm-secrets.env    (IDM_DM_PASSWORD, IDM_ADMIN_PASSWORD, plus IDM_IP and DNS_IP from
#                                            site.env; the file is shredded afterwards)
set -uo pipefail
. "$1"
: "${IDM_IP:?}" "${DNS_IP:?}"
echo "START $(date -u +%FT%TZ)"
ipa-server-install --unattended \
  --realm CORP.LOCUMVIEW.COM --domain corp.locumview.com \
  --hostname idm01.corp.locumview.com --ip-address "$IDM_IP" \
  --ds-password "$IDM_DM_PASSWORD" --admin-password "$IDM_ADMIN_PASSWORD" \
  --setup-dns --forwarder "$DNS_IP" --forward-policy=only --auto-reverse \
  --no-dnssec-validation --mkhomedir
rc=$?
shred -u "$1"
echo "RESULT rc=$rc $(date -u +%FT%TZ)"
