#!/usr/bin/env bash
# ADR 0019 spike, B2 diagnostic 2: read-only, as root on lv-test17. Why the certmonger daemon cannot see the token.
set -uo pipefail
export SYSTEMD_PAGER=cat PAGER=cat
[ "$(id -u)" = 0 ] || { echo "STOP: run with sudo"; exit 1; }
echo "== drop-in and daemon environment"
systemctl show certmonger -p Environment -p ActiveState
pid=$(systemctl show certmonger -p MainPID --value); echo "MainPID $pid"; ps -o label= -p "$pid"
tr '\0' '\n' < "/proc/$pid/environ" | grep -E '^TPM2|^HOME' || echo "(no TPM2_* in the daemon's environment)"
echo "== SELinux denials today (certmonger and helpers)"
ausearch -m avc,user_avc -ts today 2>/dev/null | grep denied | grep -E 'certmonger|comm=' | tail -12 || true
echo "== certmonger journal (last 20, FAPI noise removed)"
journalctl -u certmonger --since today --no-pager -o cat | grep -v -i -e fapi -e 'tpm2-pkcs11/blob' | tail -20
echo "== request"
getcert list -i lv-spike-client | grep -E 'status|stuck|ca-error'
