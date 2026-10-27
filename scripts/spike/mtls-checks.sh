#!/usr/bin/env bash
# ADR 0019 spike, A7 checks for Q3 (docs/plans/adr-0019-spike.md), run from the machine that holds the spike test CA.
# No root, no cluster credentials. Makes two throwaway client certificates in a private tmpfs directory (one from the
# spike CA, one from a second CA made here) and probes Traefik. Each check prints PASS or FAIL.
#   scripts/spike/mtls-checks.sh <dir with the spike CA's ca.pem and ca.key> <IdM CA certificate>
set -uo pipefail
cadir=${1:?usage: $0 <spike-ca-dir> <idm-ca.pem>}; idmca=${2:?usage: $0 <spike-ca-dir> <idm-ca.pem>}
SPIKE=https://mtls-spike.corp.locumview.com
EMR=emr.corp.locumview.com
umask 077
tmp=$(mktemp -d -p "${XDG_RUNTIME_DIR:-/dev/shm}")
trap 'rm -rf "$tmp"' EXIT

client() {  # client <name> <ca.pem> <ca.key>
  openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$tmp/$1.key" \
    -subj "/O=LocumView spike/CN=$1" -out "$tmp/$1.csr" 2>/dev/null
  openssl x509 -req -in "$tmp/$1.csr" -CA "$2" -CAkey "$3" -CAcreateserial -CAserial "$tmp/$1.srl" -days 1 \
    -extfile <(printf 'extendedKeyUsage=clientAuth\nkeyUsage=digitalSignature\n') -out "$tmp/$1.pem" 2>/dev/null
}
client checks-good "$cadir/ca.pem" "$cadir/ca.key"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -subj "/CN=Not the spike CA" \
  -keyout "$tmp/other-ca.key" -out "$tmp/other-ca.pem" 2>/dev/null
client checks-wrong-ca "$tmp/other-ca.pem" "$tmp/other-ca.key"

fails=0
probe() {  # probe <label> <expect: handshake-refused|HTTP code> <curl args...>
  local label=$1 want=$2; shift 2
  local code err rc
  code=$(curl -sS -o "$tmp/body" -w '%{http_code}' --max-time 10 --cacert "$idmca" "$@" 2>"$tmp/err"); rc=$?
  err=$(tr '\n' ' ' < "$tmp/err")
  if [[ $want == handshake-refused ]]; then
    if [[ $rc -ne 0 && $code == 000 ]]; then echo "PASS $label: refused before HTTP (curl $rc: $err)"
    else echo "FAIL $label: got HTTP $code (curl $rc)"; fails=$((fails+1)); fi
  elif [[ $code == "$want" ]]; then echo "PASS $label: HTTP $code"
  else echo "FAIL $label: want HTTP $want, got $code (curl $rc: $err)"; fails=$((fails+1)); fi
}

probe "no client certificate" handshake-refused "$SPIKE/"
probe "certificate from another CA" handshake-refused --cert "$tmp/checks-wrong-ca.pem" --key "$tmp/checks-wrong-ca.key" "$SPIKE/"
probe "certificate from the spike CA" 200 --cert "$tmp/checks-good.pem" --key "$tmp/checks-good.key" "$SPIKE/"
grep -i 'X-Forwarded-Tls-Client-Cert-Info' "$tmp/body" | sed 's/^/     /'
probe "SNI mtls-spike, Host emr. (spike CA certificate)" 421 \
  --cert "$tmp/checks-good.pem" --key "$tmp/checks-good.key" -H "Host: $EMR" "$SPIKE/"
probe "SNI emr., Host mtls-spike, no certificate (bypass attempt)" 421 -H "Host: ${SPIKE#https://}" "https://$EMR/"
probe "emr. unchanged: still sends to Keycloak" 302 "https://$EMR/"
echo "== $fails check(s) failed"
exit $((fails > 0))
