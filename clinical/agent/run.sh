#!/usr/bin/env bash
# Run the agent service, or its tests, in the pinned Python 3.13 image (the same one CI and the gateway use),
# installing the hash-pinned requirements first. The rules' own tests (test_rules.py) need no packages.
#   clinical/agent/run.sh test
#   clinical/agent/run.sh serve [port]      (local test: http on 127.0.0.1, default port 8090; SITE_TZ from the env,
#                                            and OLLAMA_URL for explanations)
set -euo pipefail
cd "$(dirname "$0")"
PY=docker.io/library/python@sha256:073ffebb96ae4d0ed73ccad59f08c47bd84af8a79f5258130f8458ac50ad9ff4  # pragma: allowlist secret (an image digest)
SETUP='python -m venv /tmp/v >/dev/null && /tmp/v/bin/pip install -q --disable-pip-version-check --require-hashes -r requirements.txt'
case "${1:-}" in
  test)
    exec podman run --rm -v "$PWD/..:/clinical:ro,Z" -w /clinical/agent "$PY" sh -c \
      "$SETUP -r requirements-test.txt && /tmp/v/bin/pip check -q && /tmp/v/bin/python -m unittest -v test_service test_explain test_rules 2>&1"
    ;;
  serve)
    port=${2:-8090}
    exec podman run --rm --replace --name lv-clinical-agent --network host -e "SITE_TZ=${SITE_TZ:?set SITE_TZ}" \
      -e "OLLAMA_URL=${OLLAMA_URL:-}" \
      -v "$PWD/..:/clinical:ro,Z" -w /clinical/agent "$PY" \
      sh -c "$SETUP && /tmp/v/bin/uvicorn service:main --factory --host 127.0.0.1 --port $port --no-server-header"
    ;;
  *) sed -n '2,7p' "$0" >&2; exit 1 ;;
esac
