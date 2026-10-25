#!/usr/bin/env bash
# Owner run (operator-laptop), before kubectl apply -k k8s/clinical: verify every image pinned in
# k8s/clinical/kustomization.yaml against the project's public key, the same checks clinical-images.yml runs after a
# build: the signature and the SPDX SBOM attestation. Exits non-zero if any image fails or none is found. Needs cosign
# and read access to the registry; uses only the public key.
#   scripts/clinical/verify-images.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
command -v cosign >/dev/null || { echo "cosign not found; install it first" >&2; exit 1; }
KEY=image/desktop/signing/cosign.pub
mapfile -t refs < <(awk '
  /^images:/ {in_images = 1; next}
  /^[^ #]/ {in_images = 0}
  in_images && $1 == "-" && $2 == "name:" {name = $3}
  in_images && $1 == "digest:" {print name "@" $2}
' k8s/clinical/kustomization.yaml)
[[ ${#refs[@]} -gt 0 ]] || { echo "no images found in k8s/clinical/kustomization.yaml" >&2; exit 1; }
failed=0
for ref in "${refs[@]}"; do
  if cosign verify --key "$KEY" --insecure-ignore-tlog "$ref" >/dev/null 2>&1 &&
     cosign verify-attestation --key "$KEY" --insecure-ignore-tlog --type spdxjson "$ref" >/dev/null 2>&1; then
    echo "verified: $ref"
  else
    echo "FAILED:   $ref (run cosign verify --key $KEY --insecure-ignore-tlog $ref for details)" >&2
    failed=1
  fi
done
[[ $failed -eq 0 ]] && echo "all ${#refs[@]} images verified" || exit 1
