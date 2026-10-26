#!/usr/bin/env bash
# Owner run (operator-laptop), M3 step 3: IdM names and TLS certificates for emr. and clinical.corp.locumview.com.
# Needs an admin ticket on idm01 (`ssh -t <idm01> kinit admin`) and INGRESS_IP in k8s/clinical/site.env (node2's LAN
# address, where Traefik listens). For each name: an IdM host entry with its A record (no PTR) and an HTTP/ service,
# each only if missing; a key and CSR made here; the certificate from IdM's CA (caIPAserviceCert), checked against the
# repository's IdM CA; and k8s/clinical/secrets/clinical-tls-<name>.sops.yaml (kubernetes.io/tls). The private key
# exists only in a private tmpfs directory until SOPS encrypts it and is never displayed. Refuses to overwrite.
#   scripts/clinical/make-tls-secrets.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
DOMAIN=corp.locumview.com
IDM=${IDM_HOST:-idm01.$DOMAIN}
CA=k8s/locumview/keycloak/idm-ca.pem
ip=$(sed -n 's/^INGRESS_IP=//p' k8s/clinical/site.env)
[[ $ip =~ ^[0-9]+(\.[0-9]+){3}$ ]] || { echo "set INGRESS_IP in k8s/clinical/site.env" >&2; exit 1; }
ssh "$IDM" klist -s || { echo "no Kerberos ticket on $IDM: run ssh -t $IDM kinit admin" >&2; exit 1; }
umask 077
tmp=$(mktemp -d -p "${XDG_RUNTIME_DIR:-/dev/shm}")
trap 'rm -rf "$tmp"' EXIT

for name in emr clinical; do
  fqdn=$name.$DOMAIN
  out=k8s/clinical/secrets/clinical-tls-$name.sops.yaml
  [[ ! -e "$out" ]] || { echo "$out exists; skipping $fqdn"; continue; }

  # shellcheck disable=SC2029  # $fqdn and $ip expand here on purpose
  ssh "$IDM" "ipa host-show $fqdn >/dev/null 2>&1 || ipa host-add $fqdn --ip-address=$ip --no-reverse >/dev/null
              ipa service-show HTTP/$fqdn >/dev/null 2>&1 || ipa service-add HTTP/$fqdn >/dev/null"
  echo "$fqdn: IdM host, A record and HTTP service present"

  openssl req -new -newkey rsa:3072 -nodes -keyout "$tmp/$name.key" -subj "/CN=$fqdn" \
    -addext "subjectAltName=DNS:$fqdn" -out "$tmp/$name.csr" 2>/dev/null
  # The CSR and the certificate are public; only they cross to idm01 and back.
  # shellcheck disable=SC2029
  ssh "$IDM" "t=\$(mktemp -d); trap 'rm -rf \$t' EXIT; cat > \$t/req.csr
              ipa cert-request \$t/req.csr --principal=HTTP/$fqdn --certificate-out=\$t/cert.pem >/dev/null
              cat \$t/cert.pem" < "$tmp/$name.csr" > "$tmp/$name.crt"

  openssl verify -CAfile "$CA" "$tmp/$name.crt" >/dev/null || { echo "$fqdn: certificate does not verify" >&2; exit 1; }
  openssl x509 -in "$tmp/$name.crt" -noout -checkhost "$fqdn" | grep -q 'does match' \
    || { echo "$fqdn: certificate is not for $fqdn" >&2; exit 1; }
  [[ "$(openssl x509 -in "$tmp/$name.crt" -noout -pubkey)" == "$(openssl pkey -in "$tmp/$name.key" -pubout)" ]] \
    || { echo "$fqdn: certificate does not match the key" >&2; exit 1; }

  python3 -I - "$name" "$tmp/$name.crt" "$tmp/$name.key" <<'PY' \
    | sops encrypt --filename-override "$out" --input-type yaml --output-type yaml /dev/stdin > "$out.tmp"
import json, sys
name, crt, key = sys.argv[1:4]
print(f"apiVersion: v1\nkind: Secret\nmetadata: {{name: clinical-tls-{name}, namespace: clinical}}\n"
      "type: kubernetes.io/tls\nstringData:")
for k, path in (("tls.crt", crt), ("tls.key", key)):
    print(f"  {k}: {json.dumps(open(path, encoding='ascii').read())}")
PY
  grep -q 'ENC\[' "$out.tmp" || { echo "encryption check failed" >&2; rm -f "$out.tmp"; exit 1; }
  mv "$out.tmp" "$out"
  echo "$fqdn: $(openssl x509 -in "$tmp/$name.crt" -noout -enddate); wrote $out (encrypted; key never shown)"
done
echo "Commit the files, then apply each: sops -d <file> | kubectl apply -f -"
