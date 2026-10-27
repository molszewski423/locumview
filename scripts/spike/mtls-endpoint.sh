#!/usr/bin/env bash
# Owner run (operator-laptop), ADR 0019 spike step A5 (docs/plans/adr-0019-spike.md): the throwaway mTLS endpoint
# mtls-spike.corp.locumview.com behind Traefik, and its undo. Needs an admin ticket on idm01 (`ssh -t <idm01> kinit
# admin`), cluster-admin kubectl, INGRESS_IP in k8s/clinical/site.env, and the spike test CA's certificate (public).
#   scripts/spike/mtls-endpoint.sh up <spike-ca.pem>
#   scripts/spike/mtls-endpoint.sh down
# up: IdM A record, host and HTTP service (each only if missing); a server key and CSR in a private tmpfs directory;
# the certificate from IdM's CA, checked against the repository's IdM CA; k8s/mtls-spike applied; Secrets
# mtls-spike-tls and spike-ca created in the cluster only. Deliberately not SOPS files: nothing is committed, the
# key never touches a disk here, and `down` deletes it with the namespace.
# down: the namespace (and so both Secrets), then the IdM certificate (revoked), service, host and A record.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
DOMAIN=corp.locumview.com
NAME=mtls-spike
FQDN=$NAME.$DOMAIN
IDM=${IDM_HOST:-idm01.$DOMAIN}
IDM_CA=k8s/locumview/keycloak/idm-ca.pem

ssh "$IDM" klist -s || { echo "no Kerberos ticket on $IDM: run ssh -t $IDM kinit admin" >&2; exit 1; }
kubectl auth can-i create secrets -n kube-system >/dev/null || { echo "kubectl is not cluster-admin here" >&2; exit 1; }

case "${1:-}" in
up)
  ca=${2:?usage: $0 up <spike-ca.pem>}
  openssl x509 -in "$ca" -noout -subject | grep -q 'CN *= *LocumView spike test CA' \
    || { echo "$ca is not the spike test CA" >&2; exit 1; }
  ! openssl pkey -in "$ca" -noout 2>/dev/null || { echo "$ca contains a private key; pass the certificate only" >&2; exit 1; }
  ip=$(sed -n 's/^INGRESS_IP=//p' k8s/clinical/site.env)
  [[ $ip =~ ^[0-9]+(\.[0-9]+){3}$ ]] || { echo "set INGRESS_IP in k8s/clinical/site.env" >&2; exit 1; }
  umask 077
  tmp=$(mktemp -d -p "${XDG_RUNTIME_DIR:-/dev/shm}")
  trap 'rm -rf "$tmp"' EXIT

  # shellcheck disable=SC2029  # $NAME, $FQDN and $ip expand here on purpose
  ssh "$IDM" "set -e
              ipa dnsrecord-show $DOMAIN $NAME >/dev/null 2>&1 || ipa dnsrecord-add $DOMAIN $NAME --a-rec=$ip >/dev/null
              ipa host-show $FQDN >/dev/null 2>&1 || ipa host-add $FQDN >/dev/null
              ipa service-show HTTP/$FQDN >/dev/null 2>&1 || ipa service-add HTTP/$FQDN >/dev/null"
  echo "$FQDN: IdM host, A record and HTTP service present"

  openssl req -new -newkey rsa:3072 -nodes -keyout "$tmp/tls.key" -subj "/CN=$FQDN" \
    -addext "subjectAltName=DNS:$FQDN" -out "$tmp/req.csr" 2>/dev/null
  # shellcheck disable=SC2029
  ssh "$IDM" "t=\$(mktemp -d); trap 'rm -rf \$t' EXIT; cat > \$t/req.csr
              ipa cert-request \$t/req.csr --principal=HTTP/$FQDN --certificate-out=\$t/cert.pem >/dev/null
              cat \$t/cert.pem" < "$tmp/req.csr" > "$tmp/tls.crt"
  openssl verify -CAfile "$IDM_CA" "$tmp/tls.crt" >/dev/null || { echo "certificate does not verify" >&2; exit 1; }
  openssl x509 -in "$tmp/tls.crt" -noout -checkhost "$FQDN" | grep -q 'does match' \
    || { echo "certificate is not for $FQDN" >&2; exit 1; }

  kubectl apply -f k8s/mtls-spike/namespace.yaml
  kubectl apply --dry-run=server -k k8s/mtls-spike >/dev/null
  kubectl -n "$NAME" create secret tls mtls-spike-tls --cert="$tmp/tls.crt" --key="$tmp/tls.key" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "$NAME" create secret generic spike-ca --from-file=ca.crt="$ca" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl apply -k k8s/mtls-spike
  kubectl -n "$NAME" rollout status deploy/whoami --timeout=120s
  echo "$FQDN: up, server certificate $(openssl x509 -in "$tmp/tls.crt" -noout -enddate); key never shown"
  ;;
down)
  kubectl delete namespace "$NAME" --ignore-not-found --wait=true
  # shellcheck disable=SC2029
  ssh "$IDM" "set -e
              for s in \$(ipa cert-find --services=HTTP/$FQDN --status=VALID 2>/dev/null | sed -n 's/^ *Serial number: //p'); do
                ipa cert-revoke \$s --revocation-reason=5 >/dev/null && echo revoked \$s
              done
              ipa service-show HTTP/$FQDN >/dev/null 2>&1 && ipa service-del HTTP/$FQDN >/dev/null
              ipa host-show $FQDN >/dev/null 2>&1 && ipa host-del $FQDN >/dev/null
              ipa dnsrecord-show $DOMAIN $NAME >/dev/null 2>&1 && ipa dnsrecord-del $DOMAIN $NAME --del-all >/dev/null
              true"
  echo "$FQDN: namespace, Secrets, IdM certificate, service, host and A record removed"
  ;;
*) echo "usage: $0 up <spike-ca.pem> | down" >&2; exit 2 ;;
esac
