#!/usr/bin/env bash
# Phase 9 lite M3: the clinical app's end-to-end test, with one command, on a fresh local OpenEMR.
#   clinical/app/e2e.sh [<patient number>] [--keep]     default patient LV-bsi-enterobacter-ampc-01
# 1. fresh OpenEMR with the scenario library (clinical/scenarios/load.py --reset; run.sh applies the OpenEMR patches)
# 2. the app built (npm ci, build) and the gateway registered as a confidential SMART client (e2e/setup.py)
# 3. the gateway on https://127.0.0.1:8443 with a throwaway certificate
# 4. Playwright's Chromium: a clinician launches the app from the patient's chart; it must open on that patient
# Screenshots go to $E2E_OUT (default: a new temporary directory). Everything is torn down unless --keep.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
PATIENT=LV-bsi-enterobacter-ampc-01 KEEP=
for arg in "$@"; do [[ "$arg" == --keep ]] && KEEP=1 || PATIENT=$arg; done
STATE=${XDG_RUNTIME_DIR:?}/locumview-openemr-spike
OUT=${E2E_OUT:-$(mktemp -d)}
PLAYWRIGHT=mcr.microsoft.com/playwright@sha256:bc72a8df40831ded821e3cbc79c318c21b44d6e51dff9fd89ace7a8249c5b462  # pragma: allowlist secret (an image digest)

# shellcheck disable=SC2317  # run by the EXIT trap
cleanup() {
  podman stop -t 2 lv-clinical-gateway >/dev/null 2>&1 || true
  [[ -n "$KEEP" ]] || clinical/spike/run.sh down >/dev/null
}
trap cleanup EXIT

python3 -I clinical/scenarios/load.py --reset | grep -E '^(patched|background|ready|API)' || true
clinical/app/run.sh npm ci --no-audit --no-fund >/dev/null
clinical/app/run.sh npm run build >/dev/null
python3 -I clinical/app/e2e/setup.py "$PATIENT"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -subj /CN=127.0.0.1 \
  -addext subjectAltName=IP:127.0.0.1 -keyout "$STATE/gw-key.pem" -out "$STATE/gw-cert.pem" 2>/dev/null
chmod 600 "$STATE/gw-key.pem"
clinical/app/server/run.sh serve "$STATE/gateway.env" "$STATE/gw-cert.pem" "$STATE/gw-key.pem" >"$OUT/gateway.log" 2>&1 &
for _ in $(seq 1 60); do curl -ksf -o /dev/null https://127.0.0.1:8443/index.html && break; sleep 2; done

status=0
podman run --rm --network host --userns keep-id --env-file "$STATE/e2e.env" \
  -v "$PWD/clinical/app/e2e:/e2e:ro,Z" -v "$OUT:/out:Z" "$PLAYWRIGHT" \
  sh -c 'cd /tmp && npm i -s --no-audit --no-fund playwright-core@1.64.0 >/dev/null 2>&1 && cp /e2e/launch.mjs . && node launch.mjs' \
  >"$OUT/result.json" 2>"$OUT/test.log" || status=$?
grep '^{' "$OUT/result.json" | python3 -I -c 'import json, sys
d = json.loads(sys.stdin.read() or "{}")
print("app:", d.get("context")); print("cultures:", d.get("organisms")); print("granted:", (d.get("granted") or {}).get("scope"))
print("error:", d.get("error"))' || true
echo "$( [[ $status == 0 ]] && echo PASS || echo FAIL ) (screenshots and logs: $OUT)"
exit "$status"
