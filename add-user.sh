#!/usr/bin/env bash
# Var olan bir Linux kullanıcısını ortak gruba ekler ve install deposu için
# kullanıcı bazında safe.directory tanımlar. Yeni hesap OLUŞTURMAZ, sudo yetkisi vermez.
# Tekrar çalıştırmak güvenlidir: mevcut gruplar korunur, aynı Git kaydı çoğalmaz.
#
# Önce yapılacak işleri ekrana yazar, sonra [e/H] onayı ister.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh" || exit 1

common_parse_args "$@"
set -- ${COMMON_ARGS[@]+"${COMMON_ARGS[@]}"}

INSTALL_DIR="$BASE_DIR/install"

script_intro \
    "Verilen kullanıcıları ortak gruba ekler ve Git güven ayarını yazar." \
    "Aşağıdaki plan uygulanmadan önce onayınız istenir."

if [[ $# -lt 1 ]]; then
    printf 'Kullanım: ./add-user.sh <kullanıcı> [<kullanıcı> …] [--base-dir <yol>] [--group <ad>] [-y]\n' >&2
    exit 1
fi

plan_header

heading "Hedef kurulum"
note_item "ana dizin : $BASE_DIR"
note_item "depo      : $INSTALL_DIR  (hazır olmalı; değilse script durur)"
note_item "ortak grup: $SHARED_GROUP"

for username in "$@"; do
    heading "Kullanıcı — $username"
    if ! id -u -- "$username" >/dev/null 2>&1; then
        note_item "UYARI: bu ad için yerel bir Linux hesabı bulunamadı — script bu adımda duracak"
        continue
    fi
    if id -nG -- "$username" 2>/dev/null | tr ' ' '\n' | grep -Fx "$SHARED_GROUP" >/dev/null; then
        skip_item "$username zaten $SHARED_GROUP üyesi — üyelik ekleme atlanacak"
    else
        new_item "$username, $SHARED_GROUP grubuna eklenecek (usermod -a -G; mevcut grupları korunur)"
    fi
    new_item "~$username/.gitconfig → safe.directory = $INSTALL_DIR (aynı kayıt çoğaltılmaz)"
done

heading "Yapılmayacaklar"
note_item "hesap oluşturulmaz/silinmez, parola veya login shell değiştirilmez"
note_item "sudo yetkisi verilmez, diğer grup üyelikleri ve Git ayarları korunur"
note_item "dizin/dosya izinleri değiştirilmez — yalnızca üyelik ve Git güven kaydı"
note_item "grup üyeliği açık oturumlara geriye dönük uygulanmaz — yeniden SSH girişi gerekir"

printf '\n'
confirm "Yukarıdaki plan uygulansın mı?" || exit 1

printf '\n'
for username in "$@"; do
    datarul_add_user "$username"
done

printf '\nGrup üyeliği yalnızca yeni oturumlarda geçerlidir: her kullanıcı SSH bağlantısını\n'
printf 'kapatıp yeniden açmalı, sonra ./check-access.sh ile doğrulamalıdır.\n'
