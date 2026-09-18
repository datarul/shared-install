#!/usr/bin/env bash
# Salt okunur doğrulama: dizin modları/sahiplikleri, Git paylaşım ayarı, kullanıcının
# grup üyeliği ve güncel umask. Hiçbir şeyi değiştirmez.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh" || exit 1

common_parse_args "$@"
set -- ${COMMON_ARGS[@]+"${COMMON_ARGS[@]}"}

script_intro \
    "Ortak kurulum dizininin izinlerini ve Git ayarlarını raporlar (salt okunur)." \
    "Ana dizin : $BASE_DIR" \
    "Grup      : $SHARED_GROUP"

pause

printf '\033[1m1) Dizin izinleri\033[0m — beklenen: %s ve uploads için root:%s, 2770, drwxrws---\n' \
    "$BASE_DIR" "$SHARED_GROUP"
stat -c '%A %a %U:%G %n' -- \
    "$BASE_DIR" "$BASE_DIR/install" "$BASE_DIR/uploads" 2>&1 ||
    printf 'Dizinler okunamadı; önce ./prepare-shared-dir.sh çalıştırılmış olmalı.\n'
printf '   install dizini ilk kuran kullanıcıya ve %s grubuna ait olmalıdır.\n\n' "$SHARED_GROUP"

printf '\033[1m2) Git paylaşım ayarı\033[0m — beklenen: group\n'
git -C "$BASE_DIR/install" config --local --get core.sharedRepository 2>&1 ||
    printf 'Okunamadı (gruba üye değilseniz ya da depo yoksa beklenen sonuç).\n'
printf '\n'

printf '\033[1m3) Git güven listesi (%s)\033[0m — beklenen: %s/install\n' "$(id -un)" "$BASE_DIR"
git config --global --get-all safe.directory 2>/dev/null ||
    printf '(kayıt yok)\n'
printf '\n'

printf '\033[1m4) Bu oturumun grupları\033[0m — beklenen: listede %s var\n' "$SHARED_GROUP"
id -nG
if id -nG | tr ' ' '\n' | grep -Fx "$SHARED_GROUP" >/dev/null; then
    printf '\033[0;32m✓\033[0m %s grubu bu oturumda etkin.\n' "$SHARED_GROUP"
else
    printf '\033[0;31m✗\033[0m %s bu oturumda yok. Gruba eklendiyseniz SSH oturumunu kapatıp yeniden açın.\n' \
        "$SHARED_GROUP"
fi
printf '\n'

printf '\033[1m5) Güncel umask\033[0m — Datarul işlemlerinde beklenen: 0007\n'
umask
printf '\nYazma paritesini iki kullanıcıyla sınamak için: ./test-group-write.sh\n'
