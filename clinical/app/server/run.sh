#!/usr/bin/env bash
# Run the clinical app gateway, or its tests, in the pinned Python 3.13 image (the same one CI uses), installing the
# hash-pinned requirements first.
#   clinical/app/server/run.sh test
#   clinical/app/server/run.sh serve <env-file> <tls-cert> <tls-key>     (local test: https on 127.0.0.1:8443)
set -euo pipefail
cd "$(dirname "$0")"
PY=docker.io/library/python@sha256:073ffebb96ae4d0ed73ccad59f08c47bd84af8a79f5258130f8458ac50ad9ff4  # pragma: allowlist secret (an image digest)
SETUP='python -m venv /tmp/v >/dev/null && /tmp/v/bin/pip install -q --disable-pip-version-check --require-hashes -r requirements.txt'
case "${1:-}" in
  test)
    exec podman run --rm -v "$PWD:/srv:ro,Z" -w /srv "$PY" sh -c "$SETUP && /tmp/v/bin/python -m unittest -v test_gateway 2>&1"
    ;;
  serve)
    env_file=${2:?env file}; cert=${3:?tls cert}; key=${4:?tls key}
    exec podman run --rm --replace --name lv-clinical-gateway --network host --env-file "$env_file" -v "$PWD:/srv:ro,Z" -v "$PWD/../dist:/dist:ro,Z" \
      -v "$(dirname "$env_file"):/run/gateway:ro,Z" -v "$cert:/tls/cert.pem:ro,Z" -v "$key:/tls/key.pem:ro,Z" -w /srv "$PY" \
      sh -c "$SETUP && /tmp/v/bin/uvicorn gateway:main --factory --host 127.0.0.1 --port 8443 --ssl-certfile /tls/cert.pem --ssl-keyfile /tls/key.pem"
    ;;
  *) sed -n '2,6p' "$0" >&2; exit 1 ;;
esac
