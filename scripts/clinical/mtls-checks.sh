#!/usr/bin/env bash
# ADR 0019 step 4 checks (changelog #163), from a machine that is NOT a LocumView desktop (operator-laptop): the two
# clinical names must refuse it at the TLS handshake. No root, no cluster credentials, no secrets: a throwaway client
# certificate from a CA made here stands in for "not a desktop". The positive check (a desktop's Chrome opens the
# EHR with no Keycloak prompt) is done in a desktop.
#   scripts/clinical/mtls-checks.sh
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
IDMCA=k8s/locumview/keycloak/idm-ca.pem
umask 077
tmp=$(mktemp -d -p "${XDG_RUNTIME_DIR:-/dev/shm}")
trap 'rm -rf "$tmp"' EXIT
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -subj "/CN=Not a LocumView desktop CA" \
  -keyout "$tmp/ca.key" -out "$tmp/ca.pem" 2>/dev/null
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$tmp/c.key" -subj "/CN=not-a-desktop" \
  -out "$tmp/c.csr" 2>/dev/null
openssl x509 -req -in "$tmp/c.csr" -CA "$tmp/ca.pem" -CAkey "$tmp/ca.key" -CAcreateserial -CAserial "$tmp/c.srl" \
  -days 1 -extfile <(printf 'extendedKeyUsage=clientAuth\nkeyUsage=digitalSignature\n') -out "$tmp/c.pem" 2>/dev/null
fails=0
probe() {  # probe <label> <expect: refused|HTTP code> <curl args...>
  local label=$1 want=$2; shift 2
  local code rc
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 --cacert "$IDMCA" "$@" 2>"$tmp/err"); rc=$?
  if [[ $want == refused ]]; then
    if [[ $rc -ne 0 && $code == 000 ]]; then echo "PASS $label: refused before HTTP ($(tr '\n' ' ' < "$tmp/err"))"
    else echo "FAIL $label: got HTTP $code"; fails=$((fails+1)); fi
  elif [[ $code == "$want" ]]; then echo "PASS $label: HTTP $code"
  else echo "FAIL $label: want HTTP $want, got $code (curl $rc)"; fails=$((fails+1)); fi
}
for host in emr.corp.locumview.com clinical.corp.locumview.com; do
  probe "$host, no client certificate" refused "https://$host/"
  probe "$host, certificate from another CA" refused --cert "$tmp/c.pem" --key "$tmp/c.key" "https://$host/"
  # The bypass attempt: a TLS name without the option, then Host: the clinical name. Traefik must answer 421.
  ip=$(getent hosts "$host" | awk '{print $1; exit}')
  probe "$host, other TLS name with this Host" 421 -k --resolve "not-clinical.corp.locumview.com:443:$ip" \
    -H "Host: $host" "https://not-clinical.corp.locumview.com/"
done
echo "$fails failure(s)"; exit $((fails > 0))
