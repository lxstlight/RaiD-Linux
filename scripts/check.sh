#!/bin/bash
# Static checks: Python (pyflakes), shell scripts (shellcheck) and whether
# every package named by the image, the installer and our packages exists
# in Debian trixie.
#
# Usage: check.sh
set -uo pipefail

TOP=$(cd "$(dirname "$0")/.." && pwd)
cd "$TOP" || exit 1
status=0

echo "==> pyflakes"
python3 -m pyflakes packages/raid-tools/raidlinux packages/raid-tools/bin/raid-* \
    packages/raid-tools/libexec/* packages/raid-artwork/tools/*.py || status=1

echo "==> shellcheck"
shellcheck -s sh -x --source-path=SCRIPTDIR \
    packages/calamares-settings-raid/scripts/* \
    packages/raid-tools/bin/prime-run \
    packages/raid-base/tuning/raid-performance packages/raid-base/tuning/plasma-env.sh \
    packages/raid-base/debian/*.postinst packages/raid-artwork/debian/*.postinst \
    packages/raid-artwork/config/plasma-env-aqua.sh scripts/update/install-update.sh \
    packages/raid-tools/data/systemd/raid-tune.sleep \
    live-build/config/hooks/normal/*.hook.chroot || status=1
shellcheck -s bash scripts/*.sh scripts/wsl/*.sh || status=1

echo "==> package names"
exists() {
    local candidate
    candidate=$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ { print $2 }')
    if [ -n "$candidate" ] && [ "$candidate" != "(none)" ]; then
        return 0
    fi
    # Virtual packages have no candidate but are provided by others.
    [ -n "$(apt-cache showpkg "$1" 2>/dev/null | sed -n '/^Reverse Provides:/,$p' | tail -n +2)" ]
}

own=" raid-base raid-artwork raid-tools-common raid-tune raid-driver-manager raid-build "
own+="raid-welcome raid-store calamares-settings-raid "
installer=packages/calamares-settings-raid
names=$(
    sed 's/#.*//' live-build/config/package-lists/*.list.* "$installer/desktops/kde.list"
    # Software page: "packages: [ a, b ]".
    sed -n 's/^ *packages: *\[\(.*\)\]$/\1/p' "$installer/modules/packagechooser-software.conf" \
        | tr ',' '\n'
    echo task-gnome-desktop task-cinnamon-desktop task-xfce-desktop task-mate-desktop \
         task-lxqt-desktop task-lxde-desktop
    python3 -I - packages/*/debian/control "$installer/scripts/desktop-select" \
        "$installer/scripts/office-select" <<'EOF'
import re, sys
for path in sys.argv[1:]:
    text = open(path, encoding="utf-8").read()
    if path.endswith("/control"):
        fields = re.findall(r"^(?:Build-Depends|Depends|Recommends):(.*(?:\n .*)*)", text, re.M)
        for field in fields:
            for alternative in re.split(r"[,|]", field):
                name = re.sub(r"\(.*?\)|\[.*?\]|<.*?>|:any", "", alternative).strip()
                if name and not name.startswith("$"):
                    print(name)
    else:
        # packages="..." and extras="..." in the installer scripts; names
        # built from variables are checked when they are installed.
        for value in re.findall(r'^\s*(?:packages|extras)="([^"]*)"', text, re.M):
            print("\n".join(n for n in value.split() if "$" not in n))
EOF
)
missing=0
for package in $names; do
    case "$own" in *" $package "*) continue ;; esac
    if ! exists "$package"; then
        echo "missing: $package"
        missing=1
    fi
done
if [ "$missing" = 0 ]; then
    echo "all packages found"
else
    status=1
fi

exit $status
