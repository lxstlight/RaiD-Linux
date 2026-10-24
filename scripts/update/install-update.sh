#!/bin/sh
# Обновление установленной RaiD Linux с флешки.
#
# Запуск из этой папки:  sudo sh install-update.sh
#
# Все нужные пакеты лежат рядом, в pool/, так что интернет не нужен. Если он
# есть, apt заодно возьмёт из архива Debian то, чего на флешке нет.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
VERSION=$(cat "$HERE/VERSION" 2>/dev/null || echo "?")
POOL=/var/cache/raid-update
SOURCE=/etc/apt/sources.list.d/raid-update.list
PACKAGES="raid-base raid-artwork raid-tools-common raid-tune raid-driver-manager raid-build
          raid-welcome raid-store systemd-zram-generator earlyoom qt6-translations-l10n
          neowofetch hyfetch fonts-inter appmenu-gtk3-module"

say() {
    printf '\n\033[1;38;5;208m==> %s\033[0m\n' "$*"
}

fail() {
    printf '\n\033[1;31mОшибка: %s\033[0m\n' "$*" >&2
    exit 1
}

# Временный источник пакетов убирается при любом исходе.
cleanup() {
    rm -f "$SOURCE"
    rm -rf "$POOL"
}

[ "$(id -u)" -eq 0 ] || fail "запустите обновление от администратора: sudo sh $0"
grep -q '^ID=raid$' /etc/os-release 2>/dev/null \
    || fail "это обновление для установленной RaiD Linux."
[ ! -d /run/live/medium ] \
    || fail "запущена live-система с флешки, а обновлять нужно установленную систему."
[ -f "$HERE/pool/Packages" ] || fail "рядом со скриптом нет папки pool с пакетами."

# С флешки apt читать неудобно (права, пробелы в пути), поэтому сначала копия.
say "Копирую пакеты с флешки"
trap cleanup EXIT
rm -rf "$POOL"
cp -r "$HERE/pool" "$POOL"
echo "deb [trusted=yes] file:$POOL ./" > "$SOURCE"

export DEBIAN_FRONTEND=noninteractive
if getent hosts deb.debian.org >/dev/null 2>&1; then
    say "Обновляю списки пакетов (есть интернет)"
    apt-get update -q || true
else
    say "Интернета нет: ставлю только с флешки"
    apt-get update -q -o Dir::Etc::SourceList="$SOURCE" -o Dir::Etc::SourceParts=- \
        -o APT::Get::List-Cleanup=0
fi

say "Устанавливаю RaiD Linux $VERSION"
# Виджеты для дока RaiD Aqua нужны там, где стоит Plasma.
extra=""
if dpkg-query -W -f '${db:Status-Abbrev}' plasma-desktop 2>/dev/null | grep -q '^ii'; then
    extra="plasma-widgets-addons"
fi
# shellcheck disable=SC2086
apt-get install -y -q $PACKAGES $extra \
    || fail "не удалось установить пакеты. Подключитесь к интернету и запустите обновление ещё раз."

# Магазин приложений теперь RaiD Store, Discover больше не нужен.
discover=$(dpkg-query -W -f '${Package} ${db:Status-Abbrev}\n' 'plasma-discover*' \
               2>/dev/null | awk '$2 ~ /^ii/ { print $1 }')
if [ -n "$discover" ]; then
    say "Убираю Discover: вместо него теперь RaiD Store"
    # shellcheck disable=SC2086
    apt-get purge -y -q $discover || true
fi

# Готовый каталог для русского и английского: RaiD Store откроется сразу.
say "Готовлю каталог RaiD Store (на медленном компьютере это займёт пару минут)"
appstreamcli refresh-cache --force >/dev/null 2>&1 || true
for language in ru en; do
    LANGUAGE=$language LC_ALL=C.UTF-8 PYTHONDONTWRITEBYTECODE=1 python3 -I -c '
import sys
sys.path.insert(0, "/usr/share/raid-tools")
from raidlinux.store.catalog import SYSTEM_CACHE, Catalog
Catalog().build().save_cache(SYSTEM_CACHE)
' 2>/dev/null || true
done

say "Готово! Перезагрузите компьютер, чтобы включилось сжатие памяти (zram)."
echo "На слабом компьютере облегчённый режим включится сам при следующем входе."
echo "Сменить его можно в «Добро пожаловать» → «Оформление» → «Быстродействие»."
