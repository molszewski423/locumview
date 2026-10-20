#!/usr/bin/env bash
# Put the desktops' registry pull credentials into SOPS (registry.sops.yaml): a Gitea token with package READ
# scope only (Settings, Applications, "desktop-image-pull"), typed in, not echoed. Desktops use it to fetch signed
# image updates (bootc); it cannot push. Values go straight into sops --encrypt; nothing is printed or stored in
# plain text.   ./registry-secrets.sh [registry-user]   (default mike)
set -euo pipefail
cd "$(dirname "$0")"
[ ! -e registry.sops.yaml ] || { echo "registry.sops.yaml exists; delete it first to replace it"; exit 1; }
user=${1:-mike}
read -r -s -p "Gitea token (package: read) for $user: " token; echo
[ "${#token}" -ge 20 ] || { echo "that does not look like a Gitea token"; exit 1; }
printf 'registry_pull_user: "%s"\nregistry_pull_token: "%s"\n' "$user" "$token" |
  sops --encrypt --filename-override terraform/node1/registry.sops.yaml --input-type yaml --output-type yaml /dev/stdin > registry.sops.yaml.tmp
mv registry.sops.yaml.tmp registry.sops.yaml
unset token
python3 ../../scripts/check-sops-encrypted.py registry.sops.yaml && echo "== registry.sops.yaml written (encrypted) =="
