#!/usr/bin/env bash
# ADR 0019 spike, B2 diagnostic 3: as root on lv-test17. certmonger's key helper loads tpm2-pkcs11 but finds no token,
# with no logged denial. This turns off SELinux dontaudit rules for the run (semodule -DB; restored with semodule -B
# on exit, whatever happens), repeats the request once and prints what certmonger was denied.
set -uo pipefail
export SYSTEMD_PAGER=cat PAGER=cat
[ "$(id -u)" = 0 ] || { echo "STOP: run with sudo"; exit 1; }
[ "$(hostname -s)" = lv-test17 ] || { echo "STOP: not lv-test17"; exit 1; }
B=/etc/pki/locumview-spike ID=lv-spike-client
start=$(date '+%H:%M:%S')
echo "== dontaudit off (takes a few seconds)"; semodule -DB
trap 'echo "== dontaudit back on"; semodule -B' EXIT
getcert stop-tracking -i "$ID" >/dev/null 2>&1
ipa-getcert request -d "sql:$B/nssdb" -n machine -t locumview-machine -p "$B/token.pin" \
  -X locumview-spike-clients -T locumviewSpikeClient -K "host/$(hostname -f)" -N "CN=$(hostname -f)" -I "$ID" -w \
  2>&1 | grep -v -i -e fapi -e 'tpm2-pkcs11/blob'
sleep 3
getcert list -i "$ID" 2>/dev/null | grep -E 'status:|stuck:|ca-error'
echo "== denials for certmonger since $start"
ausearch -m avc,user_avc -ts "$start" 2>/dev/null | grep denied | grep -E 'certmonger' \
  | sed -E 's/^.*avc: +//; s/ pid=[0-9]+//; s/ ino=[0-9]+//' | sort | uniq -c | head -20
journalctl -u certmonger --since "$start" --no-pager -o cat | grep -E 'Token is named|Error|key' | tail -6
