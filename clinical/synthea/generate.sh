#!/usr/bin/env bash
# Phase 9 lite M2: generate the background patients with Synthea, reproducibly, and convert them to
# clinical/synthea/background.json (the committed file the loader reads; loading never needs Java).
#   clinical/synthea/generate.sh
# Synthea v4.0.0 (tagged release) is downloaded once to ~/.cache/locumview-synthea and checked against the SHA-256
# GitHub publishes for the release asset; it runs in a digest-pinned JRE container without network. A fixed seed,
# clinician seed, reference date and population make the output repeatable.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
VERSION=v4.0.0
SHA256=ed43c20ad40ba5c3bc724503a5af032715fe3c491620b766148e7c2361e6ecc1  # pragma: allowlist secret (a file digest)
JRE=docker.io/library/eclipse-temurin@sha256:227118764cccd3c3294617061aaa93a08309c63a395eefa83e6b35032992ea99  # pragma: allowlist secret (an image digest)
SEED=20261025 POPULATION=20
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/locumview-synthea/$VERSION
JAR=$CACHE/synthea-with-dependencies.jar

mkdir -p "$CACHE"
if [[ ! -f "$JAR" ]]; then
  curl -fsSL -o "$JAR.part" "https://github.com/synthetichealth/synthea/releases/download/$VERSION/synthea-with-dependencies.jar"
  mv "$JAR.part" "$JAR"
fi
echo "$SHA256  $JAR" | sha256sum --check --quiet || { echo "Synthea $VERSION checksum mismatch; not running it" >&2; exit 1; }

OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
podman run --rm --network none -v "$JAR:/synthea.jar:ro,Z" -v "$OUT:/out:Z" -w /out "$JRE" \
  java -jar /synthea.jar -p "$POPULATION" -s "$SEED" -cs "$SEED" -r "$SEED" -a 25-90 \
    --exporter.fhir.export true --exporter.csv.export false \
    --exporter.hospital.fhir.export false --exporter.practitioner.fhir.export false \
    --generate.only_alive_patients true Massachusetts >/dev/null
# Synthea writes to ./output under the working directory (/out).
python3 -I clinical/synthea/convert.py "$OUT/output/fhir" clinical/synthea/background.json \
  --source "Synthea $VERSION, seed $SEED, reference date $SEED, population $POPULATION, ages 25-90, Massachusetts"
