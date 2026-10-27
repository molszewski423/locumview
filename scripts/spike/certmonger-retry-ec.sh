#!/usr/bin/env bash
# Owner run on lv-test17 with sudo, ADR 0019 spike B2 retry. The first request did not name a key type, so certmonger
# kept its default (RSA 2048) and at renewal made an RSA candidate key in the TPM, which the EC-only profile refused.
# This stops that request, deletes the candidate (only objects labelled "machine (candidate ...)"), requests again
# with -G EC -g 256 so certmonger matches the existing TPM key, then renews and compares serial and key.
set -euo pipefail
export SYSTEMD_PAGER=cat PAGER=cat
[ "$(id -u)" = 0 ] || { echo "STOP: run with sudo"; exit 1; }
[ "$(hostname -s)" = lv-test17 ] || { echo "STOP: not lv-test17"; exit 1; }
B=/etc/pki/locumview-spike STORE=/etc/pki/locumview-spike/tpm2 DB=sql:/etc/pki/locumview-spike/nssdb
PIN=$B/token.pin TOKEN=locumview-machine KEY=machine ID=lv-spike-client FQDN=$(hostname -f)
export TPM2_PKCS11_STORE=$STORE
f() { grep -v -i -e fapi -e 'tpm2-pkcs11/blob' ; }
lockout() { tpm2_getcap properties-variable | sed -n 's/^TPM2_PT_LOCKOUT_COUNTER: /TPM lockout counter: /p'; }
status() { getcert list -i "$ID" </dev/null 2>/dev/null | grep -E 'status:|ca-error|expires:'; }
settle() { for _ in $(seq 24); do getcert list -i "$ID" </dev/null 2>/dev/null | grep -q -e 'status: MONITORING' -e 'stuck: yes' -e 'ca-error' && break; sleep 5; done; }
crt() { GNUTLS_PIN=$(cat "$PIN") p11tool --provider /usr/lib64/pkcs11/libtpm2_pkcs11.so --login \
          --export "pkcs11:token=$TOKEN;object=$KEY;type=cert" </dev/null 2>/dev/null; }
pub() { crt | openssl x509 -noout -pubkey | sha256sum | cut -c1-16; }
ser() { crt | openssl x509 -noout -serial; }
lockout

echo "== 1. stop the old request, delete the RSA candidate"
getcert stop-tracking -i "$ID" </dev/null >/dev/null 2>&1 || true
# tpm2_ptool can exit non-zero over its FAPI warnings; its listing is still complete.
objs=$(tpm2_ptool listobjects --path="$STORE" --label="$TOKEN" 2>/dev/null || true)
[ -n "$objs" ] || { echo "STOP: no object listing from tpm2_ptool"; exit 1; }
cands=$(printf '%s\n' "$objs" | python3 -I -c '
import sys, re
objs, cur = [], {}
for l in sys.stdin:
    if l.startswith("- "): cur = {}; objs.append(cur)
    m = re.match(r"\s*-?\s*(CKA_LABEL|id): (.*)", l)
    if m: cur[m.group(1)] = m.group(2).strip()
for o in objs:
    if o.get("CKA_LABEL", "").startswith("machine (candidate"): print(o["id"])
') || { echo "STOP: could not parse the object listing"; exit 1; }
echo "candidate objects: ${cands:-none}"
for oid in $cands; do tpm2_ptool objdel --path="$STORE" "$oid" 2>&1 | f || true; echo "deleted candidate object $oid"; done
certutil -K -d "$DB" -h "$TOKEN" -f "$PIN" </dev/null 2>&1 | f || true

echo "== 2. request again, key type EC P-256 (the existing TPM key)"
ipa-getcert request -d "$DB" -n "$KEY" -t "$TOKEN" -p "$PIN" -X locumview-spike-clients -T locumviewSpikeClient \
  -G EC -g 256 -K "host/$FQDN" -N "CN=$FQDN" -I "$ID" </dev/null 2>&1 | f || true
settle; status
k1=$(pub); s1=$(ser); echo "issued: $s1 key $k1"

echo "== 3. renew"
getcert resubmit -i "$ID" </dev/null 2>&1 | f || true
sleep 5; settle; status
k2=$(pub); s2=$(ser); echo "renewed: $s2 key $k2"
if [ "$s1" != "$s2" ] && [ "$k1" = "$k2" ]; then echo "PASS: new certificate, same TPM key"
elif [ "$s1" != "$s2" ]; then echo "RENEWED WITH A NEW KEY (rotation): see the token's keys below"
else echo "NOT RENEWED: see ca-error above"; fi
certutil -K -d "$DB" -h "$TOKEN" -f "$PIN" </dev/null 2>&1 | f || true
lockout
