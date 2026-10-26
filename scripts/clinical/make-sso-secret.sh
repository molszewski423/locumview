#!/usr/bin/env bash
# Owner run (operator-laptop), M3 step 4, after configure-realm.sh has created the clinical-sso client: write
# k8s/clinical/secrets/clinical-sso.sops.yaml for oauth2-proxy (k8s/clinical/sso.yaml) with the client secret Keycloak
# issued and a new cookie secret. The client secret is read inside the Keycloak pod with the bootstrap admin already in
# its environment and goes straight into SOPS encryption with the cookie secret; neither is displayed or written in
# plain text. Neither value may end in a newline: oauth2-proxy uses the files as they are. Refuses to overwrite.
#   scripts/clinical/make-sso-secret.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
out=k8s/clinical/secrets/clinical-sso.sops.yaml
[[ ! -e "$out" ]] || { echo "$out exists; not overwriting" >&2; exit 1; }
umask 077

# shellcheck disable=SC2016  # expands inside the Keycloak pod, never here
read_client_secret='set -euo pipefail
k() { /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/kcadm-sso.config; }
k config credentials --server http://localhost:8080 --realm master \
  --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null 2>&1
id=$(k get clients -r locumview -q clientId=clinical-sso --fields id --format csv --noquotes)
[ -n "$id" ] || { echo "no clinical-sso client: run configure-realm.sh first" >&2; exit 1; }
k get "clients/$id/client-secret" -r locumview --fields value --format csv --noquotes | tr -d "\r\n"
rm -f /tmp/kcadm-sso.config'

kubectl -n locumview exec -i deploy/keycloak -- bash -c "$read_client_secret" |
  python3 -I -c '
import json, secrets, sys
client = sys.stdin.read()
if len(client) < 32 or "\n" in client:
    sys.exit("unexpected client secret from Keycloak")
print("apiVersion: v1\nkind: Secret\nmetadata: {name: clinical-sso, namespace: clinical}\ntype: Opaque\nstringData:")
print(f"  client-secret: {json.dumps(client)}\n  cookie-secret: {json.dumps(secrets.token_hex(16))}")' |
  sops encrypt --filename-override "$out" --input-type yaml --output-type yaml /dev/stdin > "$out.tmp"
grep -q 'ENC\[' "$out.tmp" || { echo "encryption check failed" >&2; rm -f "$out.tmp"; exit 1; }
mv "$out.tmp" "$out"
echo "wrote $out (encrypted; values never shown). Commit it, then apply: sops -d $out | kubectl apply -f -"
