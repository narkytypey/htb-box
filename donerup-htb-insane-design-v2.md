# Donerup — HTB Insane Makine Tasarımı (v3 — Build Öncesi Doğrulanmış)

**Tarih:** 2026-08-24
**Zorluk:** Insane
**Tema:** Kurumsal "Enterprise SSO" portalı → Docker foothold → AD pivot → ADCS ESC9 → Domain Admin
**Platform:** Linux Docker host (DMZ web) + Windows DC VM (AD DS + AD CS)

## Bu sürüm v1'den ne değişti

v1 tasarımında LDAP injection adımı parolayı MD5 hash'leyip filtreye
ekliyordu. Bu, **ldap3 MOCK_SYNC ile ampirik olarak test edilip
yapısal olarak bypass edilemez olduğu kanıtlandı**: hash her zaman 32
hex karakterdir (metakarakter içermez), bu yüzden filter'in
`(info=<hash>)` klozu injection ile hiçbir OR'a çekilemiyor — AND'in
zorunlu kardeşi olarak kalıyor ve doğru şifre bilinmeden asla true
olamıyor. §4.1 buna göre düzeltildi ve **çalışan bir payload ile
doğrulandı**. Değişmeyen her şey (network topolojisi, rabbit hole,
ADCS zinciri, flag yerleşimi) v1 ile aynı.

## Bu sürüm v2'den ne değişti (v3)

v2'deki "doğrulanmış" payload'ın açıklaması **ampirik olarak yanlış
çıktı**: `ldap3` MOCK_SYNC ile yeniden test edildiğinde, payload'daki
`(|(sAMAccountName=*))` klozunun **tek-operandlı, dolayısıyla no-op
bir OR** olduğu ve gerçek bypass'ın aslında `(info=*)` üzerindeki bir
**presence-wildcard eşleşmesi** olduğu kanıtlandı (bkz. §12).
Pratik sonucu: `info` özniteliği taşıyan **her** migrate edilmiş
kullanıcı, gerçek OR-breakout hiç gerekmeden tek bir fullwidth `*`
ile bypass edilebiliyordu — bu Insane seviyesinin altında bir
karmaşıklık ve dokümandaki mekanizma açıklamasıyla çelişiyordu.

**Düzeltme (§4.1'e işlendi):**
- Ayrıcalıklı hesaplar (başta `administrator`) legacy migrasyona
  **dahil edilmedi** — `info` özniteliği bu hesaplarda hiç yok. Bu,
  hikâyeye gerçekçi bir gerekçeyle eklendi ("ayrıcalıklı hesaplar
  toplu migrasyondan hariç tutuldu").
- Gerçek bypass artık **`username` alanı üzerinden** kurulan,
  gerçekten iki-dallı ve template'in sabit `(info=...)` parçasını
  yutan bir OR breakout'a dayanıyor — `password` alanı tek başına bu
  yapıyı asla üretemez, çünkü template'in sabit `(info=` öneki
  password'ün ürettiği operandı her zaman `info` özniteliği üzerinde
  bir eşitlik/presence filtresine kilitler (ve LDAP'ta var olmayan
  bir özniteliğe filtre her zaman false'tur — değerden bağımsız).
- Yeni payload `ldap3` MOCK_SYNC ile 6 ayrı senaryoda doğrulandı:
  (1) `info` olmadan admin eşleşiyor, (2) yanlış kullanıcı adı
  eşleşmiyor, (3) gerçek migrate kullanıcının normal girişi
  bozulmuyor, (4) aynı kullanıcı için yanlış parola reddediliyor,
  (5) aynı teknik başka bir kullanıcıya (gerçek şifresi bilinmeden)
  genelleşiyor — yani hardcoded bir tesadüf değil, (6) **gerekircilik
  testi:** OR'ün ilk dalı false bir önermeyle değiştirildiğinde
  (`sAMAccountName=nosuchuser`) eşleşme **kayboluyor** — yani bu OR
  gerçekten sonucu taşıyor, dekoratif değil.

---

## 1. Tasarım İlkeleri

- **Guessing yok:** Her adım bir öncekinden enumerasyonla çıkarılabilir.
- **Adil rabbit hole:** Yanlış yola sapan oyuncuyu cezalandırmayan, açık ipuçlarıyla "burada değil" sinyali veren bir tuzak.
- **Pivot teknik olarak zorunlu:** AD segmentine erişim hikâye gereği değil, host iptables kurallarıyla fiziksel olarak enforce edilir.
- **Reset dayanıklı:** Network/route yapılandırması container yaşam döngüsünden bağımsız, host boot'ta kalıcı kurulur.
- **5+ adımlı zincir:** Insane kriterine uygun karmaşıklık, ama her halka takip edilebilir ve **her kritik adım build-öncesi test edildi** (bkz. §12).

---

## 2. Zincir Haritası (uçtan uca)

| # | Aşama | Teknik | Sonuç |
|---|-------|--------|-------|
| 0 | Recon | nmap | Web yüzeyi görünür, AD gizli |
| 1 | Web foothold #1 | LDAP injection → auth bypass (**düzeltilmiş model**) | Admin panel erişimi |
| 2 | Web foothold #2 | Jinja2 SSTI (blacklist bypass, doğrulandı) | Container'da RCE (düşük yetki) |
| 3 | Rabbit hole | Deprecated SQL servisi | Boş — açık ipuçlu tuzak |
| 4 | Gerçek keşif | Config'te `svc_ldap` bind cred | AD servis hesabı |
| 5 | Network keşif + pivot | 2. NIC + ligolo-ng tünel | AD segmentine erişim |
| 6 | AD enum | bloodhound-python + certipy | `svc_ldap` → kurban ACL |
| 7 | Escalation | ADCS ESC9 | Ayrıcalıklı hesap → DCSync |
| 8 | Domain Admin | DCSync | Tüm domain |

---

## 3. Recon & Giriş Yüzeyi

- **Açık portlar:**
  - `80/tcp` (HTTP) — redirect → 443
  - `443/tcp` (HTTPS) — asıl uygulama (Donerup Enterprise SSO)
  - `22/tcp` (SSH) — sadece gürültü/gerçekçilik; **hiçbir AD/servis kimlik bilgisiyle giriş çalışmamalı** (build sırasında cred-reuse testiyle doğrulanmalı — kasıtlı çıkmaz)
- **AD segmenti VPN'den erişilemez** — `nmap` ile AD IP aralığına doğrudan erişim başarısız olmalı (pivot zorunluluğu §6'daki iptables ile fiziksel olarak enforce edilir).
- **Web:** Login sayfasının alt bilgisinde/HTML yorumlarında "corporate LDAP directory" referansı — LDAP temasını erken ekiyor.

**Build durumu (2026-08-27):** Bu bölüm uzun süre **hiç inşa edilmemişti** —
build yalnızca `8080:5000` üzerinden düz HTTP gunicorn yayınlıyordu ve login
sayfasında hiçbir ipucu yoktu; dört plan dokümanının hiçbiri bu boşluktan söz
etmiyordu. Şimdi kapatıldı: `build/proxy/` (nginx + build-time self-signed
sertifika, `CN=donerup.htb`) 80'i 443'e 301 ile yönlendiriyor ve 443'ü
`web:5000`'e proxy'liyor; `web` artık host'a **hiç port yayınlamıyor**, yani
tek giriş proxy. Login sayfası da §3'ün istediği LDAP referansını taşıyor
(tema ipucu — açığın hangi alanda olduğunu ele vermiyor). **Doğrulanmadı:**
bu değişiklikler Docker'ı olmayan bir makinede yazıldı; `docker compose build`
ve gerçek bir TLS isteği hiç çalıştırılmadı (bkz. §11).

---

## 4. Web Zinciri (çok adımlı)

### 4.1 LDAP Injection → Auth Bypass — **DÜZELTİLMİŞ MODEL (v3)**

- **Kimlik doğrulama modeli (authentication-by-search):** Uygulama parolayı kurban-DN ile *bind* ederek doğrulamaz. `svc_ldap` ile bind olur, kullanıcı girdisiyle bir filter arar ve **"eşleşen kayıt döndü mü?"** sonucunu başarı sayar; rolü dönen kaydın `memberOf` özniteliğinden okur.
- **Filter şablonu:**
  ```
  (&(sAMAccountName=<username>)(info=<password>))
  ```
  `info` özniteliği, legacy SQL → LDAP göçünde taşınan **düz-metin eşdeğeri** bir legacy kimlik değeri tutar (aceleyle yapılmış, kötü ama gerçekçi migrasyon — hash YOK). Hem `username` hem `password` alanına **aynı** (zayıf) sanitize fonksiyonu uygulanır — "tek yerde sanitize ediyoruz" gerçekçi geliştirici kararı.
- **AD veri modeli (v3'te eklendi — kritik):** Migrasyon **sadece sıradan kullanıcıları** kapsadı; ayrıcalıklı hesaplar (başta `administrator`) toplu migrasyondan bilinçli olarak hariç tutuldu, dolayısıyla bu hesaplarda `info` özniteliği **hiç yok** (boş değil — tamamen absent). Bu, hem hikâye açısından gerçekçi bir güvenlik kararı hem de tasarımsal olarak zorunlu: `info` var olmayan bir öznitelikse, üzerindeki hiçbir filtre (eşitlik ya da presence) hiçbir zaman true olamaz — bu yüzden admin'e ulaşmak gerçek bir boolean-OR breakout gerektirir, tek-operandlı "süs" bir OR ya da presence-wildcard yetmez (bkz. aşağıdaki "neden password alanı tek başına yetmez").
- **Neden hash kullanılamaz:** Parola MD5/SHA gibi hash'lenip filtreye eklenirse, hash 32+ hex karakterden oluşur ve asla metakarakter içermez. `(info=<hash>)` klozu injection ile hiçbir zaman bir OR'a çekilemez — filter'in AND yapısında zorunlu bir kardeş olarak kalır ve doğru şifre bilinmeden hiçbir zaman true olamaz. Bu, ldap3 MOCK_SYNC ile ampirik olarak doğrulandı. **Parola filtreye düz-metin olarak girmelidir**, aksi hâlde adım kırılır.
- **Neden `password` alanı tek başına yetmez (v3'te düzeltilen hata):** `password`'ün template'teki sabit öneki her zaman `(info=` olduğu için, bu alana ne yazılırsa yazılsın üretilen operand her zaman `info` özniteliği üzerinde bir eşitlik/presence filtresidir — filtrenin **tipini** (eşitlik/presence'tan `|` bileşik filtresine) asla değiştiremez. `info` var olmayan bir özniteliğe filtre LDAP semantiğinde her zaman false döner, değerden bağımsız. Bu yüzden `password=*` (presence-wildcard) gibi bir kısayol admin'de **işlemez** — sadece `info`'su gerçekten dolu olan sıradan kullanıcılarda işler (bkz. aşağıdaki "yan etki" notu).
- **Gerçek bypass — `username` alanı üzerinden gerçek OR breakout:** `username`'in sabit öneki `(sAMAccountName=` olduğu için, bu alana `)` ile kendi klozunu erken kapatıp hemen ardından `(|(` ile kapatılmamış bir OR açan bir payload yazılırsa, template'in sabit `(info=...)` parçası bu açık OR'un **ikinci (önemsiz) dalı** olarak yutulur; OR'un **ilk dalı** (`sAMAccountName=administrator` tekrarı) ise true sağlayan gerçek daldır. Böylece outer AND'in ihtiyaç duyduğu "true", hiç `info`'ya bakmadan üretilmiş olur.
- **Zayıf sanitizasyon (blacklist sıralama hatası):**
  ```python
  ASCII_BLACKLIST = ["(", ")", "*", "\\", "\x00"]

  FULLWIDTH_MAP = str.maketrans({
      "\uff08": "(",  # FULLWIDTH LEFT PARENTHESIS
      "\uff09": ")",  # FULLWIDTH RIGHT PARENTHESIS
      "\uff0a": "*",  # FULLWIDTH ASTERISK
  })

  def sanitize(raw):
      cleaned = raw
      for ch in ASCII_BLACKLIST:
          cleaned = cleaned.replace(ch, "")
      return cleaned.translate(FULLWIDTH_MAP)   # <- blacklist'ten SONRA çalışır, bypass burada
  ```
  Blacklist ASCII `(`, `)`, `*`'ı siler, ama tam-genişlik (fullwidth, U+FF08/FF09/FF0A) varyantlarını görmezden gelir; normalizasyon bu adımdan **sonra** çalışıp fullwidth karakterleri gerçek metakaraktere çevirir. `|` blacklist'te değil, ASCII kalabilir. Sıralama hatası kasıtlıdır.
  **Build notu (v3):** `str.translate()` yalnızca `str.maketrans(...)` ile üretilmiş, ordinal-keyed bir tablo kabul eder — ham string-keyed dict verilirse **sessizce hiçbir şey yapmaz** (ampirik doğrulandı). `FULLWIDTH_MAP` her zaman `str.maketrans(...)` ile sarılmalı, aksi hâlde tüm fullwidth-bypass mekanizması çalışmaz.
- **DOĞRULANMIŞ ÇALIŞAN PAYLOAD (v3)** — `ldap3` MOCK_SYNC ile test edildi:
  ```
  username (attacker fullwidth gönderir):  administrator）（|（sAMAccountName=administrator
  username (normalize sonrası, ASCII):     administrator)(|(sAMAccountName=administrator

  password (attacker fullwidth gönderir):  ）
  password (normalize sonrası, ASCII):     )

  Üretilen filter:
  (&(sAMAccountName=administrator)(|(sAMAccountName=administrator)(info=)))
  → eşleşme başarılı — administrator'da `info` hiç yokken bile.
  ```
- **Doğrulanan sanity-check'ler (ldap3 MOCK_SYNC, 6 senaryo):**
  1. Yukarıdaki payload, `info`'su olmayan `administrator` kaydıyla eşleşiyor.
  2. Aynı payload yapısı yanlış/bilinmeyen kullanıcı adıyla eşleşmiyor (guessing gerektirmiyor, hedef kullanıcı adını bilmek gerekiyor).
  3. Injection'sız, gerçek parolayla sıradan bir migrate kullanıcının (`info`'su dolu) normal girişi bozulmuyor.
  4. Aynı injection'sız kullanıcı için yanlış parola reddediliyor.
  5. Aynı teknik, gerçek parolası bilinmeden başka bir kullanıcıya (`jdoe`) uygulandığında da çalışıyor — yani hardcoded bir tesadüf değil, genel bir teknik.
  6. **Gerekircilik testi:** OR'ün ilk dalındaki `sAMAccountName=administrator` yanlış bir değere (`nosuchuser`) değiştirilirse eşleşme kayboluyor — OR gerçekten sonucu taşıyor, dekoratif değil.
- **Yan etki (kasıtlı, tasarımın parçası):** `info`'su dolu sıradan kullanıcılarda (`jdoe` gibi) tek başına `password=*` (fullwidth) presence-wildcard'ı da işler — ama bu hesaplar admin paneline erişemez (bkz. aşağıdaki rol notu), dolayısıyla oyuncuyu yanlış yola sokmaz; en fazla "LDAP injection burada gerçek, ama bu hesap işime yaramıyor" sinyali verir.
- **Rol gate'i (netlik için eklendi):** Admin paneli, dönen kaydın `memberOf` özniteliğinde ayrıcalıklı bir grup (örn. `Domain Admins` ya da eşdeğeri) gerektirir; sıradan authenticated bir kullanıcı (`jdoe` gibi) panele erişemez.
- **Zorluk (Insane):** `|` karakteri blacklist'te değil (ASCII kalabilir); sadece `(`, `)` fullwidth kaçışı gerektiriyor (bu payloadda `*` artık kullanılmıyor). Hata mesajları minimal → oyuncu blind/differential yaklaşımla ilerlemeli; ayrıca injection'ın **hangi alanda** (username, password'ün aksine) işe yaradığını keşfetmesi gerekiyor.
- **Sonuç:** Admin paneline kimlik doğrulanmış erişim.

### 4.2 Admin Panel → Jinja2 SSTI — **bypass mekanizması doğrulandı**

- **Özellik:** Admin panelinde "rapor şablonu" düzenleme alanı, `render_template_string` ile işleniyor (Flask/Jinja2, sandbox'sız).
- **Blacklist:** `__`, `class`, `mro`, `subclasses`, `import`, `os.`, `popen`, `system`, `eval`, `exec`, ` ` (boşluk) — tek geçişli substring kontrolü, **sadece `{{ ... }}` / `{% ... %}` ifade bloklarının içine uygulanır** (raw metnin tamamına değil). **Build notu (v3):** Kontrol dokümanın tamamına uygulanırsa özellik kullanılamaz hâle gelir — herhangi bir cümle içeren normal bir rapor şablonu bile boşluk içerdiği için reddedilir (ampirik doğrulandı). Regex ile `\{\{.*?\}\}|\{%.*?%\}` bloklarını çıkarıp blacklist'i sadece bu fragment'lara uygulamak hem gerçekçiliği hem de kastedilen zorluğu korur.
- **DOĞRULANMIŞ BYPASS MEKANİZMASI** (gerçek Jinja2 ile test edildi):
  - **Token bölme:** Jinja'nın `~` concat operatörüyle yasaklı kelimeler parçalanır — örn. `__class__` yerine `'_'~'_cla'~'ss_'~'_'` gibi bir ifade Jinja çalışma anında birleşir ama blacklist'in taradığı ham metinde "class" veya "__" contiguous olarak **görünmez** (tırnak/tilde karakterleri araya giriyor). **Not:** erişim dot-notation (`''.__class__`) ile değil, **subscript** ile yapılmalı — Jinja'da `.` sonrası bir literal identifier token'ı gerektirir, dinamik/concat edilmiş bir string ile attribute adı veremez. Doğru biçim: `''['_'~'_cla'~'ss_'~'_']`. Bu teknikle `<class 'str'>` sonucu alınarak bypass **çalışır durumda doğrulandı**.
  - **Boşluk engelini aşma:** Blacklist'te boşluk (` `) da yasaklı. Jinja `{% set %}` gibi ifadeler bir anahtar kelime ile değişken adı arasında whitespace gerektirir, ama bu whitespace **tab karakteri (`\t`) olabilir** — blacklist yalnızca literal `' '` karakterini arıyor, tab'ı yakalamıyor. `{%set\tx=...%}` biçiminde yazılan ifadeler blacklist'i geçiyor.
- **Kalan (build'e özgü) adım:** Tam RCE zinciri için `''.__class__.__mro__[1].__subclasses__()` üzerinden dosya-okuma/komut-çalıştırma yeteneği olan bir gadget class'ının **indeksini** bulmak gerekiyor — bu indeks Python/Jinja2 sürümüne göre değişir, evrensel olarak sabitlenemez. Build ortamında interaktif olarak (`subclasses()` çıktısını grep'leyerek) belirlenmeli. Bypass mekanizmasının kendisi (blacklist atlatma) doğrulandı; sadece son gadget seçimi ortama özgü.
- **Sonuç:** Container içinde komut çalıştırma → reverse shell → düşük yetkili `appuser`.

---

## 5. Container Foothold & Adil Rabbit Hole

- **Ortam:** Shell bir **Docker container** içinde düşer. İpuçları: `/.dockerenv`, kısıtlı process listesi, `appuser` düşük yetki. Container'da ağır pentest aracı **yok** (BloodHound, certipy, tam nmap yok) → tünel zorunlu.
- **Rabbit hole — Deprecated SQL:**
  - Container'dan erişilebilen (ama internete/VPN'e AÇIK OLMAYAN — sadece aynı Docker network'ünde) bir MySQL servisi: `legacy-auth-db`.
  - Zayıf, kırılabilir root parolası (örn. `Summer2019!`) — kırılırsa içeride yalnızca dummy/geçersiz kayıtlar var (MD5 hash'li eski test kullanıcıları, gerçek AD hesaplarıyla eşleşmiyor).
  - **Adil ipucu:** Container içinde bir `CHANGELOG.md` / migrasyon notu dosyası, `legacy-auth-db`'nin "deprecated — migrated to LDAP" olduğunu ve gerçek kimlik doğrulamanın artık LDAP `info` özniteliği üzerinden yapıldığını açıkça belirtir. Dikkatli oyuncu zaman kaybetmeden asıl config dosyasına yönelir.
  - **Kritik izolasyon kuralı:** `legacy-auth-db`, AD segmentine giden network'e (`internal-ad`) **hiçbir şekilde bağlı olmamalı** — rabbit hole'un gerçek path'e sızmaması garanti edilmeli.
- **Gerçek path — Bind credential:**
  - Uygulama config'inde (`.env` veya `ldap.conf`) AD'ye bind için kullanılan servis hesabı:
    ```
    LDAP_BIND_DN=CN=svc_ldap,OU=Service Accounts,DC=donerup,DC=htb
    LDAP_BIND_PASSWORD=<güçlü ama düz metin>
    ```
  - Bu "rastgele cred bulma" değil: web app'in LDAP auth yapabilmesi için bu hesap zaten orada olmak zorunda.
  - `appuser`'ın bu config dosyasını okuyabildiği, container'a düşürülecek pivot ajanını (ör. ligolo-ng agent, root gerektirmez) çalıştırabileceği yazılabilir bir alanı olduğu build sırasında doğrulanmalı. **In-container privesc gerekmez ve eklenmemeli** — amaçlanan yolu kırar.

---

## 6. Network Keşif & Pivot

### 6.1 Topoloji

```
[VPN]
  │
[DMZ bridge]  (docker network: dmz, dışa açık — 80/443 host'a mapli)
  │
web container (Flask)  ── 2. NIC ──► [internal-ad bridge] (docker network: internal-ad, izole)
  │
  └── legacy-auth-db (rabbit hole) — SADECE dmz'de, internal-ad'e bağlı DEĞİL
                                          │
                        Docker host iptables FORWARD zinciri
                        (yalnızca internal-ad subnet → AD VLAN, VPN client subnet DROP)
                                          │
                                     [AD VLAN]
                                          │
                              Windows DC VM (AD DS + AD CS)
```

### 6.2 Keşif İpuçları (container içinden)
- `ip addr` / `ip route` → ikinci arayüz ve `internal-ad` subnet'i.
- `/etc/hosts` veya `resolv.conf` → `dc01.donerup.htb` referansı.
- AD host'a erişim internal-ad üzerinden çalışır, VPN'den çalışmaz.

### 6.3 Enforcement (tasarımın kritik parçası — hikaye değil, teknik zorunluluk)
- Docker host'ta iki bridge network: `dmz` ve `internal-ad`. `internal-ad`, Docker'ın `internal: true` seçeneğiyle kendi otomatik NAT/masquerade'ini devre dışı bırakır — gerçek AD VLAN'a geçiş tamamen host'un elle kurduğu iptables kurallarına bağlıdır.
- Host iptables `FORWARD` zinciri:
  - `internal-ad` bridge'inden AD VLAN subnet'ine → **ACCEPT** (ve dönüş trafiği).
  - VPN client subnet'inden (HTB VPN aralığı) AD VLAN subnet'ine doğrudan → **DROP**.
- Sonuç: oyuncu AD'ye ulaşmak için container üzerinden pivot etmek **paket seviyesinde** zorunda kalır.
- Bu kurallar, Docker'ın kendi network yönetiminden bağımsız olarak host boot'ta (systemd, `After=docker.service`, idempotent script) kurulmalı — reset dayanıklılığı için.

### 6.4 Pivot Aracı
- **ligolo-ng** tercih edilir (SOCKS yerine gerçek TUN arayüzü) — Kerberos/LDAP/ADCS trafiği SOCKS proxy'de sorun çıkarabildiği için tam L3 tünel gerekli.
- Oyuncu: container'a `ligolo agent` (statik Go binary, root gerekmez) düşürür, kendi Kali'sinde `ligolo proxy` + route ekler → AD subnet'i Kali'den doğrudan erişilebilir hâle gelir.
- Tünel üzerinden `bloodhound-python`/`certipy` için `donerup.htb`/`dc01` ad çözümü `-ns <DC_IP>` ile veya resolver yapılandırmasıyla netleştirilmeli (build'de doğrulanacak).

---

## 7. AD Enumerasyon

- Tünel üzerinden `svc_ldap` kimliğiyle:
  ```
  bloodhound-python -u svc_ldap -p <pass> -d donerup.htb -c All -dc dc01.donerup.htb
  certipy find -u svc_ldap -p <pass> -dc-ip <DC_IP> -vulnerable -stdout
  ```
- **BloodHound path (amaçlanan):**
  - `svc_ldap` → bir kurban hesabı (`svc_backup`) üzerinde **`GenericWrite`**.
  - **Neden dar `WriteProperty` yetmez:** ESC9 için kurban *olarak* sertifika enroll etmek gerekir; bunun için önce kurbanın kimliğini shadow credentials (`msDS-KeyCredentialLink` yazma) ile ele geçirmek şarttır. Sadece `userPrincipalName`'e scope'lanmış bir `WriteProperty`, UPN'i değiştirmeyi sağlar ama `msDS-KeyCredentialLink` yazmayı **sağlamaz**. Bu yüzden edge hem UPN hem `msDS-KeyCredentialLink` yazımını kapsayan **`GenericWrite`** olmalı.
  - dsacls ile kurulum: `dsacls "CN=svc_backup,OU=Service Accounts,DC=donerup,DC=htb" /G "DONERUP\svc_ldap:GW"`

---

## 8. ADCS ESC9 → Domain Admin

### 8.1 Ortam Koşulları (DC üzerinde)
- Enterprise CA rolü DC'de kurulu, "User" şablonundan çoğaltılmış bir `DonerupUserAuth` şablonu CA'ya yayınlı.
- **ESC9 koşulu:**
  - Şablonun `msPKI-Enrollment-Flag` değerine `CT_FLAG_NO_SECURITY_EXTENSION` (`0x80000`) bayrağı eklenmiş — sertifikada `szOID_NTDS_CA_SECURITY_EXT` uzantısı yok.
  - DC'de `StrongCertificateBindingEnforcement = 1` (registry: `HKLM\SYSTEM\CurrentControlSet\Services\Kdc`) — zayıf/uyumluluk modu (varsayılan güvenli değer `2`'dir, kasıtlı olarak zayıflatılmalı).
  - `Authenticated Users` gruba şablon üzerinde Enroll hakkı (extended right GUID `0e10c968-78fb-11d2-90d4-00c04f79dc55`) verilmiş.

### 8.2 Amaçlanan Yol
1. **Kurban kimliğini ele geçir (zorunlu ön adım):** `GenericWrite` ile `svc_backup`'ın `msDS-KeyCredentialLink`'ine shadow credential yaz (`certipy shadow auto`) → kurbanın NT hash'ini/TGT'sini al.
2. Kurbanın `userPrincipalName`'ini ayrıcalıklı bir hesaba çevir (örn. `administrator`, `@domain` eki olmadan `sAMAccountName` eşlemesi için).
3. Kurban kimliğiyle, güvenlik-uzantısız şablondan sertifika enroll et (`certipy req`).
4. UPN'i eski değerine geri al (iz bırakmamak, eşlemenin `administrator`'a çözülmesi için).
5. Sertifikayla kimlik doğrula (`certipy auth`) → zayıf binding sayesinde `administrator` olarak TGT/NT hash.
6. **DCSync** (`secretsdump`) → `krbtgt` + tüm domain hash'leri.

### 8.3 ESC10 — ikincil yol, ayrı doğrulanmalı
- Aynı UPN-swap mantığı, Schannel (`CertificateMappingMethods` registry) üzerinden. **ESC9 birincildir**; ESC10 ayrı bir build adımında test edilmeden ikisinin birlikte çalıştığı varsayılmamalı — `StrongCertificateBindingEnforcement` (Kerberos/PKINIT yolu) ve `CertificateMappingMethods` (Schannel yolu) birbirini etkileyebilir.

### 8.4 Sonuç
- Domain Admin / `krbtgt`. Kök kanıt (root flag) DC üzerinde.

---

## 9. Fiziksel Bileşenler (build envanteri)

| Bileşen | Rol | Notlar |
|---------|-----|--------|
| Linux Docker host | DMZ + pivot köprüsü | 2 bridge network, iptables enforcement, systemd persist |
| `web` container | Flask SSO app | LDAP injection (düz-metin, hash YOK, ayrıcalıklı hesaplarda `info` yok) + Jinja2 SSTI, config'te `svc_ldap` |
| `legacy-auth-db` container | Rabbit hole | Dummy data, migrasyon ipucu, internal-ad'e bağlı DEĞİL |
| Windows DC VM | AD DS + AD CS | `donerup.htb`, ESC9 koşulları, zayıf cert binding |

- **Member server: yok.** Tüm AD sömürüsü tünelden Linux araçlarıyla yapılabilir → topoloji sadeleşir.

---

## 10. Flag Yerleşimi

- **user.txt:** container foothold sonrası, `appuser` home dizini (Bölüm 5).
- **root.txt:** DC üzerinde, Domain Admin sonrası (Bölüm 8).

---

## 11. Açık Sorular / Build Aşamasına Bırakılanlar

- **LDAP injection:** v3 payload'ı (username-alanı OR breakout, `administrator`'da `info` yok) ldap3 MOCK_SYNC ile 6 senaryoda doğrulandı — gerçek AD/ldap3 canlı bağlantısıyla (mock değil) build sırasında **tekrar** doğrulanmalı; mock'un filter parser'ı gerçek AD ile %100 birebir olmayabilir. Ayrıca AD provisioning script'inin `administrator`'a **hiç** `info` yazmadığından (boş string değil, tamamen absent) emin olunmalı.
- **SSTI:** Blacklist bypass mekanizması (concat + tab) gerçek Jinja2 ile doğrulandı. Tam RCE için `__subclasses__()` gadget indeksi build ortamına özgü, orada interaktif belirlenmeli.
- **ESC9:** Şablon/CA yapılandırması build'de gerçek DC üzerinde `certipy find -vulnerable` ile doğrulanmalı.
- **ESC10 — KAPANDI (2026-08-28, gerçek DC üzerinde):** `build/exploit/run-esc10-check.sh` ESC9'dan sonra ayrı adımda çalıştırıldı ve **PASS** verdi — aynı UPN-swap sertifikası LDAPS/Schannel üzerinden de `DONERUP\Administrator` olarak kimlik doğruluyor. Önemli bulgu: DC'de `CertificateMappingMethods` registry değeri **hiç ayarlanmamış** (Windows varsayılanı, `NOT SET`/`0x0`) ve buna rağmen ESC10 çalışıyor — yani bu build'de ESC10'un çalışması için ekstra bir Schannel yapılandırması **gerekmiyor**, tasarımın ima ettiği "registry değişikliği şart" varsayımı yanlıştı. ESC9 birincil, doğrulanmış yol olmaya devam ediyor; ESC10 artık redundant bir ikincil yol olarak da doğrulanmış durumda.
- **Tünel DNS:** `donerup.htb`/`dc01` çözümü için `-ns`/resolver netleştirilmeli.
- **Reset dayanıklılığı:** Host-boot network script'i ile Docker'ın kendi bridge yönetimi arasındaki sıralama (`After=docker.service`) ve idempotency build'de test edilmeli.
- **SSH (22) gerçek çıkmaz:** Hiçbir AD/servis cred'i ile SSH girişi olmamalı — cred-reuse testiyle doğrulanmalı.
- **TLS proxy (§3) — YENİ, hiç çalıştırılmadı (2026-08-27):** `build/proxy/`
  imajı hiç `docker build` edilmedi, nginx config'i hiç yüklenmedi, 80→443
  redirect'i ve 443→`web:5000` proxy'si hiç gerçek bir istekle denenmedi —
  bu makinede Docker yok. Build ortamında ilk iş: `docker compose build proxy`,
  `docker compose up -d`, sonra `python3 web/tests/integration_smoke.py`
  (varsayılan artık `https://localhost`, self-signed olduğu için doğrulama
  kapalı). Özellikle şu iki şey ampirik olarak doğrulanmalı: (1) full-width
  Unicode taşıyan LDAP/SSTI payload'ları nginx üzerinden **bozulmadan**
  geçiyor mu, (2) `web`'in host'a port yayınlamaması `full-chain-replay.sh`
  dışında bir şeyi kırıyor mu.

---

## 12. Bu Sürümde Yapılan Doğrulamalar (özet)

| Doğrulama | Yöntem | Sonuç |
|-----------|--------|-------|
| Hash'li LDAP filter bypass edilebilir mi? | ldap3 MOCK_SYNC, dengeli+dengesiz payload | **HAYIR** — yapısal olarak imkansız (kanıtlandı, tasarım değiştirildi) |
| v2 payload'ının OR klozu gerçekten mi işe yarıyor, yoksa dekoratif mi? | ldap3 MOCK_SYNC, `info` var/yok karşılaştırması | **DEKORATİF** — v2'nin "OR breakout"u tek-operandlı no-op; gerçek bypass `info=*` presence-wildcard'ıydı (v3'te düzeltildi) |
| `password` alanı tek başına gerçek bir OR breakout üretebilir mi? | ldap3 MOCK_SYNC, `info` yokken test | **HAYIR** — sabit `(info=` öneki filtre tipini asla değiştiremiyor |
| `username` alanı üzerinden gerçek OR breakout, `info` hiç yokken çalışıyor mu? | ldap3 MOCK_SYNC, 6 senaryo (eşleşme, yanlış kullanıcı, normal giriş, yanlış parola, genelleme, gerekircilik testi) | **EVET** — tümü beklenen sonucu verdi |
| SSTI blacklist (`__`, `class` vb.) atlatılabilir mi? | Gerçek Jinja2, `~` concat | **EVET** |
| SSTI boşluk yasağı atlatılabilir mi? | Gerçek Jinja2, tab karakteri | **EVET** |
| Tam SSTI→RCE gadget zinciri | Gerçek Jinja2 | Kısmi — mekanizma çalışıyor, gadget indeksi ortama özgü |
