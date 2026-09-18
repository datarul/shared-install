#!/usr/bin/env bash
# İsteğe bağlı: bu kullanıcının etkileşimli Bash oturumlarında umask 0007 kullanmasını sağlar.
# Her kullanıcı KENDİ hesabıyla, sudo KULLANMADAN çalıştırır.
#
# Bu seçim, kullanıcının Datarul dışındaki yeni dosyalarını da etkiler. İstemiyorsanız
# umask 0007'yi yalnızca Datarul işlerini yaptığınız alt kabukta verin (README §5).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh" || exit 1

common_parse_args "$@"
set -- ${COMMON_ARGS[@]+"${COMMON_ARGS[@]}"}

UMASK_LINE='umask 0007 # Datarul: ortak grup yazma izni'

script_intro \
    "Bu kullanıcının Bash başlangıç dosyalarına 'umask 0007' satırını ekler." \
    "Hedef hesap: $(id -un)  —  dosyalar: ~/.bashrc + Bash'in seçtiği login dosyası" \
    "Tekrar çalıştırmak güvenlidir: aynı satır ikinci kez eklenmez."

if [[ "$(id -u)" -eq 0 || -n "${SUDO_USER:-}" ]]; then
    datarul_fail "Bu script'i sudo/root ile değil, kendi hesabınızla çalıştırın."
    exit 1
fi

# Bash'in login kabuğunda okuyacağı ilk dosyayı seç.
if [[ -f "$HOME/.bash_profile" && -r "$HOME/.bash_profile" ]]; then
    login_file="$HOME/.bash_profile"
elif [[ -f "$HOME/.bash_login" && -r "$HOME/.bash_login" ]]; then
    login_file="$HOME/.bash_login"
else
    login_file="$HOME/.profile"
fi

plan_header

heading "Düzenlenecek dosyalar — kullanıcı $(id -un)"
for startup_file in "$HOME/.bashrc" "$login_file"; do
    if [[ -f "$startup_file" ]] && grep -Fx "$UMASK_LINE" "$startup_file" >/dev/null 2>&1; then
        skip_item "$startup_file — satır zaten var, tekrar eklenmeyecek"
    elif [[ -f "$startup_file" ]]; then
        new_item "$startup_file — sonuna eklenecek: $UMASK_LINE"
    else
        new_item "$startup_file — dosya oluşturulup satır eklenecek: $UMASK_LINE"
    fi
done

heading "Etkisi"
note_item "yeni dosyalar 0660, yeni dizinler 0770 (setgid altında 2770) olur"
note_item "bu seçim yalnızca $(id -un) hesabını, ama Datarul dışındaki dosyalarını da etkiler"
note_item "çalışan kabuğun umask değeri değişmez — yeni oturum ya da elle 'umask 0007' gerekir"

heading "Yapılmayacaklar"
note_item "sudo kullanılmaz, başka kullanıcının dosyalarına dokunulmaz"
note_item "mevcut satırlar silinmez/değiştirilmez; zsh/fish başlangıç dosyaları düzenlenmez"
note_item "hâlihazırda var olan dosyaların izinleri geriye dönük düzelmez"

printf '\n'
confirm "Yukarıdaki plan uygulansın mı?" || exit 1
printf '\n'

for startup_file in "$HOME/.bashrc" "$login_file"; do
    if [[ ! -f "$startup_file" ]] || ! grep -Fx "$UMASK_LINE" "$startup_file" >/dev/null; then
        printf '\n%s\n' "$UMASK_LINE" >> "$startup_file"
        printf 'Eklendi: %s\n' "$startup_file"
    else
        printf 'Zaten mevcut: %s\n' "$startup_file"
    fi
done

printf '\nBu script çağıran kabuğun umask değerini değiştiremez. Şimdiki oturumda etkinleştirmek için:\n'
printf '  umask 0007\n'
printf 'Yeni oturumda "umask" çıktısını kontrol edin: başlangıç dosyasındaki erken bir return\n'
printf 'veya sistem politikası ayarın uygulanmasını engelleyebilir.\n'
printf 'Zsh/Fish kullanıyorsanız kendi kabuğunuzun başlangıç dosyasını düzenleyin.\n'
