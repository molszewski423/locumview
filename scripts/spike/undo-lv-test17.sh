#!/usr/bin/env bash
# Owner run on lv-test17 with sudo: undo every ADR 0019 spike change on the desktop (docs/plans/adr-0019-spike.md
# section 6), so lv-test17 is clean for the build's :testing image. Then reboot it to drop the /usr overlay
# (tpm2-pkcs11 and its tools). The IdM and cluster pieces are undone separately: mtls-endpoint.sh down and
# idm-subca.sh down, from operator-laptop.
set -euo pipefail
export SYSTEMD_PAGER=cat PAGER=cat
[ "$(id -u)" = 0 ] || { echo "STOP: run with sudo"; exit 1; }
[ "$(hostname -s)" = lv-test17 ] || { echo "STOP: not lv-test17"; exit 1; }
U=${1:-molszewski}; H=$(getent passwd "$U" | cut -d: -f6); POL=/etc/opt/chrome/policies/managed
B=/etc/pki/locumview-spike

echo "== certmonger (B2): request, drop-in, machine token, /etc/tpm2_pkcs11 link"
getcert stop-tracking -i lv-spike-client </dev/null >/dev/null 2>&1 || true
rm -f /etc/systemd/system/certmonger.service.d/90-locumview-spike.conf
rmdir /etc/systemd/system/certmonger.service.d 2>/dev/null || true
systemctl daemon-reload; systemctl try-restart certmonger
[ "$(readlink /etc/tpm2_pkcs11 2>/dev/null)" = "$B/tpm2" ] && rm -f /etc/tpm2_pkcs11
rm -rf "$B" /root/.tpm2_pkcs11

echo "== Chrome policies back as the image shipped them"
rm -f "$POL/90-locumview-spike-mtls.json"
if [ -f /root/50-locumview-ehr-sites.json.spike-orig ]; then
  mv /root/50-locumview-ehr-sites.json.spike-orig "$POL/50-locumview-ehr-sites.json"; restorecon "$POL"/*.json
fi
if grep -l -e mtls-spike -e 18443 "$POL"/*.json; then echo "STOP: a spike URL is still in a policy"; exit 1; fi

echo "== system trust: the throwaway test CA"
rm -f /etc/pki/ca-trust/source/anchors/locumview-spike-test-ca.pem; update-ca-trust extract

echo "== $U: token, NSS entries, files; TPM access"
runuser -u "$U" -- certutil -D -d "sql:$H/.pki/nssdb" -n "LocumView spike test CA" 2>/dev/null || true
rm -rf "$H/.tpm2_pkcs11" "$H/lv-spike.csr" "$H/lv-spike.crt"
setfacl -x "u:$U" /dev/tpmrm0 2>/dev/null || true

echo "== check"
ls "$POL"; trust list --filter=ca-anchors | grep -c -i spike || true
for p in /etc/tpm2_pkcs11 "$B" "$H/.tpm2_pkcs11"; do if [ -e "$p" ] || [ -L "$p" ]; then echo "STILL THERE: $p"; fi; done
getfacl -p /dev/tpmrm0 2>/dev/null | grep "user:$U" || echo "no user ACL on /dev/tpmrm0"
echo "== done; now reboot to drop the /usr overlay: sudo systemctl reboot"
