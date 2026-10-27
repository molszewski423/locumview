#!/usr/bin/env bash
# Owner run on lv-test17 with sudo, ADR 0019 spike B3 (option B, owner decision 2026-10-27): renewal without certmonger.
# certmonger cannot use an empty token PIN (B3 test 1), and Chrome only stays silent with one (Q2). This root helper
# renews the certificate for the TPM key in the desktop user's own token, with the host's identity:
#   CSR signed by the TPM key (throwaway NSS database, empty PIN) -> ipa cert-request with the host keytab, from the
#   spike sub-CA -> the certificate's key checked against the CSR -> tpm2_ptool addcert (no PIN) -> older
#   certificates for that key deleted. Run it twice: the second run is the renewal test.
#   sudo bash b3-renew.sh [user]       (default molszewski)
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "STOP: run with sudo"; exit 1; }
[ "$(hostname -s)" = lv-test17 ] || { echo "STOP: not lv-test17"; exit 1; }
U=${1:-molszewski}; H=$(getent passwd "$U" | cut -d: -f6)
STORE=$H/.tpm2_pkcs11 TOKEN=locumview-desktop KEY=desktop
SUBCA=locumview-spike-clients PROFILE=locumviewSpikeClient
FQDN=$(hostname -f)
f() { grep -v -i -e fapi -e 'tpm2-pkcs11/blob' || true; }   # never fails when it removes every line
lockout() { tpm2_getcap properties-variable | sed -n 's/^TPM2_PT_LOCKOUT_COUNTER: /TPM lockout counter: /p'; }
der() { openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | cut -c1-16; }
# Objects in a tpm2_ptool listing: one line per object, "<db id> <class> <CKA_ID hex> <label>".
objects() {
  tpm2_ptool listobjects --path="$STORE" --label="$TOKEN" 2>/dev/null | python3 -I -c '
import re, sys
objs, cur, want = [], None, None
for l in sys.stdin:
    if l.startswith("- "): cur = {}; objs.append(cur)
    if cur is None: continue
    if want: cur["ckaid"] = l.strip(" -\x27\n"); want = None; continue
    m = re.match(r"\s*-?\s*(CKA_CLASS|CKA_LABEL|id): (.*)", l)
    if m: cur[m.group(1)] = m.group(2).strip()
    if re.match(r"\s*CKA_ID:\s*$", l): want = True
for o in objs:
    print(o.get("id", "?"), o.get("CKA_CLASS", "?"), o.get("ckaid", "-"), o.get("CKA_LABEL", ""))
' || true; }
[ -f "$STORE/tpm2_pkcs11.sqlite3" ] || { echo "STOP: no token store in $STORE"; exit 1; }
lockout
umask 077
tmp=$(mktemp -d); trap 'rm -rf "$tmp"; kdestroy -c "$tmp/cc" >/dev/null 2>&1 || true' EXIT
export TPM2_PKCS11_STORE=$STORE KRB5CCNAME=FILE:$tmp/cc

echo "== 1. the TPM key in $U's token"
kid=$(objects | awk -v k="$KEY" '$2=="CKO_PRIVATE_KEY" && $4==k {print $3; exit}')
[ -n "$kid" ] || { echo "STOP: no private key '$KEY' on token '$TOKEN'"; objects; exit 1; }
echo "key '$KEY', CKA_ID $kid"

echo "== 2. CSR signed by the TPM key (empty PIN)"
mkdir "$tmp/nss"; certutil -N -d "sql:$tmp/nss" --empty-password 2>&1 | f
printf '' > "$tmp/pin"
certutil -R -d "sql:$tmp/nss" -h "$TOKEN" -k "$kid" -s "CN=$FQDN" -f "$tmp/pin" -a -o "$tmp/req.csr" </dev/null 2>&1 | f
grep -q 'BEGIN NEW CERTIFICATE REQUEST\|BEGIN CERTIFICATE REQUEST' "$tmp/req.csr" || { echo "STOP: no CSR"; lockout; exit 1; }
sed -i 's/NEW CERTIFICATE REQUEST/CERTIFICATE REQUEST/' "$tmp/req.csr"
k_csr=$(openssl req -in "$tmp/req.csr" -noout -pubkey | der); echo "CSR key $k_csr"

echo "== 3. certificate from $SUBCA with the host identity"
kinit -k -t /etc/krb5.keytab "host/$FQDN"
ipa cert-request "$tmp/req.csr" --principal="host/$FQDN" --ca="$SUBCA" --profile-id="$PROFILE" \
  --certificate-out="$tmp/cert.pem" >/dev/null
openssl x509 -in "$tmp/cert.pem" -noout -serial -subject -issuer -enddate
k_crt=$(openssl x509 -in "$tmp/cert.pem" -noout -pubkey | der)
[ "$k_crt" = "$k_csr" ] || { echo "STOP: certificate key $k_crt is not the TPM key $k_csr"; exit 1; }
echo "certificate key $k_crt = TPM key"

echo "== 4. onto the token, older certificates for that key removed"
before=$(objects | awk -v id="$kid" '$2=="CKO_CERTIFICATE" && $3==id {print $1}')
tpm2_ptool addcert --path="$STORE" --label="$TOKEN" --key-label="$KEY" "$tmp/cert.pem" 2>&1 | f
for oid in $before; do tpm2_ptool objdel --path="$STORE" "$oid" 2>&1 | f; echo "removed older certificate object $oid"; done
chown "$U:" "$STORE"/tpm2_pkcs11.sqlite3*
objects
lockout
echo "== done; close every Chrome window before testing"
