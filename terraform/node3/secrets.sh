#!/usr/bin/env bash
# Create SOPS-encrypted secrets for node3 (ADR 0003): values are generated here and piped straight into
# sops --encrypt, so no plain-text copy is written. Encrypting needs only the public key in .sops.yaml.
#   ./secrets.sh state            state.sops.yaml: the state encryption passphrase (once)
#   ./secrets.sh desktop <name>   desktops/<name>.sops.yaml: break-glass, GRUB, LUKS recovery, RDP credentials
#   ./secrets.sh desktop <name> --demo   ... plus the demo user's RDP credentials
set -euo pipefail
cd "$(dirname "$0")"
# Random alphanumeric string of length $1 (no head on an endless pipe, so nothing dies of SIGPIPE under pipefail).
rnd() { local s=''; while [ "${#s}" -lt "$1" ]; do s+=$(head -c 64 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9'); done; printf '%s' "${s:0:$1}"; }
enc() { # $1 target file; YAML on stdin
  [ ! -e "$1" ] || { echo "$1 exists; delete it first to replace it"; exit 1; }
  sops --encrypt --filename-override "terraform/node3/$1" --input-type yaml --output-type yaml /dev/stdin > "$1.tmp"
  mv "$1.tmp" "$1"; echo "wrote $1"
}
case "${1:-}" in
  state)
    printf 'state_passphrase: %s\n' "$(rnd 48)" | enc state.sops.yaml ;;
  desktop)
    n=${2:?usage: secrets.sh desktop <name> [--demo]}
    [[ $n =~ ^[a-z][a-z0-9-]{0,62}$ ]] || { echo "bad name: $n"; exit 1; }
    {
      printf 'lvadmin_password: %s\n' "$(rnd 24)"
      printf 'grub_password: %s\n' "$(rnd 24)"
      printf 'luks_recovery_passphrase: %s\n' "$(rnd 40)"
      printf 'rdp_user: rdp-%s\n' "$(rnd 8 | tr '[:upper:]' '[:lower:]')"
      printf 'rdp_password: %s\n' "$(rnd 32)"
      if [ "${3:-}" = --demo ]; then
        printf 'demo_rdp_user: demo-%s\n' "$(rnd 8 | tr '[:upper:]' '[:lower:]')"
        printf 'demo_rdp_password: %s\n' "$(rnd 32)"
      fi
    } | enc "desktops/$n.sops.yaml" ;;
  *) sed -n '2,7p' "$0"; exit 1 ;;
esac
