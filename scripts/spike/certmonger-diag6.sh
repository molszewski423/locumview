#!/usr/bin/env bash
# ADR 0019 spike, B3 diagnostic: read-only, as root on lv-test17. Why certmonger could not save the certificate it
# was issued while the token PIN was empty (NEED_TO_NOTIFY_ISSUED_SAVE_FAILED).
set -uo pipefail
export SYSTEMD_PAGER=cat PAGER=cat
[ "$(id -u)" = 0 ] || { echo "STOP: run with sudo"; exit 1; }
journalctl -u certmonger --since -40min --no-pager -o short-iso \
  | grep -v -i -e fapi -e 'tpm2-pkcs11/blob' -e 'Running enrollment' -e GSSAPI -e 'jsonrpc_url' -e 'BEGIN CERT' -e 'END CERT' \
  | grep -i -E 'save|saving|login|pin|password|error|fail|token|key|issued|NSS|SEC_ERROR|PR_' | tail -30
