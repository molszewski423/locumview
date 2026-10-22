#!/bin/bash
# Build LocumView's desktop RPMs (locumview-desktop.spec) from a commit, in a clean CentOS Stream 10 container
# (changelog #62). Rootless podman; the same on an operator machine and in CI.
#   packaging/rpm/build-rpms.sh [<output-dir>] [<commit>]     default: ./build/rpms and HEAD
# The release is 1.<input commit time>git<short input commit>, shared with the image build. Signing and
# publishing are separate steps (sign-rpms.sh, publish-rpms.sh).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=$(realpath -m "${1:-build/rpms}"); REV=${2:-HEAD}
read -r REV VERSION RELEASE EVR < <(python3 packaging/rpm/resolve-version.py "$REV" --format tsv)
echo "RPM source: $REV; version-release: $EVR"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
git show "$REV:packaging/rpm/builder.env" > "$WORK/builder.env"
# Read the buildroot pin from the selected source too, including when explicitly building an older revision.
# shellcheck source=builder.env
. "$WORK/builder.env"
# Pinned by digest: a build reproduces with the same buildroot base until the pin is moved on purpose.
BUILDER=quay.io/centos/centos@sha256:${CENTOS_STREAM10_DIGEST:?set by packaging/rpm/builder.env}
SHORT=${REV:0:10}
mkdir -p "$WORK/SOURCES" "$WORK/SPECS" "$OUT"
git archive --format=tar.gz --prefix="locumview-$VERSION/" -o "$WORK/SOURCES/locumview-$VERSION.tar.gz" "$REV" \
  LICENSE packaging/extensions packaging/branding packaging/tour image/desktop/files
git show "$REV:packaging/rpm/locumview-desktop.spec" > "$WORK/SPECS/locumview-desktop.spec"
podman run --rm --network=private -v "$WORK:/rpmbuild:Z" -v "$OUT:/out:Z" "$BUILDER" bash -euo pipefail -c '
  dnf -q -y install rpm-build dnf-plugins-core >/dev/null
  dnf -q -y builddep /rpmbuild/SPECS/locumview-desktop.spec >/dev/null
  rpmbuild -ba --define "_topdir /rpmbuild" --define "lv_release '"$RELEASE"'" /rpmbuild/SPECS/locumview-desktop.spec 2>&1 \
    | grep -E "^(Wrote|error|RPM build errors|[[:space:]]+/)" || true
  cp /rpmbuild/RPMS/noarch/*.rpm /rpmbuild/SRPMS/*.src.rpm /out/'
ls -1 "$OUT" | grep -F "$SHORT"
