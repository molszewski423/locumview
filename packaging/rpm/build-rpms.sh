#!/bin/bash
# Build LocumView's desktop RPMs (locumview-desktop.spec) from a commit, in a clean CentOS Stream 10 container
# (changelog #62). Rootless podman; the same on an operator machine and in CI.
#   packaging/rpm/build-rpms.sh [<output-dir>] [<commit>]     default: ./build/rpms and HEAD
# The release is 1.<commit time>git<short commit>, so every commit gives a newer, traceable package. Signing and
# publishing are separate steps (sign-rpms.sh, publish-rpms.sh).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=builder.env
. packaging/rpm/builder.env
OUT=$(realpath -m "${1:-build/rpms}"); REV=${2:-HEAD}
# Pinned by digest: a build reproduces with the same buildroot base until the pin is moved on purpose.
BUILDER=quay.io/centos/centos@sha256:${CENTOS_STREAM10_DIGEST:?set by packaging/rpm/builder.env}
VERSION=$(git show "$REV:packaging/rpm/locumview-desktop.spec" | sed -n "s/^Version: *//p")
SHORT=$(git rev-parse --short=10 "$REV")
# The commit time (UTC, to the second) orders builds; the hash alone would order same-day builds by chance.
RELEASE="1.$(TZ=UTC git log -1 --format=%cd --date=format-local:%Y%m%d%H%M%S "$REV")git$SHORT"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
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
