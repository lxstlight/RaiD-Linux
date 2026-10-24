#!/bin/bash
# Build RaiD Linux source packages into binary .debs.
#
# Usage: build-packages.sh OUTDIR PACKAGE...
#
# Each package directory under packages/ is copied to a scratch directory
# first, so the source tree stays clean (and builds are fast even when the
# tree lives on a Windows drive under WSL).
set -euo pipefail

TOP=$(cd "$(dirname "$0")/.." && pwd)
OUTDIR=$(realpath -m "$1")
shift

WORK=$(mktemp -d /var/tmp/raid-packages.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$OUTDIR"
rm -f "$OUTDIR"/*.deb

for package in "$@"; do
    echo "==> Building $package"
    cp -r "$TOP/packages/$package" "$WORK/$package"
    (
        cd "$WORK/$package"
        # Files checked out on Windows drives carry no usable modes.
        find . -type d -exec chmod 755 {} +
        find . -type f -exec chmod 644 {} +
        chmod 755 debian/rules
        find bin libexec scripts tools -maxdepth 1 -type f -exec chmod 755 {} + 2>/dev/null || true
        dpkg-checkbuilddeps
        dpkg-buildpackage --build=binary --no-sign
    )
done

cp "$WORK"/*.deb "$OUTDIR"/
echo "==> Packages in $OUTDIR:"
ls -1 "$OUTDIR"
