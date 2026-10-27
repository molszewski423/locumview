#!/usr/bin/env bash
# ADR 0019 spike, B2 diagnostic 5: read-only, as root on lv-test17. Every certificate object on the machine token,
# with serial, expiry and public-key fingerprint, next to the one private key.
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "STOP: run with sudo"; exit 1; }
B=/etc/pki/locumview-spike
export TPM2_PKCS11_STORE=$B/tpm2 GNUTLS_PIN
GNUTLS_PIN=$(cat "$B/token.pin")
M=/usr/lib64/pkcs11/libtpm2_pkcs11.so
f() { grep -v -i -e fapi -e 'tpm2-pkcs11/blob' ; }
echo "== certificates on the token"
p11tool --provider $M --login --list-all-certs "pkcs11:token=locumview-machine" </dev/null 2>/dev/null \
  | sed -n 's/^\s*URL:\s*//p' | while read -r url; do
    echo "- $url" | sed 's/;serial=[^;]*//; s/;manufacturer=[^;]*//; s/;model=[^;]*//'
    pem=$(p11tool --provider $M --login --export "$url" </dev/null 2>/dev/null)
    printf '%s\n' "$pem" | openssl x509 -noout -serial -enddate | sed 's/^/  /'
    printf '%s\n' "$pem" | openssl x509 -noout -pubkey | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | cut -c1-16 | sed 's/^/  key /'
  done
echo "== the private key"
p11tool --provider $M --login --list-all-privkeys "pkcs11:token=locumview-machine" </dev/null 2>/dev/null | grep -E 'Object|Label|ID:|Flags'
p11tool --provider $M --login --export-pubkey "pkcs11:token=locumview-machine;object=machine;type=private" </dev/null 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | cut -c1-16 | sed 's/^/  key /'
tpm2_getcap properties-variable | grep LOCKOUT_COUNTER
