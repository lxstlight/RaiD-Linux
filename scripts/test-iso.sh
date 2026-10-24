#!/bin/bash
# QEMU options are comma-separated by design.
# shellcheck disable=SC2054
#
# Boot the ISO in QEMU.
#
# Usage: test-iso.sh ISO [bios|uefi]
#
# Uses KVM when /dev/kvm is available. With HEADLESS=1 the VM runs without
# a window; its screen is reachable over VNC on :1 and a QEMU monitor
# socket is created at $RUN_DIR/monitor (for "screendump file.ppm").
set -euo pipefail

ISO=$1
FIRMWARE=${2:-uefi}
RUN_DIR=${RUN_DIR:-/var/tmp/raid-linux-test}
mkdir -p "$RUN_DIR"

args=(-m 4096 -smp 4 -cdrom "$ISO" -boot d
      -device virtio-net-pci,netdev=net0 -netdev user,id=net0
      -device virtio-vga -usb -device usb-tablet)

# WSL distributions without systemd/udev neither load the KVM module nor
# create its device node.
if [ ! -e /dev/kvm ] && [ "$(id -u)" -eq 0 ]; then
    modprobe kvm_intel 2>/dev/null || modprobe kvm_amd 2>/dev/null || true
    if grep -qw kvm /proc/misc; then
        mknod -m 666 /dev/kvm c 10 "$(awk '$2 == "kvm" { print $1 }' /proc/misc)"
    fi
fi
if [ -w /dev/kvm ]; then
    args+=(-enable-kvm -cpu host)
fi

if [ "$FIRMWARE" = uefi ]; then
    cp /usr/share/OVMF/OVMF_VARS_4M.fd "$RUN_DIR/OVMF_VARS.fd"
    args+=(-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd
           -drive if=pflash,format=raw,file="$RUN_DIR/OVMF_VARS.fd")
fi

# A blank disk to install onto.
if [ ! -e "$RUN_DIR/disk.qcow2" ]; then
    qemu-img create -f qcow2 "$RUN_DIR/disk.qcow2" 40G >/dev/null
fi
args+=(-drive file="$RUN_DIR/disk.qcow2",if=virtio)

if [ "${HEADLESS:-0}" = 1 ]; then
    args+=(-display none -vnc :1 -monitor unix:"$RUN_DIR/monitor",server,nowait)
fi

exec qemu-system-x86_64 "${args[@]}"
