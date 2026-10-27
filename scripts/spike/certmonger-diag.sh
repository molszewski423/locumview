#!/usr/bin/env bash
# ADR 0019 spike, B2 diagnostic: read-only, as root on lv-test17. Lists what NSS sees in the machine database.
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "STOP: run with sudo"; exit 1; }
B=/etc/pki/locumview-spike; DB=sql:$B/nssdb
export TPM2_PKCS11_STORE=$B/tpm2 TPM2_PKCS11_BACKEND=esysdb TPM2_PKCS11_TCTI=device:/dev/tpmrm0
f() { grep -v -i -e fapi -e 'tpm2-pkcs11/blob' ; }
ls -laZ $B $B/tpm2 $B/nssdb 2>&1 | grep -v '^total'
echo "== modules"; modutil -dbdir $DB -list 2>&1 | f | grep -E '^ *[0-9]+\.|library name|slot:|token:'
echo "== tokens"; certutil -U -d $DB 2>&1 | f | grep -E 'token:|uri:' | head
echo "== keys on the token"; certutil -K -d $DB -h locumview-machine -f $B/token.pin 2>&1 | f
echo "== tpm2_ptool"; tpm2_ptool listobjects --path=$B/tpm2 --label=locumview-machine 2>&1 | f | grep -E 'CKA_CLASS|CKA_LABEL'
tpm2_getcap properties-variable | grep LOCKOUT_COUNTER
