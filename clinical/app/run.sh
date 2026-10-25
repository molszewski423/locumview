#!/usr/bin/env bash
# Run the clinical app's Node tooling (npm ci, build, test, preview) in a digest-pinned Node 22 container, so the
# workstation needs no Node and CI can use the same image.
#   clinical/app/run.sh npm ci | npm run build | npm test | npm run preview
# The repository is mounted (tests read the M1 evidence); host networking only so `preview` serves on
# 127.0.0.1:5173, where the local OpenEMR redirects the browser.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
NODE=docker.io/library/node@sha256:de170b39439eb0e5a3444ad7d60b015614a381e10fecae2e30ec9e735122f38d  # pragma: allowlist secret (an image digest)
exec podman run --rm --network host --userns keep-id -v "$PWD:/repo:Z" -w /repo/clinical/app \
  -e npm_config_update_notifier=false "$NODE" "$@"
