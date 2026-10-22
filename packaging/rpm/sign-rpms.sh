#!/bin/bash
# Sign LocumView RPMs with the LocumView RPM signing key, then check every signature against the committed public
# key (changelog #62). The key arrives on stdin as the decrypted SOPS file, so it never touches the disk:
#   sops -d packaging/rpm/signing/rpm-signing.sops.yaml | packaging/rpm/sign-rpms.sh build/rpms
# In CI the same YAML is built from Actions secrets. Inside the container the key lives in a tmpfs GnuPG home that
# goes away with the container.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=builder.env
. packaging/rpm/builder.env
DIR=$(realpath "${1:?usage: sign-rpms.sh <rpm-dir>  (key YAML on stdin)}")
ls "$DIR"/*.rpm >/dev/null
podman run --rm -i --network=private --tmpfs /keys:mode=0700 -v "$DIR:/rpms:Z" \
  -v "$PWD/packaging/rpm/signing/RPM-GPG-KEY-locumview:/pub.asc:ro,Z" \
  "quay.io/centos/centos@sha256:$CENTOS_STREAM10_DIGEST" bash -euo pipefail -c '
  dnf -q -y install rpm-sign gnupg2 python3-pyyaml >/dev/null
  export GNUPGHOME=/keys/gnupg; install -d -m 0700 "$GNUPGHOME"
  python3 -I -c "
import sys, yaml
d = yaml.safe_load(sys.stdin)
open(\"/keys/pass\", \"w\").write(d[\"rpm_signing_passphrase\"])
open(\"/keys/key.asc\", \"w\").write(d[\"rpm_signing_private_key\"])
open(\"/keys/fpr\", \"w\").write(d[\"rpm_signing_fingerprint\"])"
  FPR=$(cat /keys/fpr)
  gpg --batch --quiet --pinentry-mode loopback --passphrase-file /keys/pass --import /keys/key.asc 2>/dev/null
  rm -f /keys/key.asc
  # The committed public key must be the key that signs.
  gpg --batch --with-colons --show-keys /pub.asc | grep -q "^fpr:::::::::$FPR:" || { echo "public key does not match"; exit 1; }
  rpmsign --addsign --define "_gpg_name $FPR" \
    --define "_gpg_sign_cmd_extra_args --pinentry-mode loopback --passphrase-file /keys/pass" /rpms/*.rpm >/dev/null
  rpm --import /pub.asc
  for f in /rpms/*.rpm; do
    out=$(rpm -K -v "$f")
    echo "$out" | grep -qi "Header V4 RSA/SHA256 Signature, key ID ${FPR: -8}: OK" || { echo "not signed: $f"; echo "$out"; exit 1; }
    echo "signed and verified: $(basename "$f")"
  done'
