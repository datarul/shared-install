# Datarul ortak Linux kurulum dizini

Bu dizindeki script'ler, seçilen bir ana dizin altında `install` Git deposunu ve `uploads` veri
dizinini oluşturur; erişimi ortak bir Linux grubu üzerinden verir. Aynı kullanıcı fonksiyonu hem
kurulumu başlatan kullanıcı hem de sonradan eklenecek kullanıcılar için kullanılır.

Örnek sonuç:

```text
/opt/datarul/                  root:datarul, 2770
├── install/                   ilk kuran kullanıcı:datarul   ← https://github.com/datarul/install.git
│   └── .git/
└── uploads/                   root:datarul, 2770
```

`uploads`, `install` ile aynı seviyededir; Git deposunun içinde değildir. Böylece deponun
güncellenmesi, yeniden klonlanması veya branch değiştirilmesi upload verilerini etkilemez.

Bu iş yalnızca **dizin ve erişim hazırlığıdır**. Datarul servislerini başlatmak ve uygulamanın
upload yolunu bu dizine bağlamak ayrıca yapılır.

---

## 1. Ön koşullar

- GNU/Linux, Bash, Git **2.30+** (`git config --fixed-value` gerekir), `sudo`, GNU coreutils,
  `getent` ve shadow-utils (`groupadd`, `usermod`). macOS veya Alpine/BusyBox için hazırlanmamıştır.
- Kurulumu, sunucuya SSH ile bağlanan ve yönetim komutlarını `sudo` ile çalıştırabilen normal bir
  kullanıcı yürütür. **Script'ler `sudo` ile çağrılmaz**; ayrıcalıklı her komutu kendileri `sudo`
  ile çalıştırır.
- `sudo` politikası hem kullanıcı hem **grup** seçimine izin vermelidir — klon adımı
  `sudo -u <kullanıcı> -g <grup>` kullanır. sudoers girdisi `(ALL)` değil `(ALL:ALL)` olmalıdır:

  ```text
  ali ALL=(ALL:ALL) ALL
  ```

  Yalnızca `(ALL)` verilmişse script açık bir hatayla durur, yarım iş bırakmaz.
- Eklenecek hesaplar ve ortak grup **yerel** Linux hesap veritabanında bulunmalıdır; LDAP/AD üyelik
  yönetimi kapsam dışıdır. Script hesap oluşturmaz.
- Ana dizinin üst dizini önceden bulunmalıdır (örn. `/opt/datarul` için `/opt`).
- Örnek, yeni bir kurulum veya bu script'lerle daha önce hazırlanmış dizinler içindir. Başka bir
  kurulumun sahipliğini ve izinlerini topluca dönüştürmez.

## 2. İzin modeli

| Ayar | Etki |
| --- | --- |
| Ortak grup: `datarul` | Yetkili kullanıcıların ortak erişim grubudur. Kullanıcıların mevcut grupları korunur. |
| Dizin modu: `2770` | Sahip ve grup okuyabilir, yazabilir, dizine girebilir. Diğer kullanıcıların erişimi kapalıdır. |
| `setgid` (`2`) | Yeni dosyaların grubu üst dizinden alınır; yeni alt dizinler ayrıca `setgid` bitini miras alır. |
| `umask 0007` | Yeni dosyalar `0660`, yeni dizinler `0770`; `setgid` altında dizinler `2770` olur. |
| `umask 0002` alternatifi | Grup yazma izni yine vardır ama grup dışına da okuma/geçiş verir; bu yüzden `0007` tercih edilir. |

`setgid` grup sahipliğini aktarır, tek başına grup **yazma** izni sağlamaz. `umask` da uygulamanın
istediği izinleri yalnızca kısıtlar: `0600` oluşturan bir uygulamayı `0660` oluşturmaya zorlayamaz.
Varsayılan ACL varsa sonuç ayrıca ACL kurallarına bağlıdır.
([GNU setgid](https://www.gnu.org/software/coreutils/manual/html_node/Directory-Setuid-and-Setgid.html),
[umask(2)](https://man7.org/linux/man-pages/man2/umask.2.html))

Gruba yalnızca ortak kurulum dosyalarını değiştirmesine güvenilen kullanıcılar eklenmelidir. Grup
üyeleri birbirlerinin dosyalarını değiştirebilir, yazılabilir dizinlerden silebilir. Aynı `install`
çalışma ağacında Git güncellemelerini ve kurulumu **sırayla** yürütün.

## 3. Script'ler

Her script çalıştığı an ne yaptığını yazar; durum değiştirenler **yapılacak işlerin tam listesini**
gösterip `[e/H]` onayı ister. `-y` / `--yes` (veya `DATARUL_ASSUME_YES=true`) onayı ve tuş beklemeyi
atlar. TTY yoksa ve `-y` verilmemişse onay isteyen script takılmaz, açık hatayla durur.

| Script | Ne yapar | Durum değiştirir mi |
| --- | --- | --- |
| `prepare-shared-dir.sh` | Grup + `BASE_DIR` + `uploads` + `install` klonu; sonunda kuran kullanıcıyı yetkilendirir | Evet |
| `add-user.sh <kullanıcı>…` | Var olan kullanıcıyı gruba ekler, `safe.directory` yazar | Evet |
| `check-access.sh` | İzin/sahiplik, Git ayarı, grup üyeliği ve umask raporu | Hayır (salt okunur) |
| `test-group-write.sh` | İki kullanıcılı yazma testi; `uploads` altında geçici dizin açıp kaldırır | Evet (yalnız kendi geçici dizini) |
| `set-umask.sh` | Kullanıcının Bash başlangıç dosyalarına `umask 0007` ekler | Evet (yalnız kendi home'u) |

Ortak ayarlar — bayrak ya da ortam değişkeni (bayrak önceliklidir):

| Bayrak | Ortam değişkeni | Varsayılan |
| --- | --- | --- |
| `--base-dir <yol>` | `BASE_DIR` | `/opt/datarul` |
| `--group <ad>` | `SHARED_GROUP` | `datarul` |
| `--repo-url <adres>` | `REPO_URL` | `https://github.com/datarul/install.git` |
| `--login-user <ad>` | `LOGIN_USER` | `SUDO_USER`, yoksa `id -un` |

`lib/common.sh` tek başına çalıştırılmaz; script'ler onu source eder. Sunucuya **dizinin tamamını**
kopyalayın (tek bir `.sh` dosyası tek başına çalışmaz).

## 4. İlk hazırlık

Sunucuda, kendi hesabınızla (başına `sudo` koymadan):

```bash
./prepare-shared-dir.sh
```

Farklı bir ana dizin veya grup için:

```bash
./prepare-shared-dir.sh --base-dir /srv/datarul --group datarul
```

Doğrudan **root** ile giriş yaptıysanız kurulumu yürütecek gerçek hesabı açıkça verin; root ortak
çalışma kullanıcısı olarak kabul edilmez:

```bash
./prepare-shared-dir.sh --login-user ali
```

Script önce planı gösterir (grup var mı, dizinler var mı, klon var mı, kullanıcı zaten üye mi),
onay aldıktan sonra sırayla: ortak grup → `BASE_DIR` → `uploads` → `install` klonu →
kullanıcı yetkilendirme adımlarını uygular.

Klonlama, seçilen ana dizinde `git clone https://github.com/datarul/install.git` çalıştırmakla aynı
hedef yapıyı üretir; ek olarak `core.sharedRepository=group` ayarı kaydedilir ve indirme/checkout
seçilen normal kullanıcıyla, ortak grup ve `umask 0007` altında çalışır.
([git-clone](https://git-scm.com/docs/git-clone), [sudo](https://man7.org/linux/man-pages/man8/sudo.8.html))

`core.sharedRepository`, Git'in **depo içi** dosyaları için paylaşım ayarıdır; çalışma ağacında veya
`uploads` altında başka programların ürettiği dosyaların izinlerini tek başına yönetmez.
`safe.directory`, başka kullanıcıya ait bu ortak depoda Git çalıştırılabilmesi için kullanıcı bazında
tanımlanır — `*` gibi tüm depolara güven veren bir ayar eklenmez.
([git-config](https://git-scm.com/docs/git-config))

Depo erişimi kimlik doğrulaması gerektiriyorsa ilgili Linux kullanıcısının Git erişimini önceden
hazırlayın. Parola veya erişim belirtecini URL'ye yazmayın.

## 5. Diğer kullanıcıları ekleme

Sunucuda önceden bulunan hesaplar için:

```bash
./add-user.sh ayse mehmet

# Mevcut kullanıcı için tekrar çalıştırmak da güvenlidir.
./add-user.sh ali
```

`prepare-shared-dir.sh` çağrısını tekrarlamanız gerekmez. Eklenen kullanıcıya `sudo` yetkisi
verilmez, hesap oluşturulmaz, parola/shell değiştirilmez.

Fonksiyon kalıcı grup üyeliğini ve kullanıcıya ait Git güven ayarını düzenler; **başka bir
kullanıcının zaten açık olan kabuğunun** gruplarını veya `umask` değerini değiştiremez.

## 6. Oturumu yenileme ve umask

Grup üyeliği değiştikten sonra her kullanıcı SSH bağlantısını kapatıp yeniden açmalıdır. Önceden
açık terminal, `tmux` ve servis süreçleri eski grup listesini taşımaya devam eder.

Yeni oturumda:

```bash
id -nG                       # çıktıda datarul görünmeli
umask 0007
cd /opt/datarul/install && git status --short
```

`umask 0007` bu kabuğu ve ondan başlatılan süreçleri etkiler; `cd` edilen dizine özgü değildir ve
oturum kapanınca sona erer. Diğer çalışmaların maskesini değiştirmemek için Datarul işlerini ayrı
bir oturumda ya da alt kabukta yapın:

```bash
(
    umask 0007
    cd /opt/datarul/install || exit 1
    git status --short
)
```

Kalıcı istiyorsanız — her kullanıcı **kendi hesabıyla, sudo kullanmadan**:

```bash
./set-umask.sh
umask 0007          # script çağıran kabuğu değiştiremez; bu oturum için elle verin
```

Bu seçim, o kullanıcının Datarul dışındaki yeni dosyalarını da etkiler. Zsh/Fish kullananlar kendi
kabuklarının başlangıç dosyasını düzenlemelidir. Yeni oturumda `umask` çıktısını kontrol edin:
başlangıç dosyasındaki erken bir `return` veya sistem politikası ayarı engelleyebilir.
([Bash başlangıç dosyaları](https://www.gnu.org/software/bash/manual/html_node/Bash-Startup-Files.html))

## 7. Doğrulama

Önce salt okunur rapor — gruba katılmış bir kullanıcının **yeni** oturumunda:

```bash
./check-access.sh
```

Beklenen: `BASE_DIR` ve `uploads` için `root:datarul`, `2770`, `drwxrws---`; `install` ilk kuran
kullanıcıya ve `datarul` grubuna ait; Git paylaşım ayarı `group`; güven listesinde tam `install`
yolu; oturumun gruplarında `datarul`.

Asıl kabul kontrolü, kullanıcılar arası yazmadır. İki kullanıcı da 5–6. bölümleri tamamlamış olmalı.

1. kullanıcı, yeni SSH oturumunda:

```bash
./test-group-write.sh
```

Komut geçici bir test dizini oluşturur, izinleri yazar ve 2. kullanıcının çalıştıracağı komutu
ekrana basar. 2. kullanıcı kendi yeni oturumunda:

```bash
./test-group-write.sh --finish /opt/datarul/uploads/.datarul-permission-test.XXXXXXXX
```

Beklenen: dizin `2770`, dosya `660`, ikisi de ortak grupta; 2. kullanıcı satır ekleyebiliyor. Test
dizini bu adımda kaldırılır. (Grup dizinlerinin ortak yazılabilir olması, dosyayı oluşturmayan bir
grup üyesinin bu dosyayı silmesine de izin verir — beklenen davranıştır.)

## 8. Tekrar çalıştırma ve işletim notları

| Durum | Davranış |
| --- | --- |
| Ortak grup mevcut | Yeniden oluşturulmaz; yerel grup olduğu ve GID'in sıfır olmadığı kontrol edilir. |
| Ana dizin / uploads mevcut | Dizin ve `root:ortak-grup` sahipliği doğrulanır; yalnızca bu dizinlere `2770` uygulanır. İç dosyalar değişmez. |
| install aynı origin ile mevcut | Klonlama atlanır; yerel Git paylaşım ayarı uygulanır. `pull`, `reset`, `clean` veya dosya silme yapılmaz. |
| install dosya, sembolik bağ, eksik klon veya farklı depo | İşlem hata ile durur; hedef otomatik silinmez veya değiştirilmez. |
| Kullanıcı zaten grupta | Üyelik ekleme atlanır; diğer gruplar korunur. |
| Git güven kaydı mevcut | Aynı tam yol için kayıt çoğaltılmaz; diğer kayıtlar korunur. |
| Ağ / yetki / disk hatası | Hazırlık durur. Önceki başarılı adımlar kalabilir; sorun giderildikten sonra tekrar çalıştırılır. |

İdempotanslık aynı parametrelerle **ardışık** çalıştırma içindir. Hazırlık sırasında aynı dizinlere
başka bir süreçle müdahale etmeyin. Yarım kalmış bir `install` dizini varsa içeriğini inceleyip
gerekirse başka bir ada taşıyın; script bu dizini otomatik silmez.

İzin bozulmasını giderirken `chmod -R 777` kullanmayın. Tek bir doğrulanmış, hassas olmayan dizin
için karşılığı şudur (toplu onarım adımı değildir):

```bash
sudo chmod g+rwX,g+s,o-rwx -- /opt/datarul/uploads
```

- Taşınan dosyalar mevcut grup ve modlarını koruyabilir; `cp -p`, `rsync -a` veya uygulamanın kendi
  izin ayarı beklenen mirası değiştirebilir. Mevcut dosyalar `umask` değişince düzelmez.
- `.env`, anahtar vb. hassas dosyalara topluca grup yazma izni uygulamayın.
- Bir servis veya container upload dosyalarını yazacaksa, süreçteki UID/GID ve dosya oluşturma
  maskesi de bu tasarımla uyumlu olmalıdır. İnsan kullanıcıyı gruba eklemek çalışan servisi
  yetkilendirmez; ayar değiştiğinde süreçlerin yeniden başlatılması gerekebilir.
- SELinux, varsayılan ACL veya ağ dosya sistemi kuralları varsa yalnızca Unix mod bitleri erişim
  için yeterli olmayabilir.

## 9. Doğrulama sınırı

Script'lerin tamamı ShellCheck (`-x`) kontrolünden geçti ve Debian 12 container'ında iki gerçek
kullanıcıyla (`ali`, `ayse`) uçtan uca çalıştırıldı: ilk kurulum, ikinci kez çalıştırma
(idempotanslık), kullanıcı ekleme ve tekrar ekleme, `check-access.sh` raporu, iki kullanıcılı yazma
testi, `set-umask.sh` (ve sudo ile çağrıldığında reddi), dar `sudo` politikasının anlaşılır hatayla
durması, farklı origin'li deponun reddi, geçersiz `BASE_DIR` değerlerinin ve yabancı bir dizinin
devralınmamasının reddi. Sonuçta `install` dizini `ali:datarul 2770`, dosyalar `660` oldu ve `ayse`
aynı dosyalara yazabildi.

Gerçek hedef sunucuda çalıştırma, gerçek uzak depodan klonlama ve Datarul uygulama kurulumu
yapılmamıştır. Sunucudaki kabul kontrolü 7. bölümdeki iki kullanıcı testidir.
