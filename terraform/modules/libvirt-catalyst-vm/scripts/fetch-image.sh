#!/usr/bin/env bash
# Fetch the Debian cloud image once into the operator machine's cache and check it against its pinned SHA-512, so
# the base volume is uploaded from a verified local file. Called by OpenTofu (terraform_data.image).
set -euo pipefail
: "${IMAGE_URL:?}" "${IMAGE_SHA512:?}" "${IMAGE_FILE:?}"
mkdir -p "$(dirname "$IMAGE_FILE")"
check() { [ "$(sha512sum "$1" | cut -d' ' -f1)" = "$IMAGE_SHA512" ]; }
if [ -f "$IMAGE_FILE" ] && check "$IMAGE_FILE"; then echo "base image cached and verified: $IMAGE_FILE"; exit 0; fi
tmp=$(mktemp "$IMAGE_FILE.XXXXXX"); trap 'rm -f "$tmp"' EXIT
curl --fail --location --silent --show-error --proto '=https' --output "$tmp" "$IMAGE_URL"
check "$tmp" || { echo "SHA-512 mismatch for $IMAGE_URL; nothing kept" >&2; exit 1; }
mv "$tmp" "$IMAGE_FILE"; trap - EXIT
echo "base image fetched and verified: $IMAGE_FILE"
