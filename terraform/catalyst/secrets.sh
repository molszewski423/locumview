#!/usr/bin/env bash
# Create SOPS-encrypted secrets for the Catalyst contributor VMs (ADR 0003): values are generated here and piped
# straight into sops --encrypt, so no plain-text copy is written. Encrypting needs only the public key in .sops.yaml.
#   ./secrets.sh state       state.sops.yaml: the state encryption passphrase (once)
#   ./secrets.sh vm <name>   vms/<name>.sops.yaml: the local break-glass account's password
set -euo pipefail
cd "$(dirname "$0")"
# Random alphanumeric string of length $1 (no head on an endless pipe, so nothing dies of SIGPIPE under pipefail).
rnd() { local s=''; while [ "${#s}" -lt "$1" ]; do s+=$(head -c 64 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9'); done; printf '%s' "${s:0:$1}"; }
enc() { # $1 target file; YAML on stdin
  [ ! -e "$1" ] || { echo "$1 exists; delete it first to replace it"; exit 1; }
  mkdir -p "$(dirname "$1")"
  sops --encrypt --filename-override "terraform/catalyst/$1" --input-type yaml --output-type yaml /dev/stdin > "$1.tmp"
  mv "$1.tmp" "$1"; echo "wrote $1"
}
case "${1:-}" in
  state)
    printf 'state_passphrase: %s\n' "$(rnd 48)" | enc state.sops.yaml ;;
  vm)
    n=${2:?usage: secrets.sh vm <name>}
    [[ $n =~ ^[a-z][a-z0-9-]{0,62}$ ]] || { echo "bad name: $n"; exit 1; }
    printf 'lvadmin_password: %s\n' "$(rnd 24)" | enc "vms/$n.sops.yaml" ;;
  *) sed -n '2,5p' "$0"; exit 1 ;;
esac
