#!/usr/bin/env bash
# Make the SSH key for the vnc-tunnel pod (changelog #170) and encrypt it (ADR 0003). Operator machine, from the
# repository root; encrypting needs only the age public key in .sops.yaml.
#   k8s/locumview/vnc-tunnel/new-key.sh
# Writes k8s/locumview/secrets/vnc-tunnel.sops.yaml (the Secret vnc-tunnel-key) and prints only the PUBLIC key, which
# goes into Catalyst's devalpine_vnc_tunnel_keys on the desktop. The private key exists in plain text only in a
# private directory on a per-user tmpfs ($XDG_RUNTIME_DIR) for the moment it takes to encrypt it, and is then removed.
# Apply: sops -d k8s/locumview/secrets/vnc-tunnel.sops.yaml | kubectl apply -f -
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=k8s/locumview/secrets/vnc-tunnel.sops.yaml
[ ! -e "$OUT" ] || { echo "$OUT exists; delete it first to replace the key"; exit 1; }
work=$(mktemp -d "${XDG_RUNTIME_DIR:?needs a per-user runtime directory}/vnc-tunnel.XXXXXX")
trap 'rm -rf "$work"' EXIT
chmod 700 "$work"
ssh-keygen -q -t ed25519 -N '' -C "locumview guacd vnc-tunnel $(date +%Y-%m-%d)" -f "$work/id_ed25519"
{
  cat <<'YAML'
apiVersion: v1
kind: Secret
metadata:
  name: vnc-tunnel-key
  namespace: locumview
  labels:
    app.kubernetes.io/part-of: locumview
  annotations:
    locumview.org/purpose: SSH key of the vnc-tunnel pod, for Catalyst's restricted vnc-tunnel account on the owner's Catalyst desktop (changelog 170).
type: Opaque
stringData:
  id_ed25519: |
YAML
  sed 's/^/    /' "$work/id_ed25519"
} | sops --encrypt --filename-override "$OUT" --input-type yaml --output-type yaml /dev/stdin > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
echo "wrote $OUT"
echo "public key (for devalpine_vnc_tunnel_keys on the desktop):"
cat "$work/id_ed25519.pub"
