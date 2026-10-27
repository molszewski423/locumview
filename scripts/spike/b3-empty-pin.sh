#!/usr/bin/env bash
# Owner run on lv-test17 with sudo, ADR 0019 spike B3 test 1: can certmonger use the machine token with an EMPTY user
# PIN (what keeps Chrome silent, Q2)? An empty PIN file is read as "no PIN" (B2). Tries a PIN file holding only a
# newline (A), then a new request with -P "" (B). If neither renews, the random PIN goes back so B2's setup keeps
# working. The only PINs ever sent are the current one (from the file) and "" once it is set, so a failed variant
# costs at most one lockout count (limit 32); the counter is printed after each step.
set -uo pipefail
export SYSTEMD_PAGER=cat PAGER=cat
[ "$(id -u)" = 0 ] || { echo "STOP: run with sudo"; exit 1; }
[ "$(hostname -s)" = lv-test17 ] || { echo "STOP: not lv-test17"; exit 1; }
B=/etc/pki/locumview-spike STORE=/etc/pki/locumview-spike/tpm2 DB=sql:/etc/pki/locumview-spike/nssdb
PIN=$B/token.pin KEEP=$B/token.pin.random TOKEN=locumview-machine KEY=machine ID=lv-spike-client FQDN=$(hostname -f)
export TPM2_PKCS11_STORE=$STORE
f() { grep -v -i -e fapi -e 'tpm2-pkcs11/blob' ; }
lockout() { tpm2_getcap properties-variable | sed -n 's/^TPM2_PT_LOCKOUT_COUNTER: /  TPM lockout counter: /p'; }
expiry() { getcert list -i "$ID" </dev/null 2>/dev/null | sed -n 's/^\s*expires: //p'; }
settle() { for _ in $(seq 24); do getcert list -i "$ID" </dev/null 2>/dev/null | grep -q -e 'status: MONITORING' -e 'stuck: yes' -e 'ca-error' -e 'NEED_' && break; sleep 5; done
           getcert list -i "$ID" </dev/null 2>/dev/null | grep -E 'status:|stuck:|ca-error|expires:'; }
renewed() {  # renewed <expiry before>
  local now; now=$(expiry); getcert list -i "$ID" </dev/null 2>/dev/null | grep -q 'status: MONITORING' && [ "$now" != "$1" ]; }
lockout

echo "== 0. user PIN: random -> empty (one login with the PIN from the file)"
if [ -s "$PIN" ] && [ ! -f "$KEEP" ]; then
  cp -p "$PIN" "$KEEP"
  tpm2_ptool changepin --path="$STORE" --label="$TOKEN" --user=user --old="$(cat "$KEEP")" --new="" 2>&1 | f
fi
lockout

echo "== A. PIN file with only a newline, then renew"
printf '\n' > "$PIN"; chmod 0600 "$PIN"; restorecon "$PIN"
before=$(expiry); echo "  expires before: $before"
getcert resubmit -i "$ID" </dev/null 2>&1 | f; sleep 5; settle
if renewed "$before"; then echo "PASS A: certmonger renewed with an empty PIN (newline PIN file)"; lockout; exit 0; fi
lockout

echo "== B. new request with -P \"\" (no PIN file)"
getcert stop-tracking -i "$ID" </dev/null >/dev/null 2>&1
ipa-getcert request -d "$DB" -n "$KEY" -t "$TOKEN" -P "" -X locumview-spike-clients -T locumviewSpikeClient \
  -G EC -g 256 -K "host/$FQDN" -N "CN=$FQDN" -I "$ID" </dev/null 2>&1 | f
settle
if getcert list -i "$ID" </dev/null 2>/dev/null | grep -q 'status: MONITORING'; then
  b0=$(expiry); getcert resubmit -i "$ID" </dev/null 2>&1 | f; sleep 5; settle
  if renewed "$b0"; then echo "PASS B: certmonger renewed with -P \"\""; lockout; exit 0; fi
fi
lockout

echo "== neither worked: the random PIN goes back, request as in B2"
tpm2_ptool changepin --path="$STORE" --label="$TOKEN" --user=user --old="" --new="$(cat "$KEEP")" 2>&1 | f
cp -p "$KEEP" "$PIN"; rm -f "$KEEP"
getcert stop-tracking -i "$ID" </dev/null >/dev/null 2>&1
ipa-getcert request -d "$DB" -n "$KEY" -t "$TOKEN" -p "$PIN" -X locumview-spike-clients -T locumviewSpikeClient \
  -G EC -g 256 -K "host/$FQDN" -N "CN=$FQDN" -I "$ID" </dev/null 2>&1 | f
settle; lockout
echo "RESULT: certmonger cannot use an empty token PIN"
