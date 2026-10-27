#!/usr/bin/env bash
# ADR 0019 spike, B2 diagnostic 4: read-only, as root on lv-test17. Why renewal is CA_UNREACHABLE, and whether
# certmonger made a second key on the token.
set -uo pipefail
export SYSTEMD_PAGER=cat PAGER=cat
[ "$(id -u)" = 0 ] || { echo "STOP: run with sudo"; exit 1; }
B=/etc/pki/locumview-spike
export TPM2_PKCS11_STORE=$B/tpm2
f() { grep -v -i -e fapi -e 'tpm2-pkcs11/blob' ; }
getcert list -i lv-spike-client </dev/null 2>&1 | f | grep -E 'status|ca-error|stuck|key pair storage|expires|key-generation|next-key|auto-renew'
echo "== keys on the token"
certutil -K -d "sql:$B/nssdb" -h locumview-machine -f "$B/token.pin" </dev/null 2>&1 | f
echo "== certmonger journal since 09:02"
journalctl -u certmonger --since 09:02 --no-pager -o cat | f | grep -v -e 'Running enrollment' -e GSSAPI | tail -15
tpm2_getcap properties-variable | grep LOCKOUT_COUNTER
