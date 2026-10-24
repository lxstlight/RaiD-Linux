#!/bin/bash
# Create the root file system of the "RaiD-Builder" WSL distribution: a
# Debian 13 system with live-build and everything needed to build the
# RaiD Linux packages and ISO.
#
# Usage (as root, in any Debian or Ubuntu WSL distribution):
#   make-builder-rootfs.sh OUTPUT.tar
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

OUT=$1
ROOT=$(mktemp -d /var/tmp/raid-builder-rootfs.XXXXXX)

cleanup() {
    for m in dev/pts dev sys proc; do
        if mountpoint -q "$ROOT/$m"; then
            umount -l "$ROOT/$m"
        fi
    done
}
trap cleanup EXIT

apt-get update -qq
apt-get install -y -qq debootstrap debian-archive-keyring >/dev/null

# Minimal bootstrap first; apt resolves the rest (debootstrap's own
# resolver does not handle virtual packages such as perl-openssl-abi-3).
debootstrap --arch=amd64 --variant=minbase \
    --keyring=/usr/share/keyrings/debian-archive-keyring.gpg \
    trixie "$ROOT" http://deb.debian.org/debian

mount -t proc proc "$ROOT/proc"
mount -t sysfs sys "$ROOT/sys"
mount --bind /dev "$ROOT/dev"
mount -t devpts devpts "$ROOT/dev/pts"
cp /etc/resolv.conf "$ROOT/etc/resolv.conf"

cat > "$ROOT/etc/apt/sources.list" <<'EOF'
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF

chroot "$ROOT" apt-get update -qq
chroot "$ROOT" apt-get install -y -qq \
    live-build build-essential debhelper dh-python devscripts dpkg-dev fakeroot gettext \
    librsvg2-bin imagemagick fonts-dejavu-core chafa python3 python3-polib python3-pyflakes \
    python3-pyqt6 shellcheck lintian \
    xorriso squashfs-tools mtools dosfstools grub-efi-amd64-bin grub-pc-bin \
    syslinux isolinux syslinux-utils ca-certificates curl rsync make git apt-utils \
    qemu-system-x86 qemu-utils ovmf
chroot "$ROOT" apt-get clean

cleanup
trap - EXIT

cat > "$ROOT/etc/wsl.conf" <<'EOF'
[boot]
systemd=false

[user]
default=root

[interop]
appendWindowsPath=false
EOF
echo raid-builder > "$ROOT/etc/hostname"
rm -f "$ROOT/etc/resolv.conf"

tar --numeric-owner -C "$ROOT" -cpf "$OUT" .
rm -rf --one-file-system "$ROOT"
echo "Root file system written to $OUT"
