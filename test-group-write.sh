#!/usr/bin/env bash
# İki kullanıcılı grup yazma testi. uploads altında geçici bir test dizini oluşturur;
# ikinci kullanıcı aynı dosyaya yazıp dizini kaldırır. Kurulumun asıl kabul kontrolüdür.
#
#   1. kullanıcı (kendi yeni SSH oturumunda):  ./test-group-write.sh
#   2. kullanıcı (kendi yeni SSH oturumunda):  ./test-group-write.sh --finish <yol>
#
# Yalnızca kendi ürettiği geçici dizine dokunur; başka dosyayı silmez.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh" || exit 1

TEST_PREFIX=".datarul-permission-test."
FINISH_DIR=""

REST_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --finish)   FINISH_DIR="${2:?--finish bir yol ister}"; shift ;;
        --finish=*) FINISH_DIR="${1#*=}" ;;
        *)          REST_ARGS+=("$1") ;;
    esac
    shift
done
common_parse_args ${REST_ARGS[@]+"${REST_ARGS[@]}"}

umask 0007

if [[ -z "$FINISH_DIR" ]]; then
    script_intro \
        "1. adım: uploads altında geçici test dizini ve dosyası oluşturur." \
        "Ana dizin : $BASE_DIR" \
        "Oluşturulan dizin testin sonunda 2. kullanıcı tarafından kaldırılır."

    plan_header
    heading "1. adım — bu kullanıcı ($(id -un))"
    new_item "$BASE_DIR/uploads/${TEST_PREFIX}XXXXXXXX geçici dizini oluşturulacak, mod 2770"
    new_item "içine shared.txt yazılacak (umask 0007 → mod 660, grup $SHARED_GROUP)"
    new_item "dizin ve dosyanın izinleri ekrana yazılacak"
    heading "Sonraki adım"
    note_item "yazdırılan yolu 2. kullanıcı '--finish <yol>' ile kullanır; test dizinini o kaldırır"
    heading "Yapılmayacaklar"
    note_item "uploads altındaki başka hiçbir dosyaya dokunulmaz; kalıcı veri yazılmaz"

    printf '\n'
    confirm "Yukarıdaki plan uygulansın mı?" || exit 1

    test_dir=$(mktemp -d -- "$BASE_DIR/uploads/${TEST_PREFIX}XXXXXXXX")
    # mktemp özel izin oluşturur; test dizinine amaçlanan modu açıkça veriyoruz.
    chmod 2770 -- "$test_dir"
    printf 'ilk kullanıcı (%s)\n' "$(id -un)" > "$test_dir/shared.txt"

    printf '\n'
    stat -c '%A %a %U:%G %n' -- "$test_dir" "$test_dir/shared.txt"
    printf '\nBeklenen: dizin 2770, dosya 660, her ikisi de %s grubunda.\n' "$SHARED_GROUP"
    printf '\n2. kullanıcı kendi yeni SSH oturumunda şunu çalıştırsın:\n'
    printf '  %s --finish %q\n' "$SCRIPT_DIR/test-group-write.sh" "$test_dir"
    exit 0
fi

script_intro \
    "2. adım: 1. kullanıcının dosyasına ekleme yapar, okur ve test dizinini kaldırır." \
    "Test dizini: $FINISH_DIR"

[[ "$FINISH_DIR" == "$BASE_DIR/uploads/${TEST_PREFIX}"* ]] ||
    { datarul_fail "Yalnızca $BASE_DIR/uploads/${TEST_PREFIX}* yolları kabul edilir."; exit 1; }
[[ ! -L "$FINISH_DIR" ]] || { datarul_fail "Sembolik bağ kabul edilmiyor."; exit 1; }
[[ -d "$FINISH_DIR" ]] || { datarul_fail "Test dizini bulunamadı: $FINISH_DIR"; exit 1; }

plan_header
heading "2. adım — bu kullanıcı ($(id -un))"
new_item "$FINISH_DIR/shared.txt dosyasına bir satır eklenecek (1. kullanıcının dosyası)"
new_item "dosyanın tamamı ekrana yazılacak"
new_item "shared.txt silinecek ve $FINISH_DIR dizini kaldırılacak"
heading "Yapılmayacaklar"
note_item "yalnızca $BASE_DIR/uploads/${TEST_PREFIX}* yolları kabul edilir; başka yol reddedilir"
note_item "install deposuna ve diğer upload dosyalarına dokunulmaz"

printf '\n'
confirm "Yukarıdaki plan uygulansın mı?" || exit 1

printf 'ikinci kullanıcı (%s)\n' "$(id -un)" >> "$FINISH_DIR/shared.txt"
printf '\n'
cat -- "$FINISH_DIR/shared.txt"

# Yalnızca bu testin dosyası ve boş dizini kaldırılır.
rm -- "$FINISH_DIR/shared.txt"
rmdir -- "$FINISH_DIR"

printf '\n\033[0;32m✓\033[0m İki kullanıcı arasında grup yazma izni doğrulandı; test dizini kaldırıldı.\n'
