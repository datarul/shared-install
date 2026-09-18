#!/usr/bin/env bash
# lib/common.sh — ortak kurulum dizini script'lerinin paylaştığı ayarlar, onay kapısı ve
# doğrulama fonksiyonları. Tek başına çalıştırılmaz; her script bunu source eder.
#
# Kullanım:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib/common.sh" || exit 1
#   common_parse_args "$@"; set -- ${COMMON_ARGS[@]+"${COMMON_ARGS[@]}"}
#
# Ayarlar — ortam değişkeni ya da bayrak (bayrak önceliklidir):
#   BASE_DIR      --base-dir <yol>     (varsayılan: /opt/datarul)
#   SHARED_GROUP  --group <ad>         (varsayılan: datarul)
#   REPO_URL      --repo-url <adres>   (varsayılan: https://github.com/datarul/install.git)
#   LOGIN_USER    --login-user <ad>    (varsayılan: SUDO_USER, yoksa `id -un`)
#   -y / --yes / DATARUL_ASSUME_YES=true → onay sorma
#
# Script'ler root olarak DEĞİL, normal kullanıcıyla çalıştırılır; ayrıcalıklı her komut
# tek tek `sudo` ile çağrılır.

BASE_DIR="${BASE_DIR:-/opt/datarul}"
SHARED_GROUP="${SHARED_GROUP:-datarul}"
REPO_URL="${REPO_URL:-https://github.com/datarul/install.git}"
LOGIN_USER="${LOGIN_USER:-${SUDO_USER:-$(id -un)}}"

COMMON_YES="${DATARUL_ASSUME_YES:-false}"
COMMON_ARGS=()

# --------------------------------------------------------------------------------------
# Argümanlar, açılış mesajı, onay kapısı
# --------------------------------------------------------------------------------------

# common_parse_args "$@" — ortak bayrakları ayıklar, kalanları COMMON_ARGS'a koyar.
common_parse_args() {
    COMMON_ARGS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)       COMMON_YES=true ;;
            --base-dir)     BASE_DIR="${2:?--base-dir bir yol ister}"; shift ;;
            --base-dir=*)   BASE_DIR="${1#*=}" ;;
            --group)        SHARED_GROUP="${2:?--group bir grup adı ister}"; shift ;;
            --group=*)      SHARED_GROUP="${1#*=}" ;;
            --repo-url)     REPO_URL="${2:?--repo-url bir adres ister}"; shift ;;
            --repo-url=*)   REPO_URL="${1#*=}" ;;
            --login-user)   LOGIN_USER="${2:?--login-user bir kullanıcı adı ister}"; shift ;;
            --login-user=*) LOGIN_USER="${1#*=}" ;;
            *)              COMMON_ARGS+=("$1") ;;
        esac
        shift
    done
}

# script_intro "<satır 1>" ["<satır 2>" …] — script adı + ne yaptığı; her koşuda basılır.
script_intro() {
    printf '\n\033[0;34m▶ %s\033[0m\n' "$(basename "$0")"
    local line
    for line in "$@"; do printf '  %s\n' "$line"; done
    printf '  \033[0;90m(-y: onay sorma / tuş bekleme)\033[0m\n\n'
}

# pause [mesaj] — salt okunur script'ler için. -y verilmişse ya da TTY yoksa beklemez.
pause() {
    [[ "$COMMON_YES" == "true" ]] && return 0
    [[ -t 0 ]] || return 0
    printf '\033[1;33m%s\033[0m' "${1:-Devam etmek için bir tuşa basın (çıkmak için Ctrl+C)… }"
    read -r -n 1 -s _key
    printf '\n'
}

# confirm "<soru>" → e/evet/y/yes = 0; başka her şey (Enter dahil) = 1.
# TTY yoksa ve -y verilmemişse: takılmaz, sessizce ilerlemez — açık hata ile 1 döner.
confirm() {
    [[ "$COMMON_YES" == "true" ]] && return 0
    if [[ ! -t 0 ]]; then
        printf '\033[0;31mHata:\033[0m onay gerekiyor ama etkileşimli terminal yok — otomasyonda "-y" verin.\n' >&2
        return 1
    fi
    printf '\033[1;33m%s [e/H]: \033[0m' "$1"
    local answer
    read -r answer
    case "$answer" in
        e|E|evet|Evet|EVET|y|Y|yes|YES) return 0 ;;
    esac
    printf 'Vazgeçildi.\n' >&2
    return 1
}

# --------------------------------------------------------------------------------------
# Plan ekranı yardımcıları — onay öncesi "ne yapılacak" listesi
# --------------------------------------------------------------------------------------

plan_header() {
    printf '\n  \033[1mYapılacak işlemler — sırayla\033[0m\n'
    printf '  %s\n' "────────────────────────────────────────────────────────────────"
}
heading()   { printf '\n  \033[1m%s\033[0m\n' "$*"; }
new_item()  { printf '     \033[0;32m+\033[0m %s\n' "$*"; }   # yeni işlem
skip_item() { printf '     \033[0;33m=\033[0m %s\n' "$*"; }   # mevcut → doğrulanır/atlanır
note_item() { printf '     \033[0;90m·\033[0m %s\n' "$*"; }   # bilgi / sınır

# probe_path <yol> → "var" | "yok" | "bilinmiyor". sudo parola istiyorsa ekran takılmaz.
probe_path() {
    local target="$1" parent
    if sudo -n test -e "$target" 2>/dev/null; then printf 'var'; return; fi
    if sudo -n true 2>/dev/null; then printf 'yok'; return; fi
    if [[ -e "$target" ]]; then printf 'var'; return; fi
    parent="$(dirname -- "$target")"
    if [[ -r "$parent" && -x "$parent" ]]; then printf 'yok'; else printf 'bilinmiyor'; fi
}

datarul_fail() {
    printf '\033[0;31mHATA:\033[0m %s\n' "$*" >&2
    return 1
}

# --------------------------------------------------------------------------------------
# Doğrulamalar — hepsi hata durumunda 1 döner; çağıran script `set -e` altında durur.
# --------------------------------------------------------------------------------------

# Ana dizin yolu ve grup adı biçimsel olarak güvenli mi?
datarul_check_settings() {
    local normalized
    [[ "$BASE_DIR" == /* && "$BASE_DIR" != / ]] ||
        { datarul_fail "BASE_DIR, kök dizin dışında tam bir yol olmalı."; return 1; }
    [[ "$BASE_DIR" != *$'\n'* && "$BASE_DIR" != *'*'* ]] ||
        { datarul_fail "BASE_DIR satır sonu veya * içeremez."; return 1; }
    [[ "$SHARED_GROUP" =~ ^[a-z_][a-z0-9_-]*$ ]] ||
        { datarul_fail "Geçersiz ortak grup adı: $SHARED_GROUP"; return 1; }

    normalized=$(sudo realpath -m -- "$BASE_DIR") || return 1
    [[ "$normalized" == "$BASE_DIR" ]] ||
        { datarul_fail "Yol sembolik bağ, .., çift / veya sonda / içeriyor: $BASE_DIR"; return 1; }
    sudo test -d "$(dirname -- "$BASE_DIR")" ||
        { datarul_fail "Ana dizinin üst dizini önceden bulunmalı: $(dirname -- "$BASE_DIR")"; return 1; }
}

# Hedef hesap yerel bir Linux kullanıcısı mı ve root değil mi?
datarul_check_user() {
    local target_user="${1:?Kullanıcı adı gerekli}" uid
    # Yerel hesapları kabul eder; mevcut hesap oluşturulmaz veya silinmez.
    awk -F: -v name="$target_user" '
        $1 == name { found = 1 }
        END { exit !found }
    ' /etc/passwd ||
        { datarul_fail "Yerel kullanıcı bulunamadı: $target_user"; return 1; }
    uid=$(id -u -- "$target_user") || return 1
    [[ "$uid" != 0 ]] ||
        { datarul_fail "Ortak çalışma kullanıcısı root olamaz: $target_user"; return 1; }
}

# Ortak grup yerel mi ve GID'i sıfır değil mi?
datarul_check_group() {
    local group_entry group_gid
    group_entry=$(getent group "$SHARED_GROUP") || return 1
    group_gid=$(printf '%s\n' "$group_entry" | cut -d: -f3)
    [[ "$group_gid" != 0 ]] ||
        { datarul_fail "GID 0 ortak grup olarak kullanılamaz."; return 1; }
    awk -F: -v name="$SHARED_GROUP" '
        $1 == name { found = 1 }
        END { exit !found }
    ' /etc/group ||
        { datarul_fail "Ortak grup yerel bir Linux grubu olmalı: $SHARED_GROUP"; return 1; }
}

# Dizini root:<ortak grup> + 2770 olarak hazırlar; mevcutsa sahipliğini doğrular.
datarul_prepare_directory() {
    local directory="${1:?Dizin gerekli}" expected_gid
    expected_gid=$(getent group "$SHARED_GROUP" | cut -d: -f3) || return 1

    sudo test ! -L "$directory" ||
        { datarul_fail "Sembolik bağ kabul edilmiyor: $directory"; return 1; }
    if sudo test -e "$directory"; then
        sudo test -d "$directory" ||
            { datarul_fail "Hedef bir dizin değil: $directory"; return 1; }
        # Başka bir alanı yanlışlıkla ortak kullanıma açmayı önler.
        [[ "$(sudo stat -c '%u:%g' -- "$directory")" == "0:$expected_gid" ]] ||
            { datarul_fail "Mevcut dizinin sahibi root:$SHARED_GROUP değil: $directory"; return 1; }
    else
        sudo install -d -o root -g "$SHARED_GROUP" -m 2770 -- "$directory" || return 1
    fi

    # Yalnızca bu dizini düzenler; mevcut dosyalara özyinelemeli işlem yapmaz.
    sudo chmod 02770 -- "$directory"
}

# Tekrar kullanılabilir kullanıcı hazırlığı: mevcut grupları korur, yalnızca bu kurulumun
# Git dizinini kullanıcının güven listesine ekler. prepare-shared-dir.sh de bunu çağırır.
datarul_add_user() {
    local target_user="${1:?Kullanıcı adı gerekli}" group_gid
    datarul_check_settings
    datarul_check_group
    datarul_check_user "$target_user"
    sudo test ! -L "$BASE_DIR/install" || { datarul_fail "install sembolik bağ olamaz."; return 1; }
    sudo test ! -L "$BASE_DIR/install/.git" || { datarul_fail ".git sembolik bağ olamaz."; return 1; }
    sudo test -d "$BASE_DIR/install/.git" ||
        { datarul_fail "Önce ./prepare-shared-dir.sh ile dizini ve depoyu hazırlayın."; return 1; }
    group_gid=$(getent group "$SHARED_GROUP" | cut -d: -f3)

    if ! id -G -- "$target_user" | tr ' ' '\n' | grep -Fx "$group_gid" >/dev/null; then
        sudo usermod -a -G "$SHARED_GROUP" -- "$target_user"
    fi

    # Git ayarı hedef kullanıcının yetkileriyle ve kendi home diziniyle yazılır.
    # Tam eşleşen değer yenilenir; yeniden çağrıda aynı kayıt çoğalmaz.
    sudo -H -u "$target_user" -- git config --global --fixed-value \
        --replace-all safe.directory "$BASE_DIR/install" "$BASE_DIR/install"

    printf '%s hazır. Yeni SSH oturumu açın; Datarul işlemlerinde umask 0007 kullanın.\n' \
        "$target_user"
}
