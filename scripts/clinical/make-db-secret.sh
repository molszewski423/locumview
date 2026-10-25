#!/usr/bin/env bash
# Owner run (operator-laptop): create k8s/clinical/secrets/clinical-db.sops.yaml, the clinical namespace's database
# and OpenEMR administrator passwords. Values are generated here and go straight into SOPS encryption; nothing is
# displayed or written in plain text. Refuses to overwrite an existing file (rotation is a separate, deliberate step).
#   scripts/clinical/make-db-secret.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
out=k8s/clinical/secrets/clinical-db.sops.yaml
[[ ! -e "$out" ]] || { echo "$out exists; not overwriting" >&2; exit 1; }
mkdir -p "$(dirname "$out")"
gen() { openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-40; }
umask 077
{
  printf 'apiVersion: v1\nkind: Secret\nmetadata: {name: clinical-db, namespace: clinical}\ntype: Opaque\nstringData:\n'
  printf '  root: "%s"\n  openemr: "%s"\n  admin: "%s"\n' "$(gen)" "$(gen)" "$(gen)"
} | sops encrypt --filename-override "$out" --input-type yaml --output-type yaml /dev/stdin > "$out.tmp"
grep -q 'ENC\[' "$out.tmp" || { echo "encryption check failed" >&2; rm -f "$out.tmp"; exit 1; }
mv "$out.tmp" "$out"
echo "wrote $out (encrypted; values never shown). Commit it, then apply: sops -d $out | kubectl apply -f -"
