#!/bin/bash
# Publish signed LocumView RPMs to the Gitea RPM registry, group el10 (changelog #62). Refuses any package that is
# not signed with the LocumView RPM signing key.
#   REGISTRY_USER=<owner> REGISTRY_TOKEN=<token> packaging/rpm/publish-rpms.sh <rpm-dir> [<registry-url>]
# Default registry: https://git.lan/api/packages/<owner>/rpm/el10. Desktops (and the image build) use
# <registry>.repo; the packages carry the LocumView signature, and Gitea signs the repository metadata with its own key.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
DIR=${1:?usage: publish-rpms.sh <rpm-dir> [<registry-url>]}
: "${REGISTRY_USER:?}" "${REGISTRY_TOKEN:?}"
URL=${2:-https://git.lan/api/packages/$REGISTRY_USER/rpm/el10}
# shellcheck source=builder.env
. packaging/rpm/builder.env
FPR=$(gpg --batch --with-colons --show-keys packaging/rpm/signing/RPM-GPG-KEY-locumview | awk -F: '/^fpr/{print $10; exit}')
# rpm is not on every operator machine (or the CI host): check the signatures in the build container.
podman run --rm --network none -v "$(realpath "$DIR"):/rpms:ro,Z" \
  -v "$PWD/packaging/rpm/signing/RPM-GPG-KEY-locumview:/pub.asc:ro,Z" \
  "quay.io/centos/centos@sha256:$CENTOS_STREAM10_DIGEST" bash -euo pipefail -c '
  rpm --import /pub.asc
  for f in /rpms/*.rpm; do
    rpm -K -v "$f" | grep -qi "Signature, key ID '"${FPR: -8}"': OK" || { echo "not signed with the LocumView key: $f"; exit 1; }
  done'
for f in "$DIR"/*.rpm; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' -u "$REGISTRY_USER:$REGISTRY_TOKEN" --upload-file "$f" "$URL/upload")
  case "$code" in
    201) echo "published $(basename "$f")" ;;
    409) echo "already published $(basename "$f")" ;;
    *) echo "upload failed ($code): $f"; exit 1 ;;
  esac
done
echo "repository: $URL.repo"
