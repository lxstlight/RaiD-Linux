#!/bin/bash
# Build the offline update of an installed RaiD Linux 1.0 to the current
# version: a folder to copy to a USB stick, with the RaiD packages, every
# Debian package they need that 1.0 did not have, and install-update.sh.
#
# Usage: make-update.sh DEBDIR OUTDIR
#
# The Debian packages to include are found by letting apt resolve the
# package lists of 1.0 and of this version on an empty system and taking
# the difference, so the update works without an internet connection.
set -euo pipefail

TOP=$(cd "$(dirname "$0")/.." && pwd)
DEBDIR=$(realpath "$1")
VERSION=$(cat "$TOP/VERSION")
OUT=$(realpath -m "$2")/RaiD-Linux-$VERSION-update
LISTS="$TOP/live-build/config/package-lists"
KDE_LIST="$TOP/packages/calamares-settings-raid/desktops/kde.list"

# Packages the image gained since 1.0, and the ones it lost.
ADDED="raid-store appstream packagekit neowofetch hyfetch fonts-inter appmenu-gtk3-module
       plasma-widgets-addons systemd-zram-generator earlyoom qt6-translations-l10n"
REMOVED="plasma-discover plasma-discover-backend-flatpak plasma-discover-backend-fwupd"
# Our packages on an installed system (the installer settings are removed
# together with the installer).
OURS=$(find "$DEBDIR" -name 'raid-*.deb' | sort)

WORK=$(mktemp -d /var/tmp/raid-update.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

image_packages() {
    sed 's/#.*//' "$LISTS"/*.list.chroot "$KDE_LIST" | tr -s ' \t' '\n' | sed '/^$/d' \
        | grep -v -x -e 'raid-.*' -e 'calamares-settings-raid' | sort -u
}

# Everything apt would install for these packages on an empty system.
resolve() {
    : > "$WORK/status"
    apt-get -s -q -o Dir::State::status="$WORK/status" -o Debug::NoLocking=1 \
        -o APT::Install-Recommends=true install "$@" 2>/dev/null \
        | awk '/^Inst / { print $2 }' | sort -u
}

echo "==> Resolving the packages of 1.0 and $VERSION"
mapfile -t new_list < <(image_packages)
mapfile -t old_list < <(image_packages | grep -v -x -F -f <(tr -s ' \n' '\n' <<<"$ADDED"))
read -r -a removed <<<"$(tr -s ' \n' ' ' <<<"$REMOVED")"
resolve "${old_list[@]}" "${removed[@]}" > "$WORK/old"
# shellcheck disable=SC2086
resolve "${new_list[@]}" $OURS > "$WORK/new"
if [ ! -s "$WORK/old" ] || [ ! -s "$WORK/new" ]; then
    echo "make-update.sh: apt could not resolve the package lists" >&2
    exit 1
fi
comm -13 "$WORK/old" "$WORK/new" | grep -v -x -e 'raid-.*' > "$WORK/needed" || true
echo "    $(wc -l < "$WORK/needed") Debian packages are new since 1.0"

rm -rf "$OUT"
mkdir -p "$OUT/pool"
echo "==> Downloading them"
if [ -s "$WORK/needed" ]; then
    # An incomplete update would only fail on the laptop, so stop here.
    if ! (cd "$WORK" && xargs -a needed apt-get download -q > download.log 2>&1); then
        cat "$WORK/download.log" >&2
        echo "make-update.sh: the packages could not be downloaded" >&2
        exit 1
    fi
    mv "$WORK"/*.deb "$OUT/pool/"
fi
# shellcheck disable=SC2086
cp $OURS "$OUT/pool/"

echo "==> Writing the repository"
(cd "$OUT/pool" && apt-ftparchive packages . > Packages && gzip -9kn Packages \
    && apt-ftparchive -o APT::FTPArchive::Release::Origin="RaiD Linux" \
       -o APT::FTPArchive::Release::Label="RaiD Linux $VERSION update" release . > Release)
install -m 644 "$TOP/scripts/update/install-update.sh" "$OUT/install-update.sh"
echo "$VERSION" > "$OUT/VERSION"
sed "s/@VERSION@/$VERSION/g" "$TOP/scripts/update/README.txt" > "$OUT/ПРОЧТИ.txt"

echo "==> $OUT ($(du -sh "$OUT" | cut -f1))"
