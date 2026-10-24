#!/bin/bash
# Prepare the files of a GitHub release in OUTDIR/github-release:
#
#   RaiD-Linux-VERSION-update.zip     the update of installed systems
#   raid-linux-VERSION-amd64.iso.partN the ISO, cut below GitHub's limit of
#                                      2 GiB per file
#   SHA256SUMS                         checksums, the whole ISO included
#   release-notes.md                   text for the release page
#
# Usage: make-release.sh OUTDIR   (after "make iso" and "make update")
set -euo pipefail

TOP=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(realpath "$1")
VERSION=$(cat "$TOP/VERSION")
UPDATE="RaiD-Linux-$VERSION-update"
ISO="raid-linux-$VERSION-amd64.iso"
REL="$OUT/github-release"
# Reading the ISO back from a Windows drive under WSL is slow; use the copy
# in the live-build directory when it is the same image.
BUILD_ISO=$(find "${BUILD_DIR:-/var/tmp/raid-linux-build}" -maxdepth 1 -name '*.iso' 2>/dev/null \
                | head -n1 || true)

if [ ! -d "$OUT/$UPDATE" ]; then
    echo "make-release.sh: $OUT/$UPDATE is missing, run \"make update\" first" >&2
    exit 1
fi
rm -rf "$REL"
mkdir -p "$REL"
# The files are made and checksummed on the Linux file system: reading large
# files back from a Windows drive under WSL is slow and can run out of memory.
WORK=$(mktemp -d /var/tmp/raid-release.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

echo "==> $UPDATE.zip"
# Python's zipfile marks non-ASCII names as UTF-8 in the way every unpacker
# understands (Info-ZIP's zip uses an extra field that some ignore), so
# ПРОЧТИ.txt keeps its name in Ark, Windows and python3 -m zipfile.
(cd "$OUT" && python3 -I - "$UPDATE" "$WORK/$UPDATE.zip" <<'EOF'
import os, sys, zipfile
folder, archive = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for root, dirs, files in os.walk(folder):
        dirs.sort()
        for name in sorted(files):
            z.write(os.path.join(root, name))
EOF
)

if [ -f "$OUT/$ISO" ]; then
    source_iso="$OUT/$ISO"
    if [ -n "$BUILD_ISO" ] && [ "$(stat -c %s "$BUILD_ISO")" = "$(stat -c %s "$OUT/$ISO")" ]; then
        source_iso=$BUILD_ISO
    fi
    echo "==> $ISO in parts of 1900 MiB"
    split -b 1900M --numeric-suffixes=1 -a 1 "$source_iso" "$WORK/$ISO.part"
else
    echo "    no ISO in $OUT, the release only has the update"
fi

echo "==> SHA256SUMS"
(cd "$WORK" && sha256sum -- * > SHA256SUMS)
if [ -f "$OUT/$ISO.sha256" ]; then
    cat "$OUT/$ISO.sha256" >> "$WORK/SHA256SUMS"
fi
cp "$WORK"/* "$REL/"

sed -e "s/@VERSION@/$VERSION/g" -e "s/@UPDATE@/$UPDATE/g" -e "s/@ISO@/$ISO/g" \
    "$TOP/scripts/update/release-notes.md" > "$REL/release-notes.md"

echo "==> $REL ($(du -sh "$REL" | cut -f1))"
ls -l "$REL"
