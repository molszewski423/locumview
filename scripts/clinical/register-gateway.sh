#!/usr/bin/env bash
# Owner run (operator-laptop), after OpenEMR in the clinical namespace is ready: configure OpenEMR's API, register the
# gateway as a confidential SMART client, and write k8s/clinical/secrets/clinical-gateway.sops.yaml with the client id
# and the secret OpenEMR issues. The secret goes from OpenEMR's response straight into SOPS encryption; it is never
# displayed or written in plain text. SQL runs inside the MariaDB pod with its own root password.
#   scripts/clinical/register-gateway.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
out=k8s/clinical/secrets/clinical-gateway.sops.yaml
[[ ! -e "$out" ]] || { echo "$out exists; not overwriting" >&2; exit 1; }
EMR=https://emr.corp.locumview.com
GATEWAY=https://clinical.corp.locumview.com
NAME="LocumView Clinical"
# shellcheck disable=SC2016  # $MARIADB_ROOT_PASSWORD expands inside the pod, never here
sql() { kubectl exec -i -n clinical mariadb-0 -c mariadb -- sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot --batch openemr'; }

# OpenEMR's API on, its public address for OAuth, and the S/I/R/SDD result flags. The password grant stays off.
{
  printf "UPDATE globals SET gl_value = '1' WHERE gl_name IN ('rest_api', 'rest_fhir_api');\n"
  printf "UPDATE globals SET gl_value = '%s' WHERE gl_name = 'site_addr_oath';\n" "$EMR"
  cat clinical/spike/susceptibility-flags.sql
} | sql
echo "OpenEMR API configured for $EMR"

kubectl port-forward -n clinical svc/openemr 18081:80 >/dev/null 2>&1 &
pf=$!; trap 'kill $pf 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do curl -sf -o /dev/null http://127.0.0.1:18081/interface/login/login.php && break; sleep 1; done

scope=$(python3 -I -c 'import sys; sys.path.insert(0, "clinical/app/server"); from scopes import SCOPES; print(SCOPES)')
umask 077
python3 -I - "$NAME" "$GATEWAY" "$scope" <<'PY' | sops encrypt --filename-override "$out" --input-type yaml --output-type yaml /dev/stdin > "$out.tmp"
import json, sys, urllib.request
name, gateway, scope = sys.argv[1:4]
body = {"application_type": "private", "client_name": name, "token_endpoint_auth_method": "client_secret_post",
        "redirect_uris": [f"{gateway}/callback"], "initiate_login_uri": f"{gateway}/launch", "scope": scope}
req = urllib.request.Request("http://127.0.0.1:18081/oauth2/default/registration", data=json.dumps(body).encode(),
                             headers={"Content-Type": "application/json"})
c = json.loads(urllib.request.urlopen(req, timeout=30).read())
print("apiVersion: v1\nkind: Secret\nmetadata: {name: clinical-gateway, namespace: clinical}\ntype: Opaque\nstringData:")
print(f"  client-id: {json.dumps(c['client_id'])}\n  client-secret: {json.dumps(c['client_secret'])}")
PY
grep -q 'ENC\[' "$out.tmp" || { echo "encryption check failed" >&2; rm -f "$out.tmp"; exit 1; }
mv "$out.tmp" "$out"
# Approving the client, as an administrator would under Administration > System > API Clients.
printf "UPDATE oauth_clients SET is_enabled = 1 WHERE client_name = '%s';\nSELECT client_name, is_enabled, is_confidential FROM oauth_clients WHERE client_name = '%s';\n" "$NAME" "$NAME" | sql
echo "wrote $out (encrypted; values never shown). Commit it, then apply: sops -d $out | kubectl apply -f -"
