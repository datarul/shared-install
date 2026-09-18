#!/usr/bin/env bash
# Ortak kurulum dizinini hazırlar: ortak grup, <BASE_DIR>, <BASE_DIR>/uploads ve
# <BASE_DIR>/install klonu; sonunda kurulumu yürüten kullanıcıyı yetkilendirir.
# Root olarak DEĞİL, normal kullanıcıyla çalıştırılır; ayrıcalıklı komutlar sudo ile çağrılır.
#
# Önce yapılacak işlerin tamamını ekrana yazar, sonra [e/H] onayı ister.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh" || exit 1

common_parse_args "$@"
set -- ${COMMON_ARGS[@]+"${COMMON_ARGS[@]}"}

INSTALL_DIR="$BASE_DIR/install"
UPLOADS_DIR="$BASE_DIR/uploads"

script_intro \
    "Ortak kurulum dizinini hazırlar (idempotent): grup, dizinler, install klonu." \
    "Aşağıdaki plan uygulanmadan önce onayınız istenir."

if [[ "$LOGIN_USER" == "root" ]]; then
    datarul_fail "Doğrudan root girişi: --login-user <kullanıcı> ile gerçek bir hesap verin."
    exit 1
fi

# --------------------------------------------------------------------------------------
# Plan ekranı — mevcut duruma göre "yapılacak" / "atlanacak" ayrımıyla
# --------------------------------------------------------------------------------------

describe_dir() {
    local target="$1" state owner
    state="$(probe_path "$target")"
    case "$state" in
        yok) new_item "$target — oluşturulacak (install -d -o root -g $SHARED_GROUP -m 2770)" ;;
        var)
            owner="$(sudo -n stat -c '%U:%G %a' -- "$target" 2>/dev/null \
                     || stat -c '%U:%G %a' -- "$target" 2>/dev/null || echo '?')"
            skip_item "$target — mevcut ($owner); sahipliği doğrulanıp mod 2770 uygulanacak" ;;
        *)   note_item "$target — durumu bu oturumdan okunamadı; mevcutsa doğrulanır, yoksa oluşturulur" ;;
    esac
}

plan_header

heading "1) Ortak Linux grubu: $SHARED_GROUP"
if getent group "$SHARED_GROUP" >/dev/null 2>&1; then
    skip_item "grup zaten var (GID $(getent group "$SHARED_GROUP" | cut -d: -f3)) — yeniden oluşturulmayacak"
    note_item "yerel bir grup olduğu ve GID'inin 0 olmadığı doğrulanacak"
else
    new_item "grup oluşturulacak: sudo groupadd $SHARED_GROUP"
fi
note_item "gruba yalnızca ortak kurulum dosyalarını değiştirmesine güvenilen kullanıcılar eklenmeli"

heading "2) Dizinler — sahip root:$SHARED_GROUP, mod 2770 (drwxrws---), setgid açık"
describe_dir "$BASE_DIR"
describe_dir "$UPLOADS_DIR"
note_item "uploads, install'ın içinde değil kardeşidir; depo yenilense de veriler etkilenmez"
note_item "mevcut dizinlerin İÇİNDEKİ dosyalara dokunulmaz (özyinelemeli chmod/chown yok)"

heading "3) install deposu — $INSTALL_DIR"
case "$(probe_path "$INSTALL_DIR/.git")" in
    var)
        skip_item "klon mevcut — origin adresinin $REPO_URL olduğu doğrulanacak, yeniden klonlanmayacak" ;;
    yok)
        new_item "git clone $REPO_URL → $INSTALL_DIR"
        new_item "klon '$LOGIN_USER' kullanıcısı + '$SHARED_GROUP' grubu + umask 0007 ile çalışacak" ;;
    *)
        note_item "klonun durumu bu oturumdan okunamadı; mevcutsa origin doğrulanır, yoksa klonlanır" ;;
esac
new_item "depo ayarı: core.sharedRepository=group"
note_item "mevcut klonda pull / reset / clean / dosya silme YAPILMAZ"

heading "4) Kullanıcı — $LOGIN_USER"
if id -nG -- "$LOGIN_USER" 2>/dev/null | tr ' ' '\n' | grep -Fx "$SHARED_GROUP" >/dev/null; then
    skip_item "$LOGIN_USER zaten $SHARED_GROUP üyesi — üyelik ekleme atlanacak"
else
    new_item "$LOGIN_USER, $SHARED_GROUP grubuna eklenecek (usermod -a -G; mevcut grupları korunur)"
fi
new_item "~$LOGIN_USER/.gitconfig → safe.directory = $INSTALL_DIR (aynı kayıt çoğaltılmaz)"

heading "Yapılmayacaklar"
note_item "yeni Linux hesabı açılmaz/silinmez, kimseye sudo yetkisi verilmez"
note_item "Datarul servisleri kurulmaz/başlatılmaz, uygulamanın upload yolu bağlanmaz"
note_item "başka bir kurulumun sahiplik/izinleri topluca dönüştürülmez"
note_item "grup üyeliği açık oturumlara geriye dönük uygulanmaz — yeniden SSH girişi gerekir"

printf '\n  Ayrıcalıklı adımlar sudo ile çalışır; script'\''i sudo ile ÇAĞIRMAYIN.\n\n'

confirm "Yukarıdaki plan uygulansın mı?" || exit 1

# --------------------------------------------------------------------------------------
# Uygulama
# --------------------------------------------------------------------------------------

printf '\n\033[1m[1/4]\033[0m Ortak grup: %s\n' "$SHARED_GROUP"
datarul_check_settings
datarul_check_user "$LOGIN_USER"
if ! getent group "$SHARED_GROUP" >/dev/null; then
    sudo groupadd -- "$SHARED_GROUP"
    printf '  grup oluşturuldu.\n'
else
    printf '  grup zaten var, atlandı.\n'
fi
datarul_check_group

printf '\n\033[1m[2/4]\033[0m Dizinler: %s, %s\n' "$BASE_DIR" "$UPLOADS_DIR"
datarul_prepare_directory "$BASE_DIR"
datarul_prepare_directory "$UPLOADS_DIR"
sudo stat -c '  %A %a %U:%G %n' -- "$BASE_DIR" "$UPLOADS_DIR"

printf '\n\033[1m[3/4]\033[0m install deposu: %s\n' "$INSTALL_DIR"
# Klon, kullanıcı + ortak grup seçilerek çalışır; bunun için sudo politikası hem kullanıcı
# hem grup belirtmeye izin vermelidir (sudoers: (ALL:ALL), yalnızca (ALL) yetmez).
if ! sudo -H -u "$LOGIN_USER" -g "$SHARED_GROUP" -- true; then
    datarul_fail "sudo, '$LOGIN_USER' kullanıcısı + '$SHARED_GROUP' grubuyla komut çalıştıramadı. \
sudoers girdisi kullanıcı ve grup içermeli, örneğin: '$LOGIN_USER ALL=(ALL:ALL) ALL'."
    exit 1
fi

# Kullanıcının mevcut SSH oturumu yeni grubu henüz taşımayabilir.
# Bu komutta grubu açıkça seçeriz; Git root olarak çalışmaz.
sudo -H -u "$LOGIN_USER" -g "$SHARED_GROUP" -- \
    bash --noprofile --norc -s -- "$INSTALL_DIR" "$REPO_URL" <<'DATARUL_CLONE'
set -euo pipefail
install_dir=$1
repo_url=$2
umask 0007
cd /

if [[ -L "$install_dir" ]]; then
    printf 'HATA: install sembolik bağ olamaz.\n' >&2
    exit 1
fi

if [[ -e "$install_dir" ]]; then
    # Dosya, boş klasör, yarım klon veya ayrı worktree üzerine yazılmaz.
    if [[ ! -d "$install_dir/.git" || -L "$install_dir/.git" ]]; then
        printf 'HATA: install mevcut, fakat normal bir Git klonu değil.\n' >&2
        exit 1
    fi
    current_origin=$(git -c safe.directory="$install_dir" -C "$install_dir" \
        config --local --get remote.origin.url)
    if [[ "$current_origin" != "$repo_url" ]]; then
        printf 'HATA: Mevcut deponun origin adresi beklenen adresle eşleşmiyor.\n' >&2
        exit 1
    fi
    printf '  mevcut install deposu korunuyor; yeniden klonlanmıyor.\n'
else
    git clone --origin origin --config core.sharedRepository=group \
        -- "$repo_url" "$install_dir"
fi

# Bu güven istisnası yalnızca belirtilen depo ve bu komut için geçerlidir.
git -c safe.directory="$install_dir" -C "$install_dir" \
    config --local core.sharedRepository group
DATARUL_CLONE

printf '\n\033[1m[4/4]\033[0m Kullanıcı: %s\n' "$LOGIN_USER"
# Dizinler ve depo hazırlandıktan sonra mevcut kullanıcıyı yetkilendirir.
datarul_add_user "$LOGIN_USER"

printf '\n\033[0;32mHazır:\033[0m %s ve %s\n' "$INSTALL_DIR" "$UPLOADS_DIR"
printf 'Sıradaki adımlar:\n'
printf '  1. SSH oturumunu kapatıp yeniden açın (yeni grup üyeliği için).\n'
printf '  2. ./check-access.sh ile izinleri doğrulayın.\n'
printf '  3. Başka kullanıcılar için: ./add-user.sh <kullanıcı>\n'
