#!/usr/bin/env bash
# Owner run on lv-test17 with sudo, ADR 0019 spike step B2 (docs/plans/adr-0019-spike.md), after idm-subca.sh up:
# certmonger requests a client certificate from the IdM sub-CA for a key it cannot export, held in the TPM in a
# machine-level token, using only the host's own IdM identity (keytab); then renews it and checks the key is the same.
#   sudo bash certmonger-machine.sh        up (each step only if not done)
#   sudo bash certmonger-machine.sh down   stop tracking, remove the store, the NSS database and the drop-in
# The token's user PIN is random and root-only: certmonger treats an empty PIN file as "no PIN" (first run,
# NEED_KEYINFO_READ_PIN, no login attempted), so the empty PIN that keeps Chrome silent (Q2) does not work for it.
# Prints the TPM lockout counter before and after; stops on the first failure instead of retrying a login.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "STOP: run with sudo"; exit 1; }
[ "$(hostname -s)" = lv-test17 ] || { echo "STOP: not lv-test17"; exit 1; }
BASE=/etc/pki/locumview-spike          # cert_t: certmonger may write here
STORE=$BASE/tpm2 DB=sql:$BASE/nssdb PIN=$BASE/token.pin
TOKEN=locumview-machine KEY=machine ID=lv-spike-client
SUBCA=locumview-spike-clients PROFILE=locumviewSpikeClient
FQDN=$(hostname -f)
DROPIN=/etc/systemd/system/certmonger.service.d/90-locumview-spike.conf
export TPM2_PKCS11_STORE=$STORE TPM2_PKCS11_BACKEND=esysdb TPM2_PKCS11_TCTI=device:/dev/tpmrm0
lockout() { tpm2_getcap properties-variable | sed -n 's/^TPM2_PT_LOCKOUT_COUNTER: /TPM lockout counter: /p'; }
q() { "$@" 2> >(grep -v -i -e fapi >&2); }

if [ "${1:-}" = down ]; then
  getcert stop-tracking -i "$ID" 2>/dev/null || true
  rm -f "$DROPIN"; systemctl daemon-reload; systemctl try-restart certmonger
  rm -rf "$BASE"
  echo "== B2 undone: tracking stopped, $BASE and the drop-in removed (the certificate expires within 2 days)"
  exit 0
fi

start=$(date '+%H:%M:%S'); lockout
echo "== 1. machine token in the TPM ($STORE)"
install -d -m 0700 "$BASE" "$STORE"
[ -f "$PIN" ] || install -m 0600 /dev/null "$PIN"
if [ ! -f "$STORE/tpm2_pkcs11.sqlite3" ]; then
  q tpm2_ptool init --path="$STORE" >/dev/null
  so=$(openssl rand -hex 16); up=$(openssl rand -hex 16)
  # SO PIN kept root-only next to the store (spike only); it is needed only to reset the user PIN.
  umask 077; printf '%s\n' "$so" > "$BASE/token.sopin"
  q tpm2_ptool addtoken --path="$STORE" --pid=1 --label="$TOKEN" --sopin="$so" --userpin="$up" >/dev/null
  q tpm2_ptool changepin --path="$STORE" --label="$TOKEN" --user=user --old="$up" --new="" >/dev/null
  unset so up
fi
q tpm2_ptool listobjects --path="$STORE" --label="$TOKEN" | grep -q "CKA_LABEL: $KEY" \
  || q tpm2_ptool addkey --path="$STORE" --label="$TOKEN" --userpin="" --algorithm=ecc256 --key-label="$KEY" >/dev/null
if [ ! -s "$PIN" ]; then   # empty PIN (first run): one login with it, known to work, to set a random one
  up=$(openssl rand -hex 16)
  q tpm2_ptool changepin --path="$STORE" --label="$TOKEN" --user=user --old="" --new="$up" >/dev/null
  umask 077; printf '%s' "$up" > "$PIN"; unset up
  echo "user PIN set to a random value in $PIN (root only)"
fi
echo "key '$KEY' is in the TPM token '$TOKEN'"

echo "== 2. NSS database for certmonger ($DB)"
[ -f "$BASE/nssdb/cert9.db" ] || { install -d -m 0700 "$BASE/nssdb"; certutil -N -d "$DB" --empty-password; }
# No module registration: the new database loads p11-kit-proxy, which exposes the tpm2-pkcs11 token found through
# TPM2_PKCS11_STORE (registering the library a second time fails).
q certutil -U -d "$DB" | grep -q "token: $TOKEN\$" || { echo "STOP: NSS does not see the token $TOKEN"; exit 1; }
restorecon -R "$BASE"
q certutil -K -d "$DB" -h "$TOKEN" -f "$PIN" | grep -E "\b$KEY\$"   # one login, empty PIN (proven in part 4)

echo "== 3. certmonger sees the same store"
if [ ! -f "$DROPIN" ]; then
  install -d -m 0755 "${DROPIN%/*}"
  {
    echo '[Service]'
    echo "Environment=TPM2_PKCS11_STORE=$STORE"
    echo 'Environment=TPM2_PKCS11_BACKEND=esysdb'   # pragma: allowlist secret
    echo 'Environment=TPM2_PKCS11_TCTI=device:/dev/tpmrm0'
  } > "$DROPIN"
  systemctl daemon-reload
fi
systemctl restart certmonger

echo "== 4. request from $SUBCA with the host's own identity"
if getcert list -i "$ID" 2>/dev/null | grep -q 'NEED_KEYINFO_READ_PIN'; then
  getcert stop-tracking -i "$ID" >/dev/null; echo "stuck request from the first run removed"
fi
if ! getcert list -i "$ID" 2>/dev/null | grep -q "Request ID '$ID'"; then
  ipa-getcert request -d "$DB" -n "$KEY" -t "$TOKEN" -p "$PIN" -X "$SUBCA" -T "$PROFILE" \
    -K "host/$FQDN" -N "CN=$FQDN" -I "$ID" -w -v || true
fi
getcert list -i "$ID" | grep -E 'status:|stuck:|ca-error|issuer:|subject:|expires:|key pair storage|certificate:'
getcert list -i "$ID" | grep -q 'status: MONITORING' || { lockout; echo "STOP: not MONITORING"; exit 1; }
pub() { certutil -L -d "$DB" -n "$TOKEN:$KEY" -a -f "$PIN" 2>/dev/null | openssl x509 -noout -pubkey | sha256sum | cut -c1-16; }
ser() { certutil -L -d "$DB" -n "$TOKEN:$KEY" -a -f "$PIN" 2>/dev/null | openssl x509 -noout -serial; }
k1=$(pub); s1=$(ser)

echo "== 5. renewal keeps the key"
ipa-getcert resubmit -i "$ID" -w -v || true
getcert list -i "$ID" | grep -E 'status:|expires:'
k2=$(pub); s2=$(ser)
echo "before: $s1 key $k1"; echo "after:  $s2 key $k2"
[ "$s1" != "$s2" ] && [ "$k1" = "$k2" ] && echo "PASS: new certificate, same TPM key" || echo "FAIL: see above"

echo "== 6. the private key stays in the TPM"
echo "-- software database (expect: no keys found):"; certutil -K -d "$DB" -f "$PIN" 2>&1 | grep -v -i fapi || true
lockout
avc=$(ausearch -m avc -ts "$start" 2>/dev/null | grep denied | head -5 || true)
echo "${avc:-no SELinux denials since $start}"
