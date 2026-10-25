#!/usr/bin/env bash
# Phase 9 lite M1 spike: start, inspect and destroy a disposable OpenEMR (k8s/clinical/openemr-spike/pod.yaml)
# with rootless podman on an operator workstation. Nothing persists between runs: `down` removes the pod, its
# emptyDir volumes and the generated Secret.
#   clinical/spike/run.sh up       start a fresh instance and wait until OpenEMR has finished installing
#   clinical/spike/run.sh api      turn on the REST and FHIR APIs and register an enabled spike API client
#   clinical/spike/run.sh sql      read SQL on stdin, run it in the instance's database (as the database root)
#   clinical/spike/run.sh status   show the pod
#   clinical/spike/run.sh down     destroy the instance
# Passwords are random per run, kept in $XDG_RUNTIME_DIR (a per-user tmpfs) and never printed.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
POD_YAML=k8s/clinical/openemr-spike/pod.yaml
STATE=${XDG_RUNTIME_DIR:?needs a per-user runtime directory}/locumview-openemr-spike
URL=https://127.0.0.1:18443

secret_yaml() {
  python3 -I - <<'PY'
import base64, secrets
values = {name: secrets.token_urlsafe(24) for name in ("root", "openemr", "admin")}
print("apiVersion: v1\nkind: Secret\nmetadata:\n  name: openemr-spike-db\ndata:")
for name, value in values.items():
    print(f"  {name}: {base64.b64encode(value.encode()).decode()}")
PY
}

case "${1:-}" in
  up)
    if podman pod exists openemr-spike; then echo "An instance is running; run '$0 down' first." >&2; exit 1; fi
    install -d -m 0700 "$STATE"
    (umask 077; secret_yaml > "$STATE/secret.yaml")
    podman kube play --quiet "$STATE/secret.yaml" >/dev/null
    podman kube play --quiet "$POD_YAML" >/dev/null
    echo "Waiting for OpenEMR's first-boot install (several minutes)..."
    for _ in $(seq 1 120); do
      if curl -ksf -o /dev/null "$URL/interface/login/login.php"; then echo "ready: $URL"; exit 0; fi
      podman pod exists openemr-spike || { echo "pod exited" >&2; exit 1; }
      sleep 10
    done
    echo "OpenEMR did not become ready in 20 minutes; see: podman logs openemr-spike-openemr" >&2
    exit 1
    ;;
  api)
    "$0" sql < clinical/spike/enable-api.sql
    python3 -I clinical/spike/fhir.py register >/dev/null
    # The spike's stand-in for an administrator approving the client (Administration > System > API Clients).
    echo "UPDATE oauth_clients SET is_enabled = 1 WHERE client_name = 'locumview-m1-spike';" | "$0" sql
    echo "API on; spike client registered and enabled"
    ;;
  sql)
    podman exec -i openemr-spike-db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot --batch openemr'
    ;;
  status)
    podman pod ps --filter name=openemr-spike
    podman ps --pod --filter pod=openemr-spike --format '{{.Names}} {{.Status}}'
    ;;
  down)
    podman kube down "$POD_YAML" >/dev/null 2>&1 || true
    podman secret rm openemr-spike-db >/dev/null 2>&1 || true
    rm -rf "$STATE"
    echo "destroyed"
    ;;
  *)
    sed -n '3,9p' "$0" >&2
    exit 1
    ;;
esac
