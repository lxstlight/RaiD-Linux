#!/bin/bash
# Build the RaiD Linux live ISO with live-build. Must run as root.
#
# Usage: build-iso.sh DEBDIR OUTDIR
#
# live-build works in $BUILD_DIR (default /var/tmp/raid-linux-build), which
# must be on a Linux file system. Downloaded packages are cached there, so
# later builds are much faster.
set -euo pipefail

TOP=$(cd "$(dirname "$0")/.." && pwd)
DEBDIR=$(realpath "$1")
OUTDIR=$(realpath -m "$2")
BUILD_DIR=${BUILD_DIR:-/var/tmp/raid-linux-build}
VERSION=$(cat "$TOP/VERSION")
ISO_NAME="raid-linux-$VERSION-amd64.iso"

if [ "$(id -u)" -ne 0 ]; then
    echo "build-iso.sh: live-build needs root; run it with sudo" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR" "$OUTDIR"
cd "$BUILD_DIR"

# Start from a clean tree but keep the package cache.
if [ -d config ]; then
    lb clean
fi
rsync -a --delete "$TOP/live-build/auto/" auto/
rsync -a --delete "$TOP/live-build/config/" config/

# Files checked out on Windows drives carry no usable modes; the includes
# would otherwise make /usr and /usr/lib world-writable in the image.
find auto config -type d -exec chmod 755 {} +
find auto config -type f -exec chmod 644 {} +
chmod 755 auto/* config/hooks/normal/*.hook.* \
    config/includes.chroot_after_packages/usr/lib/live/config/*

# Our packages are installed from a local repository built from these.
mkdir -p config/packages.chroot
cp "$DEBDIR"/*.deb config/packages.chroot/

# The installer removes exactly this list when another desktop is chosen.
cp "$TOP/packages/calamares-settings-raid/desktops/kde.list" \
   config/package-lists/kde.list.chroot

lb config
lb build

iso=$(find . -maxdepth 1 -name '*.iso' -printf '%T@ %p\n' | sort -rn | head -n1 | cut -d' ' -f2-)
if [ -z "$iso" ]; then
    echo "build-iso.sh: live-build did not produce an ISO, see $BUILD_DIR/build.log" >&2
    exit 1
fi

# Checksum the image on the Linux file system: reading it back from a
# Windows drive under WSL is slow and can run out of memory.
echo "$(sha256sum "$iso" | cut -d' ' -f1)  $ISO_NAME" > "$OUTDIR/$ISO_NAME.sha256"
cp "$iso" "$OUTDIR/$ISO_NAME"
echo "==> $OUTDIR/$ISO_NAME"
