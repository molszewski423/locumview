#!/usr/bin/env bash
# Owner run (operator-laptop), after register-gateway.sh: load the scenario library and the Synthea background
# patients into OpenEMR in the clinical namespace (M3 step 2b). Idempotent: cases already present are skipped.
# SQL runs inside the MariaDB pod and API calls inside the OpenEMR pod, each with its own credentials, so no password
# or client secret reaches this machine (clinical/scenarios/targets.py). Nothing is decrypted.
#   scripts/clinical/load-scenarios.sh [case.json ...]     default: every case in clinical/scenarios/cases/
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
kubectl -n clinical wait --for=condition=Available deployment/openemr --timeout=60s >/dev/null
kubectl -n clinical wait --for=condition=Ready pod/mariadb-0 --timeout=60s >/dev/null
exec python3 -I clinical/scenarios/load.py --target cluster "$@"
