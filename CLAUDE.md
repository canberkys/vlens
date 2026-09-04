# vLens - Claude Code Project Context

## Proje Özeti
vCenter/ESXi ortamlarından envanter bilgisi toplayan, hızlı, modern, native
SwiftUI desktop uygulaması — RVTools'tan esinlenildi, ama sadece bir port
değil: RVTools'ta olmayan birden fazla kendine özgü özelliği var (vPerformance,
Snapshot/Compare, PDF rapor, VMSA farkındalığı). "RVTools'un alternatifi"
demek yerine bu şekilde çerçevelenmeli — kullanıcı notu (2026-09-04).
`~/Documents/Projects/vInventory` (Tauri/React, Windows-only, askıda) ile
ilgisi yok — ayrı, macOS-first bir proje.

Detaylı mimari gerekçe ve tam MVP kapsamı:
`~/.claude/plans/swirling-painting-snail.md`

RVTools'un tam alan/tab/health-check referansı (145 sayfalık resmi Dell PDF, metne
çevrilmiş):
`/private/tmp/claude-1487936373/-Users-c-kilicarsl/701b4010-67e7-4fef-a0bc-23ad902563cc/scratchpad/rvtools.txt`

vLens'in kendi kapsamlı referansı (RVTools'un PDF'ine benzer, alan/tab/mimari
dokümanı): `docs/vLens-Reference.md`

## Teknoloji Stack

| Katman | Teknoloji |
|--------|-----------|
| Desktop Framework | SwiftUI + AppKit, SwiftPM, Swift 6.1+ |
| vSphere client | Gömülü Go/govmomi helper (`helper/`), JSON stdin/stdout protokolü |
| Credential storage | Keychain (Docky'nin `CredentialStoreProtocol` pattern'i) |
| Data grid | SwiftUI native `Table` (perf yetersiz kalırsa NSTableView'a geç) |
| Export | CSV (`CSVExport.swift`) ve XLSX (`XLSXExport.swift`, ZIPFoundation) — ikisi de yapıldı |
| Arama | Her tab'da tek metin kutusu, `Searchable` protokolü (`Searchable.swift`) |
| Saved connections | JSON (`ConnectionProfileStore`, Application Support) + Keychain (parola) |

## VPN olmadan gerçek entegrasyon testi: vcsim

Kullanıcının vCenter'a VPN erişimi Nw-Sec tarafından kesildi (2026-09-03). Bu bir
blocker değil: govmomi'nin kendi `simulator` paketi (gerçek `vcsim` CLI'ının motoru)
localhost'ta gerçek bir SOAP/PropertyCollector sunucusu ayağa kaldırıyor —
`helper/vcsim/main.go`. `vlens-helper` buna karşı gerçek login+collection yapıyor,
mock değil. `go run ./vcsim` (veya derlenmiş `vcsim/vcsim` binary'si) ile başlat,
çıktısındaki URL'i (`https://127.0.0.1:PORT/sdk`) `user`/`pass` credential'larıyla
vLens'in Connect ekranına gir. İlk bağlantıda sertifika onay sheet'i çıkacak
(cert-trust-on-first-use), gerçek bir self-signed vCenter sertifikasında yapacağın
gibi onayla.

Bu sayede prod dışındaki her şey gerçek anlamda test edilebiliyor. 1200 VM / 34 host
/ 4 cluster / 12 datastore ölçeğinde `collectAll` **0.58 saniyede** tamamlandı — RVTools
ölçeğinde performans endişesi yok.

## Neden Go/govmomi helper (Swift SOAP client değil)?

RVTools verisinin ~%95'i SOAP tabanlı vim25 PropertyCollector'dan geliyor, sadece
tag'ler için CIS REST kullanıyor. Swift'in bakımı yapılan bir vSphere SDK'sı yok.
govmomi (Terraform/Packer/k8s'in kullandığı, olgun kütüphane) `.app` içine gömülü bir
helper binary olarak kullanılıyor — Docky da protokol katmanı için libssh2/Citadel
gibi Swift-olmayan bağımlılıklar gömüyor, bu yeni bir pattern değil.

## Dosya Yapısı

```
vLens/
├── Package.swift
├── Resources/               # Info.plist, vLens.entitlements, AppIcon.icns/.iconset — .app paketleme için
├── scripts/release.sh       # build → bundle → codesign → (varsa) notarize → DMG, tek script
├── Sources/
│   ├── vLens/              # SwiftUI app target
│   │   ├── vLensApp.swift        # NSApplicationDelegateAdaptor (`swift run` focus fix'i) +
│   │   │                          # ConnectionViewModel'i WindowGroup/Settings scene'leri
│   │   │                          # arasında paylaştırır
│   │   ├── ContentView.swift     # tab bar + demo banner + connect ekranı + cert onay sheet'i
│   │   ├── PreferencesView.swift # Cmd+, — vHealth eşikleri (RVTools'un Health Properties'i)
│   │   ├── AppTab.swift          # 27 tab'ın enum'u
│   │   ├── ConnectionViewModel.swift
│   │   ├── HelperLocator.swift
│   │   ├── ReportView.swift      # yönetici raporu (PDF) — SwiftUI Charts + stat kartları
│   │   ├── ReportRenderer.swift  # ImageRenderer → CGContext → tek sayfa PDF
│   │   ├── HelpView.swift        # native in-app Help (Help menüsü artık dışarı çıkmıyor)
│   │   ├── AboutView.swift       # custom About paneli (varsayılan boş panel yerine)
│   │   ├── AppVersion.swift      # Bundle.main → dev fallback (HelperLocator'la aynı desen)
│   │   ├── FeedbackView.swift    # Help menüsünden "Send Feedback…" — mailto: taslağı, backend yok
│   │   ├── Tutorial.swift        # TutorialID + .tutorialPopover(...) + WelcomeOverlayView
│   │   └── Tabs/                 # her tab için ayrı Table view (VInfoTabView, VCpuTabView, ...)
│   └── vLensCore/          # Paylaşılan veri katmanı (app + gelecekteki CLI)
│       ├── Models/          # VirtualMachineInfo, VMCpuInfo, VMMemoryInfo, VMDiskInfo,
│       │                     # VMSnapshotInfo, VMToolsInfo, HostInfo, DatastoreInfo,
│       │                     # ClusterInfo, HealthCheckResult — hepsi rvtools.txt'teki
│       │                     # gerçek kolon tanımlarından, temsili bir alt küme
│       ├── Credentials/    # Keychain credential store
│       ├── Helper/         # Go helper ile JSON protokolü + Process client
│       ├── Demo/DemoData.swift   # 40 VM + tüm tab'lar için tutarlı mock veri üretici
│       ├── HealthCheckEngine.swift  # RVTools'un 24 vHealth kuralından 10'u, gerçek hesaplama
│       ├── HealthCheckPreferencesStore.swift  # eşikleri UserDefaults'a kaydeder
│       ├── SnapshotStore.swift     # InventorySnapshot geçmişi, Application Support'ta JSON
│       ├── SnapshotPreferencesStore.swift  # Compare panelinde hangi metriklerin gösterileceği
│       ├── AutomationSchedule.swift  # Faz 10B — tek bir zamanlama (profil/aksiyon/gün/saat) +
│       │                               # AutomationPreferencesStore (UserDefaults'ta JSON)
│       ├── ExportTab.swift         # tab anahtarı → CollectedInventory alanı eşlemesi + CSV/XLSX
│       │                            # render (vlens-cli VE Preferences'ın Automation picker'ı paylaşıyor)
│       ├── TutorialStore.swift     # hangi tutorial/coachmark'ların gösterildiği (UserDefaults)
│       ├── VMSAClient.swift        # Broadcom'un resmi güvenlik danışmanlığı JSON API'si (Go helper'a gitmiyor)
│       ├── CertificateTrust.swift  # trust-on-first-use (Docky'nin HostKeyTrust'ından uyarlandı)
│       ├── Searchable.swift      # her model için searchableText + .matches(query)
│       ├── CSVExport.swift       # her model için CSVExportable + CSVWriter
│       ├── XLSXExport.swift      # ZIPFoundation üzerine minimal OOXML writer
│       ├── ConnectionProfileStore.swift  # kayıtlı bağlantılar (host/user), parola Keychain'de —
│       │                                  # ConnectionProfile.keychainReferenceID(for:) burada,
│       │                                  # GUI ve vlens-cli'ın Keychain'de aynı girdiyi bulması için
│       └── FieldComparator.swift   # sıralama comparator'ı (app değil Core'da — sadece
│                                     # Foundation'a bağımlı, SwiftUI değil, bu yüzden test edilebilir)
├── Sources/vLens/ExportPanel.swift  # NSSavePanel ile CSV/XLSX kaydetme (app layer, @MainActor)
├── Sources/vLens/LaunchdScheduler.swift    # Faz 10B — AutomationSchedule'ı gerçek bir launchd
│                                             # plist'ine çevirip yükler/kaldırır (launchctl bootstrap/bootout)
├── Sources/vLens/AutomationCLILocator.swift  # HelperLocator'la aynı desen — paketlenmiş .app'te
│                                               # Contents/MacOS/vlens-cli'ı bulur
├── Sources/vLensCLI/        # `vlens-cli` — headless snapshot/export (Faz 10A)
│   ├── main.swift                # komutlar: list-profiles, list-tabs, snapshot, export
│   └── CLIHelperLocator.swift    # HelperLocator'ın bare-executable versiyonu (Bundle.main yok)
├── Tests/vLensCoreTests/    # decode + HealthCheckEngine + CSVWriter + XLSXWriter +
│                             # FieldComparator + Searchable + ConnectionProfileStore +
│                             # CertificateTrust + HealthCheckPreferencesStore + SnapshotStore +
│                             # InventorySnapshotMetrics + TutorialStore + VMSAClient testleri (58 test)
├── docs/vLens-Reference.md  # RVTools PDF'i tarzında kapsamlı proje referansı
└── helper/                 # Go module (govmomi)
    ├── go.mod
    ├── main.go              # `collectAll` (24 collector, artık vCenter About bilgisi
    │                          # de dahil — bedava, login sonrası zaten mevcut) +
    │                          # `getCertificate` + `collectPerformance` action (kendi
    │                          # login'i, ayrı tutulan tek istisna — bkz. §3 mimari notu)
    ├── vcsim/main.go        # dev-only: localhost'ta gerçek vCenter simülatörü (VPN gerekmez)
    ├── vcsim/mksnap/main.go # dev-only: vcsim'de test snapshot'ı oluşturur (snapshot-size testi için)
    └── vcsim/mkvapp/main.go # dev-only: vcsim'de gerçek bir VirtualApp instance'ı oluşturur (vApp testi için)
```

## Build & Run

```bash
# Swift tarafı
swift build
swift test
swift run vLens             # dev modunda çalıştırır, helper'ı ../helper/vlens-helper'dan bulur

# Go helper
cd helper
go build -o vlens-helper .

# Yerel vCenter simülatörü (VPN/gerçek vCenter gerekmez)
go build -o vcsim/vcsim ./vcsim && ./vcsim/vcsim

# CLI (Faz 10A) — kayıtlı bir bağlantı gerektirir (GUI'de bir kere
# "Save this connection to Keychain" ile bağlanılmış ve sertifikası
# onaylanmış olmalı)
swift run vlens-cli list-profiles
swift run vlens-cli snapshot --profile <ad> [--label <metin>] [--full-detail]
swift run vlens-cli export --profile <ad> --tab vinfo --format csv --output ~/Desktop/vinfo.csv
```

`ConnectionViewModel` helper binary'yi şu sırayla arıyor: app bundle Resources →
`VLENS_HELPER_PATH` env var → dev fallback (`helper/vlens-helper`, proje kökünde
`go build` ile üretilmiş olmalı).

## Durum (2026-09-03, son maddeler 2026-09-05)

- [x] **(2026-09-05) #11: XLSX hücre tipi artık kolon tanımından geliyor,
      değerden sniff edilmiyor (v1.3.3)** — kullanıcının sıralamasında #8'den
      sonraki adım. Eski kod "değer Int/Double olarak parse oluyor mu"
      testiyle karar veriyordu ve kod içindeki "deliberately conservative"
      yorumuna rağmen bu gerçekte doğru değildi: `Int("00123")` başarıyla
      123'e parse oluyor (baştaki sıfırlar kayboluyor), `Double("8.0")` da
      8'e parse oluyor (iki parçalı versiyon string'i sayıya dönüşüyor) —
      ikisi de review'ın verdiği somut örneklerdi. Düzeltme: `CSVExportable`
      protokolüne yeni bir `xlsxColumnTypes: [XLSXColumnType]` (`.text`/
      `.number`, `csvHeader` ile birebir aynı sırada) eklendi — 28 conformance'ın
      (23 model + `InventorySnapshot`'ın dinamik metrik kolonları +
      `SnapshotsTabView`'daki `CompareRow`) her biri kendi kolonlarının
      gerçek tipini tek tek deklare ediyor. `XLSXWriter` artık değere hiç
      bakmadan (sadece boş/parse-edilemez bir `.number` hücresi için text'e
      düşme güvenlik ağı hariç) bu deklarasyona göre hücre tipi yazıyor. 2
      yeni regresyon testi (`00123` VM adı ve `8.0` vApp versiyonu, ikisi de
      gerçek bir zip'ten çıkarılan XML'e karşı doğrulandı — text kaldıklarını
      VE aynı satırdaki gerçek sayısal bir kolonun (CPUs) hâlâ sayı olarak
      yazıldığını kanıtlıyor). Bu değişiklik ayrıca gelecekteki bir "tüm
      envanteri tek dosyaya aktar" özelliği için de temel oluşturuyor — her
      kolonun tipi zaten tek bir yerde deklare edilmiş oluyor. `swift
      build`/`swift test` temiz (65/65, +2 yeni test). **Sırada #5
      (bağlantı yaşam döngüsü: refresh/disconnect/switch), sonra #9
      (otomasyon)**.
- [x] **(2026-09-05) #8: Performans toplama artık kapsamını raporluyor +
      çoklu disk metrikleri tanımlı bir kuralla birleştiriliyor (v1.3.2)** —
      kullanıcı kalan 4 P2 için veri doğruluğuna öncelik veren bir sıra
      önerdi ("kullanıcıya başarılı görünen ama eksik/değiştirilmiş veri
      sunmaları" nedeniyle önce bunlar); #8 ile başlandı. Batched `QueryPerf`
      bir batch'te başarısız olduğunda o ana kadar toplanan sonuç sessizce
      "tam sonuç" gibi dönüyordu — artık her `collectPerformance`
      çağrısında yeni bir `performanceCoverage` (requested/collected VM
      sayısı, `complete`, ve tamamlanmadıysa gerçek hata) dönüyor,
      vPerformance tab'ı bunu "Collected N of M VMs — request failed
      partway through: ..." olarak gösteriyor. Ayrıca çok disklı bir VM'in
      IOPS metrikleri (`readIOSize`/`writeIOSize`, disk başına ayrı bir seri)
      son işlenen diskin üzerine yazması yerine artık diskler arası en
      büyük tekil pike göre birleştiriliyor. **Proje ilk kez Go unit
      testleri aldı** (`helper/main_test.go`) — batch sampling mantığı
      `perfSampler` arayüzü arkasına alınıp sahte bir sampler'la ilk-batch
      başarısızlığı, sonraki-batch başarısızlığı, ve çoklu-disk birleştirme
      kuralı vcsim'e ihtiyaç duymadan doğrudan test edildi (vcsim zaten
      disk IOPS sayaçlarını hiç desteklemiyor, bu üçünü canlı reproduce
      etmek mümkün değildi). Tam-başarı yolu ayrıca canlı vcsim'e karşı da
      doğrulandı (`performanceCoverage: {requested:10, collected:10,
      complete:true}`). `go test` (5 yeni test) + `swift build`/`swift
      test` temiz (63/63). **Sırada #11 (XLSX hücre tipleri), sonra #5
      (bağlantı yaşam döngüsü), sonra #9 (otomasyon)** — kullanıcının
      belirlediği sıra. Snapshot boyutunun disk delta'larını içermediği
      açıklaması ayrı, küçük bir düzeltme olarak bekliyor (bu turla
      bilinçli olarak birleştirilmedi).
- [x] **(2026-09-05) Aynı review'ın 4 P2 bulgusu daha düzeltildi (v1.3.1)** —
      kullanıcı "diğer bulgularımız için aksiyonun nedir" diye sordu; kalan
      8 P2 bulgusunu efor/etkiye göre gruplayıp bir sıra önerdim, en ucuz/net
      4 tanesini hemen düzelttim. (#10) **CSV formula injection** — `=`/`+`/
      `-`/`@`/tab/CR ile başlayan hücreler artık tek tırnakla nötrleniyor
      (OWASP'ın standart mitigasyonu), gerçek bir injection payload'ıyla test
      edildi. (#12) **VM ID çakışması** — `mapVMInfo`, `Config.Uuid`'i
      doğrudan (fallback'siz, ve sadece `Config != nil` iken) kullanıyordu;
      artık diğer her mapper'ın kullandığı `vmID()` fallback'ini (moref'e
      düşme) kullanıyor — bu narrow bir tutarlılık düzeltmesi, vcsim'de canlı
      reproduce edilmedi (gerçek VM'lerde Config nil olması son derece nadir),
      ama zaten test edilmiş paylaşılan bir fonksiyona geçiş olduğu için kod
      incelemesiyle yeterince doğrulandı. (#6) **Sıfır-VM ortamı "bağlı değil"
      ile aynı görünüyordu** — ana pencere `vms.isEmpty`'e bakıyordu, gerçek
      sağlıklı bir sıfır-VM vCenter da bunu sağlıyordu; yeni bir
      `isConnected` flag'i (`ConnectionViewModel`) bağlantı/demo başarılı
      olunca true, demo'dan çıkılınca false oluyor, `ContentView` artık ona
      bakıyor. (#README) **Mesajlaşma tutarsızlığı** — README hâlâ
      "pre-release"/"not notarized"/"private repository" diyordu, bu turun
      Faz 3/Sparkle/public-repo işinden önce yazılmış, güncellenmemiş
      kalmıştı; badge/status paragrafı/lisans satırı gerçek duruma
      (imzalı+notarize+public+5 gerçek GitHub Release) göre güncellendi.
      Kalan 4 P2 (refresh/disconnect eksikliği, launchd/CLI UUID riski,
      performans partial-failure, XLSX sayı-dönüşümü) ve mimari eleştiriler
      hâlâ backlog'da. `swift build`/`swift test` temiz (63/63, +1 yeni test).
- [x] **(2026-09-05) Harici bir kod review'ının 4 kritik (P1) bulgusu
      düzeltildi (v1.3.0)** — kullanıcı detaylı, dosya:satır referanslı 12
      maddelik bir profesyonel kod review'ı paylaştı, 4'ü P1/kritik
      işaretliydi; her biri gerçek kodda doğrulandı (varsayım değil), sonra
      "fix it pls" onayıyla düzeltildi. (1) **Paketlenmiş app her zaman
      çöküyordu** — `Bundle.module`'ün ürettiği resource bundle hiçbir zaman
      `.app`'e kopyalanmıyordu, fallback'i sadece build makinesinde
      çalışıyordu; her önceki release başka bir Mac'te fatalError veriyordu.
      Kanıtlandı: fallback path gizlenip paketlenmiş app gerçekten
      çöktürüldü. Düzeltme iki denemede oldu — ilk deneme (bundle'ı app
      root'una kopyalamak, `Bundle.module`'ün aradığı birebir yer) app'i
      çalıştırdı ama codesign'ı kırdı ("unsealed contents present in the
      bundle root" — `Contents/` dışına hiçbir şey, symlink dahil,
      konamıyor, doğrudan test edilerek doğrulandı); ikinci ve kalıcı
      çözüm: yeni `AppResourceLocator.swift`, bundle'ı `Contents/Resources/`'a
      bakıyor (`scripts/release.sh` oraya kopyluyor), dev modda
      `Bundle.module`'e düşüyor. Son doğrulama: fallback path tekrar
      gizlenip düzeltilmiş paketlenmiş app'in artık çökmediği doğrulandı.
      (2) **Sertifika pinleme gerçek bağlantıyı korumuyordu** — fingerprint
      sadece tek seferlik bir TLS probe'unda kontrol ediliyordu, asıl
      kimlik doğrulanmış bağlantı (`collectAll`, performans toplama)
      `insecure: true` ile bu fingerprint'e hiç bağlı olmadan kuruluyordu —
      ilk kontrolü geçen bir MITM ikinciyi hiç görmeden araya girebilirdi.
      govmomi'nin kendi `soap.Client.SetThumbprint` mekanizması kullanılarak
      düzeltildi (govc/terraform-provider-vsphere'in de kullandığı, olgun
      bir mekanizma — kaynak koddan okunarak keşfedildi). Hem GUI
      (`ConnectionViewModel`) hem CLI (`vlensCLI/main.swift`) artık gerçek
      bağlantıdan önce pinlenmiş fingerprint'i zorunlu kılıyor — yoksa
      bağlanmayı reddediyor. (3) **Sağlıklı bir multipath her zaman kırmızı
      işaretleniyordu** — Go tarafı `ScsiLun.OperationalState`'i (LUN
      seviyesi: "ok"/"degraded" vb.) gönderiyordu ama Swift tarafı bunu
      path-seviyesi state sanıp sadece "active"/"standby"'ı sağlıklı
      sayıyordu. Düzeltildi + iki mevcut test yanlış vocabulary kullandığı
      için düzeltildi. (4) **Snapshot deposu cross-process kilitlemeye
      sahip değildi** — GUI ve zamanlanmış CLI aynı anda
      `inventory-snapshots.json`'a yazabilir, biri diğerinin yazdığını
      sessizce kaybedebilirdi; bozuk bir dosya da sessizce boş sayılıp bir
      sonraki yazmada üzerine yazılabilirdi. `flock` ile cross-process
      kilitleme eklendi; mutation path'i artık bozuk dosyada sessizce boş
      saymak yerine hata fırlatıyor (salt-okunur `loadAll()` hâlâ nazik
      davranıyor). 3 yeni eşzamanlılık/bozukluk testi
      (`concurrentAddsDoNotLoseWrites` — 20 eşzamanlı writer, hiçbiri
      kaybolmuyor). Ayrıca ilişkili bir P2 bulgusu da düzeltildi: (7)
      **Helper'ın gerçek hata mesajları kayboluyordu** — Go helper stdout'a
      açıklayıcı bir JSON hata yazıyordu ama Swift sadece exit code≠0'da
      stderr'i okuyordu; artık önce stdout'u `HelperResponse` olarak decode
      etmeyi deniyor, sadece o başarısız olursa stderr'e düşüyor (geçici
      bir test dosyasıyla gerçek Go hatasının artık doğru yüzeye çıktığı
      canlı doğrulandı, sonra silindi). Kalan 8 P2 bulgusu (refresh/disconnect
      eksikliği, sıfır-VM ekranı, performans toplama partial-failure/metrik
      çakışması, launchd durum kontrolü + profil-adı-yerine-UUID riski, CSV
      formula injection, XLSX sayı-gibi-metin dönüşümü, VM ID çakışması) ve
      mesajlaşma/mimari eleştirileri (README tutarsızlığı, "historical
      trends"/"VM Changes" çerçevelemesi, export'un UI sıralamasını
      taşımaması) bilinçli olarak backlog'da bırakıldı — sadece P1'ler +
      #7 onay kapsamındaydı. `swift build`/`swift test` temiz (62/62, +3
      yeni test).
- [x] **(2026-09-05) Help ▸ What's New render'ı düzeltildi (v1.2.3)** —
      kullanıcı "text'ler çok kötü" diye geri bildirdi. Kök neden:
      `AttributedString(markdown:)` ile tüm CHANGELOG'u tek bir `Text`'e
      basmak hiçbir başlık/liste görsel hiyerarşisi uygulamıyordu (her satır
      aynı boyutta body text, versiyonlar arası boşluk yok). `HelpView.swift`'e
      elle yazılmış bir parser (`ChangelogEntry`/`ChangelogSection`) +
      gerçek SwiftUI VStack/HStack render'ı eklendi — versiyon başlıkları
      `.title3.bold()`, bölüm başlıkları `.subheadline.bold()`, madde
      imleri düzgün girinti/boşlukla. Tek satırlık madde içindeki
      `**bold**`/`` `code` `` için native markdown parser hâlâ kullanılıyor
      (o dar kapsamda iyi çalışıyor). **Gerçek bir ikinci bug bulundu ve
      düzeltildi doğrulama sırasında**: parser, `### ` başlığı olmadan gelen
      madde imlerini (v1.0.0'ın tek satırlık özeti gibi) sessizce
      düşürüyordu — standalone bir Swift script ile gerçek CHANGELOG.md'ye
      karşı çalıştırılıp yakalandı, düzeltildi, tekrar doğrulandı (9/9
      versiyon artık doğru parse ediliyor). `swift build`/`swift test`
      temiz (59/59).
- [x] **(2026-09-05) "What's New" ve Sparkle release notes eklendi (v1.2.2)**
      — kullanıcı Sparkle güncellemesini gerçekten test edip ("vov çalıştı!")
      sonra "kullanıcı update etti ama yenilikleri bilmiyor, rahatsız etmeden
      nasıl gösteririz" diye sordu. İki parça: (1) Help ▸ What's New — kök
      `CHANGELOG.md`, `Package.swift`'te yeni bir resource olarak
      `Sources/vLens/Resources/CHANGELOG.md`'ye kopyalanıp `Bundle.module`
      üzerinden okunuyor, Foundation'ın native `AttributedString(markdown:)`
      parser'ı (`.full` interpretedSyntax) ile render ediliyor — üçüncü parti
      bağımlılık yok, `docs/vLens-Reference.md`'nin "elle uyarlanmış özet"
      kuralının aksine burada TAM CHANGELOG gösterilmesi istendiği için
      kaynağın kendisi bundle edildi (elle kopyalanan ikinci bir Swift string
      = drift riski). (2) `scripts/release.sh`'a yeni bir adım: yeni
      `scripts/changelog_section_html.py` (bağımlılıksız, küçük bir markdown→HTML
      dönüştürücü — `### `/`- ` satırlarını + wrap olmuş devam satırlarını +
      `**bold**`/`` `code` ``'u anlıyor) `CHANGELOG.md`'den o sürümün bölümünü
      çekip appcast.xml'in `<item><description>`'ına CDATA olarak gömüyor —
      Sparkle bunu native güncelleme diyaloğunun içinde gösteriyor, ayrı bir
      pencere/interruption yok. Script'in başına `CHANGELOG.md`'yi
      `Sources/vLens/Resources/`'a kopyalayan bir senkron adımı da eklendi
      (tek elle yapılması gereken şey: release öncesi CHANGELOG.md'yi güncel
      tutmak). `swift build`/`swift test` temiz (59/59).
- [x] **(2026-09-05) Preferences'a Snapshot metrikleri için Select All/None
      eklendi (v1.2.1)** — kullanıcı Sparkle'ın "Check for Updates"
      akışını gerçek bir sürüm artışıyla test etmek istedi, Faz 7 backlog'undan
      küçük/bağımsız bir madde seçildi. `swift build`/`swift test` temiz
      (59/59). Bu sürüm aynı zamanda Sparkle'ın 1.2.0'dan 1.2.1'e gerçek bir
      güncelleme akışını da doğrulamak için kullanılıyor.
- [x] **(2026-09-04) Sparkle auto-update entegre edildi, Faz 3 tamamen kapandı
      (v1.2.0)** — `Package.swift`'e Sparkle SPM dependency'si (2.9.6),
      `vLensApp.swift`'e `SPUStandardUpdaterController` (`AppDelegate`
      artık `@MainActor` — Sparkle'ın init'i main-actor izole, Swift 6 strict
      concurrency bunu zorunlu kıldı) + "Check for Updates…" menü öğesi.
      `generate_keys` ile gerçek bir EdDSA anahtar çifti üretildi (private key
      sadece bu makinenin Keychain'inde), public key `Info.plist`'e
      (`SUPublicEDKey`) yazıldı, `SUFeedURL` `https://raw.githubusercontent.com/canberkys/vlens/main/appcast.xml`'e
      işaret ediyor. **Gerçek bir mimari bulgu**: SwiftPM'in varsayılan rpath'i
      (`@loader_path`) framework'ü `Contents/MacOS/` yanında arıyor, standart
      `Contents/Frameworks/` konumu değil — `Package.swift`'e
      `@executable_path/../Frameworks` rpath'i linker flag'i olarak eklendi.
      `scripts/release.sh`: Sparkle.framework artık `.app` içine gömülüp
      içeriden dışarıya doğru imzalanıyor (Autoupdate → Updater.app → 2 XPC
      servisi → framework'ün kendisi — hepsi XCFramework'te ad-hoc imzalı
      geliyor, gerçek Developer ID ile yeniden imzalanması gerekiyordu), DMG
      paketlendikten sonra `sign_update` ile EdDSA imzası alınıp `appcast.xml`
      yazılıyor. **Gerçek bir mimari karar (kullanıcı onayı, AskUserQuestion
      ile)**: Sparkle'ın arka plan güncelleme kontrolü kimlik doğrulama
      taşıyamıyor — private repo'da GitHub Pages/raw content/release asset'lerin
      hepsi auth istiyor. Kullanıcı **repoyu public yapmayı** seçti — public
      yapılmadan önce tüm commit geçmişi gerçek bir secret/credential sızıntısı
      için tarandı (temiz çıktı). Repo artık `github.com/canberkys/vlens`
      (public). `swift build`/`swift test` temiz (59/59).
- [x] **(2026-09-04) Snapshots tab'ına toplu seç/sil eklendi (v1.1.3)** —
      kullanıcı isteği: 10 snapshot'tan 4'ünü seçip birlikte silebilme.
      `List(rows, selection: $selectedSnapshotIDs)` ile çoklu seçim; seçim
      boş değilken listenin üstünde "N selected" + Deselect All + Delete
      Selected barı çıkıyor, tek bir onay diyaloğuyla hepsi birden siliniyor.
      `SnapshotStore.delete(ids: Set<UUID>)` eklendi — tek satırı N kere
      `delete(id:)` çağırıp N kere dosyayı yeniden yükleyip yazmak yerine
      tek bir load/persist round trip. 1 yeni test
      (`bulkDeleteRemovesOnlyTheMatchingSnapshots`). `swift build`/`swift
      test` temiz (59/59).
- [x] **(2026-09-04) Connect ekranı `macos-ui-ux` agent'ının bulgularına göre
      yeniden tasarlandı (v1.1.2)** — iki ayrı üst üste başlık (icon+"vLens"+tagline
      bloğu VE "Connect to vCenter" headline'ı) tek kompakt bir yatay header'a
      indirildi (icon solda, başlık+tagline sağda); kayıtlı bağlantılar menüsü
      artık host alanının hemen üstünde, ona bitişik (eskiden başıboş bir
      satır gibiydi); "Try demo mode" artık Connect butonunun altında, ayrı
      ve sönük (eskiden Connect ile aynı satırda eşit ağırlıktaydı); pencere
      480×580'den 420×480'e küçültüldü (3 esnek Spacer yerine sabit
      padding/spacing kullanıldı — içerik artık boşlukta yüzmüyor). `swift
      build`/`swift test` temiz (58/58). **Not**: GUI ekran görüntüsü
      otomasyonu bu turda tekrar denendi, yine yanlış pencere yakaladı
      (ilgisiz bir başka uygulama) — görsel doğrulama kullanıcıya bırakıldı.
- [x] **(2026-09-04) Sidebar navigasyonu resize sırasında tamamen kaybolabiliyordu
      (v1.1.1)** — kullanıcı canlı olarak yakaladı: 2 snapshot alıp Snapshots
      tab'ındayken pencereyi yeniden boyutlandırınca sidebar (27 tab'lık liste)
      tamamen görünmez oldu, geri getirecek hiçbir yol yoktu. Yeni kurulan
      `macos-ui-ux` sub-agent'ına kök neden bulup düzeltmesi için verildi.
      Kök neden: `NavigationSplitView` sistem `.automatic` stilinde
      bırakılmıştı — bu, belirli genişlik koşullarında sidebar'ı sessizce
      gizli bir overlay'e çeviriyor; app'in kendi "toolbar"ı gerçek bir
      `.toolbar()` olmadığı için SwiftUI'ın otomatik sidebar-geri-getirme
      butonu da hiç eklenmiyordu. Düzeltme (`ContentView.swift`):
      `columnVisibility` artık `.all`'a sabitlenmiş bir `@State` ile açıkça
      bağlanıyor, `.navigationSplitViewStyle(.balanced)` ekleniyor (collapse
      davranışına sahip `.prominentDetail`'in alternatifi), ve toolbar'a
      güvenlik ağı olarak manuel bir sidebar toggle butonu eklendi.
      `swift build`/`swift test` temiz (58/58).
- [x] **(2026-09-04) Faz 10B tamamlandı — Scheduler UI + launchd (v1.1.0)**:
      Preferences'a yeni "Automation" bölümü — aç/kapa toggle, kayıtlı
      bağlantı picker'ı, aksiyon picker'ı (Snapshot/Export CSV/Export XLSX,
      export seçilirse tab picker'ı da çıkıyor), gün/saat seçici
      (`DatePicker(.hourAndMinute)`), Save/Remove butonları, gerçek zamanda
      "Scheduled and active" / hata durumu göstergesi. Yeni
      `Sources/vLens/LaunchdScheduler.swift` — `AutomationSchedule`'ı gerçek
      bir `~/Library/LaunchAgents/com.canberkki.vlens.scheduler.plist`'e
      çevirip `launchctl bootstrap`/`bootout` ile yüklüyor (eski `load`/`unload`
      değil, güncel API). `Sources/vLens/AutomationCLILocator.swift` —
      `HelperLocator`'la aynı desen, paketlenmiş `.app`'te
      `Contents/MacOS/vlens-cli`'ı buluyor. `scripts/release.sh` artık
      `vlens-cli`'ı da build edip `.app` içine kopyalayıp imzalıyor (nested
      code sırası: helper → vlens-cli → dış app).
      **Gerçek mimari düzeltme**: `ExportTab`/`ExportFormat`/`exportData(...)`
      (Faz 10A'da `Sources/vLensCLI` içindeydi) `vLensCore`'a taşındı — hem
      CLI hem Preferences'ın export-tab picker'ı artık aynı tek listeyi
      paylaşıyor, iki ayrı yerde string listesi kopyalanmıyor.
      **Gerçek bir bulgu**: paketlenmiş `.app` içinde `vlens-cli`,
      `vLens`'in `Contents/Info.plist`'ine dizin-komşuluğu sayesinde aynı
      bundle ID'yi devralıyor — bu da Faz 10A'nın `UserDefaults(suiteName:
      "com.canberkki.vlens")` çağrısını macOS'un "kendi bundle ID'ni suite
      olarak kullanmak anlamsız" diye logladığı (ama sessizce zararsız kalan)
      bir duruma sokuyordu; `sharedDefaults()` artık bundle ID zaten eşleşiyorsa
      `.standard`'a düşüyor, gürültü gitti. **Uçtan uca gerçek doğrulama**:
      `scripts/release.sh` tam çalıştırılıp `vlens-cli` gerçekten imzalanıp
      notarize edildi; ikinci bir vcsim + gerçek bir bağlantı/Keychain/trust
      kaydı seed edilip, `LaunchdScheduler.install`'ın üreteceğiyle birebir
      aynı bir plist elle yazılıp **gerçekten** `launchctl bootstrap` ile
      yüklendi (~100 saniye sonrası için zamanlanmış) — launchd gerçekten
      zamanında tetikledi, `vlens-cli` gerçekten vcsim'e bağlanıp bir
      snapshot kaydetti, log dosyasında ve `inventory-snapshots.json`'da
      doğrulandı. Tüm test verisi sonrasında temizlendi. `docs/vLens-Reference.md`
      §10'un "Automation" notu güncellendi, versiyon **1.1.0**'a yükseltildi,
      `CHANGELOG.md`'ye eklendi.
- [x] **(2026-09-04) DMG artık standart "Applications'a sürükle" düzeninde**:
      kullanıcı gerçek indirmeyi test etti — DMG açılınca sadece `.app` tek
      başına boş bir Finder penceresinde duruyordu, Applications kısayolu
      yoktu (`hdiutil create -srcfolder <sadece .app>` kullanılıyordu).
      `scripts/release.sh`'ın DMG paketleme adımı yeniden yazıldı: `.app` +
      `/Applications` symlink'i bir staging klasörüne konup yazılabilir bir
      DMG oluşturuluyor, `osascript`/Finder scripting ile iki ikon yan yana
      diziliyor (pencere boyutu, ikon boyutu/konumları), sonra salt-okunur
      sıkıştırılmış DMG'ye dönüştürülüyor. Gerçekten mount edilip Finder'da
      doğru göründüğü doğrulandı (ekran görüntüsüyle). GitHub Release'deki
      DMG asset'i güncellenmiş haliyle değiştirildi (`gh release upload
      --clobber`).
- [x] **(2026-09-04) Gerçek app icon + ilk GitHub Release**: kullanıcı server
      rack + magnifying glass temalı, düz macOS-stili bir icon tasarladı
      (placeholder SF Symbol'ün yerine) — `Resources/AppIcon.icns`/`.iconset`
      güncellendi, `scripts/release.sh` yeniden çalıştırılıp gerçekten
      imzalanıp notarize edildi (yeni ikonun pakete girdiği checksum'la
      doğrulandı), ve `github.com/canberkys/vlens`'e (private) **v1.0.0**
      olarak `gh release create` ile yayınlandı — DMG asset olarak ekli.
- [x] **(2026-09-04) Faz 10A tamamlandı — `vlens-cli` (headless snapshot/export)**:
      yeni `.executableTarget("vlens-cli")`, `Sources/vLensCLI/` (`main.swift`,
      `CLIHelperLocator.swift`, `ExportTab.swift`). Komutlar: `list-profiles`,
      `list-tabs`, `snapshot --profile <ad> [--label] [--full-detail]`,
      `export --profile <ad> --tab <anahtar> --format csv|xlsx --output <path>`.
      `vLensCore`'daki her şey (Keychain, kayıtlı bağlantılar, sertifika
      trust store, helper client, snapshot store, vHealth engine, CSV/XLSX
      writer) sıfır değişiklikle doğrudan kullanıldı. İki gerçek mimari
      düzeltme yapıldı: (1) `ConnectionViewModel`'in özel
      `keychainReferenceID(for:)`'ı `vLensCore`'a taşındı
      (`ConnectionProfile.keychainReferenceID`) — GUI ve CLI artık aynı
      Keychain girdisini aynı formülle buluyor, format drift riski kalmadı;
      (2) CLI, `*PreferencesStore`'ları `UserDefaults(suiteName:
      "com.canberkki.vlens")` ile inşa ediyor — düz bir executable'ın
      `UserDefaults.standard`'ı GUI'nin gerçek bundle ID'sinden farklı bir
      domain'e düşer, bu paylaşılan suite olmasa CLI'nin aldığı snapshot
      GUI'nin ayarladığı depolama konumunu (Faz 9A) hiç görmezdi — canlı
      olarak test edilip doğrulandı. Sertifika: CLI bir onay sheet'i
      gösteremediği için bilinmeyen bir sertifikada **başarısız olur** (net
      mesaj + non-zero exit code), önceden pinlenmiş bir sertifikaya karşı
      sessizce güvenmez. **Uçtan uca gerçek doğrulama**: ikinci bir vcsim
      instance'ı ayağa kaldırılıp gerçek bir `ConnectionProfile`/Keychain
      girdisi/trust kaydı seed edildi (GUI'nin normalde ürettiğinin birebir
      aynı şeması); `snapshot`/`export` gerçekten çalıştırılıp üretilen
      dosyalar (gerçek VM verisi, gerçek XLSX arşivi) doğrulandı, özel
      depolama konumu gerçek bir `defaults write` ile ayarlanıp CLI'nin onu
      gerçekten kullandığı görüldü, bilinmeyen sertifika ve erişilemeyen
      host senaryolarının ikisi de net hata + exit code 1 ile başarısız
      oldu. Tüm test verisi sonrasında temizlendi. **Kapsam dışı
      (bilinçli)**: PDF rapor export'u. **Sırada Faz 10B**: Preferences'a
      "Automation" bölümü + launchd zamanlayıcı.
- [x] **(2026-09-04) Faz 3 tamamlandı — ilk imzalı/notarize/DMG'lenmiş sürüm**:
      kullanıcı Apple ID'siyle bir app-specific şifre üretip
      `xcrun notarytool store-credentials` adımını tamamladı (Keychain'deki
      `vlens-notary` profili), ardından `./scripts/release.sh` uçtan uca
      çalıştırıldı — build → `.app` bundle → codesign (önce helper, sonra app)
      → notarization (Apple'a submit edildi, "Accepted" döndü) → staple →
      Gatekeeper doğrulaması → DMG. Üç ayrı gerçek doğrulama yapıldı (sahte
      değil): `xcrun stapler validate` → "The validate action worked!",
      `spctl -a -vvv --type exec` → "accepted, source=Notarized Developer ID",
      ve `vLens-1.0.0.dmg` (~9.4 MB) diskte gerçekten oluştu. vLens artık
      temiz bir Mac'e indirilip doğrudan açılabilecek ilk gerçek sürümüne
      sahip. **Kalan**: bu DMG'yi bir GitHub Release'e eklemek (kullanıcı
      onayı gerektiriyor — repo private olsa da bir Release oluşturmak
      görünür/paylaşılan bir aksiyon), ve Sparkle auto-update entegrasyonu
      (Faz 3'ün planlanan ama henüz yapılmamış son parçası — appcast.xml +
      `SPUStandardUpdaterController`).
- [x] **(2026-09-04) 2 gerçek UI bug'ı düzeltildi — kullanıcının canlı kullanımında
      yakalandı**: (1) Snapshots tab'ına girildiğinde sidebar navigasyonu aşırı
      daraltılıyordu (etiketler baştan değil sondan görünür hale geliyordu,
      örn. "vNetwork" → "rk"). Kök neden: `SnapshotsTabView`'ın `HSplitView`'ı
      iki paneline sabit `minWidth` (260+420=680pt) veriyordu — bu, Snapshots
      seçildiğinde `NavigationSplitView`'ın sidebar kolonunu kendi
      `navigationSplitViewColumnWidth(min:160...)` sınırının çok altına
      sıkıştırmasına yol açıyordu (diğer hiçbir tab bu kadar büyük bir minWidth
      istemiyor). Düzeltme: minWidth'ler önemli ölçüde düşürüldü (180+260=440pt),
      hâlâ makul bir varsayılan genişlik veriyor ama sidebar'ı zorlamıyor.
      (2) Aynı saniye içinde birden fazla snapshot alındığında (gerçek bir
      senaryo — Faz 10'un zamanlayıcısı yanlış yapılandırılırsa olabilir, bu
      turda da yanlışlıkla test otomasyonuyla tetiklendi), List'in varsayılan
      satır-ekleme animasyonu bazı satırları geçiş ortasında yakalayıp trash
      ikonunun kırpılmış görünmesine yol açıyordu — satırlara sabit
      `minHeight: 36` + `List`'e `.transaction { $0.disablesAnimations = true }`
      eklendi. **Ayrıca kullanıcının sorusu üzerine**: Snapshot silme artık
      onay istiyor (`.alert`) — önceden trash butonuna basınca geri dönüşü
      olmayan bir silme anında gerçekleşiyordu.
- [x] **(2026-09-04) Faz 9 tamamlandı — Snapshot depolama konumu + basic/full-detail
      seçimi** (geri bildirim maddeleri 6 ve 6.1, ertelenen 3 mimari kararın ilk
      ikisi). **9A**: `SnapshotPreferencesStore.customStorageDirectory` (düz path,
      UserDefaults — sandbox olmadığı için security-scoped bookmark gerekmiyor),
      `SnapshotStore.url(inDirectory:)`, `ConnectionViewModel.changeSnapshotStorageDirectory(to:)`
      (kopyalar, asla taşımaz/silmez). Preferences'a yeni bir "Snapshot storage"
      bölümü: mevcut konum, Reveal in Finder, Change Location… (`NSOpenPanel`),
      Reset to Default. **9B**: `InventorySnapshot.fullVMList: [VirtualMachineInfo]?`
      (varsayılan `nil`, eski snapshot'lar sorunsuz decode oluyor), Take Snapshot
      satırında "Include full VM inventory" checkbox'ı (varsayılan **kapalı**).
      İki karşılaştırılan snapshot'ın ikisi de full detail taşıyorsa Compare
      panelinde yeni bir "VM Changes" bölümü — eklenen/çıkarılan VM'ler,
      `vmUUID`'ye göre basit bir set farkı (her alanın diff'lenmesi kasıtlı
      olarak kapsam dışı). **Aynı turda ayrıca**: Snapshot liste satırlarının alt
      satırı artık relative time gösteriyor (`RelativeDateTimeFormatter`) —
      önceki turda düzeltilen "aynı dakika-hassasiyetli tarih iki kez" bug'ının
      devamı, tutarlı hale getirildi. 6 yeni test (`SnapshotStoreTests.swift`) —
      gerçek `vlens-helper collectAll` çıktısının JSON şekli (vcsim'e karşı canlı
      çalıştırılarak) `fullVMList`'in decode edeceği şekille birebir doğrulandı.
      **Ertelenen üçüncü madde (8, rapor/snapshot zamanlayıcısı) artık Faz 10**.
- [x] **(2026-09-04) 9 maddelik kullanıcı geri bildirimi — 7'si hemen
      uygulandı** — mesajlaşma düzeltmesi ("alternative to RVTools" değil,
      "esinlenildi + kendine özgü özellikler"), Snapshot metriklerine (i) info
      icon, Help'in Tips.app tarzı yeniden tasarımı (renkli ikon rozetleri) +
      2 yeni konu (Security Advisories, Feedback), Cmd+F arama kısayolı, VMSA
      popover'ının yakınlığa göre gruplanması + etkilenen ürün tag'leri, ve
      kullanıcının ekran görüntüsüyle yakaladığı gerçek bir bug (Snapshot liste
      satırında label yokken başlık+alt satır aynı dakika-hassasiyetli tarihi
      tekrarlıyordu). Detaylar `~/.claude/plans/swirling-painting-snail.md`'de.
      **3 madde mimari karar gerektirdiği için ertelendi**: snapshot depolama
      konumunun kullanıcı tarafından seçilebilir olması, snapshot'ın
      basic/full-detail seçimi, ve rapor/snapshot toplama zamanlayıcısı (zaten
      bilinen "Automation" roadmap boşluğu) — bunlar için kısa bir `/plan`
      turu önerildi.
- [x] **(2026-09-04) README.md + About penceresi eklendi (Faz 7)** — README
      PkgLens'in yapısıyla tutarlı ama vLens'in henüz dağıtılmamış durumuna
      uyarlandı (Download bölümü yok, lisans "henüz karar verilmedi").
      `AboutView.swift`/`AppVersion.swift` — varsayılan boş About panelinin
      yerine geçiyor (`swift run` modunda gerçek Info.plist olmadığı için
      varsayılan panel boş görünürdü), `HelperLocator`'la aynı bundle→dev-fallback
      deseni.
- [x] **(2026-09-04) Gerçek imzalı `.app` bundle çalışıyor (Faz 3'ün büyük kısmı)** —
      `scripts/release.sh`: `swift build -c release` + elle inşa edilmiş `.app`
      bundle (Xcode projesi yok, PkgLens'in kanıtlanmış deseni) + iki aşamalı
      codesign (önce `vlens-helper`, sonra `.app` — nested code sırası önemli) +
      `codesign --verify --deep --strict` doğrulaması. Gerçekten çalıştırıldı,
      gerçek bir sorun bulundu: Apple'ın timestamp sunucusu bir seferinde flaky
      çıktı, retry'da düzeldi — script'e 3 denemeli retry loop eklendi. İmzalı
      `.app` gerçekten `open` ile başlatılıp çalıştığı doğrulandı. Placeholder
      icon (`Resources/AppIcon.icns`, SF Symbol tabanlı, mavi gradient — AppKit
      ile programatik üretildi, tasarımcı emeği değil) ve gerçek versiyonlama
      (`Resources/Info.plist`, `CFBundleShortVersionString` **1.0.0** — ilk
      gerçek sürüm, Package.swift'teki "v0.1.0" yorumu hiç dağıtılmamıştı).
      **Kalan**: notarization — kullanıcının bir kerelik `xcrun notarytool
      store-credentials` adımını bekliyor (Apple ID gerektirdiği için
      otomatikleştirilemez), script bunu algılayıp net talimatla duruyor.
      Ayrıca kullanıcı Preferences ekranını gözden geçirip geliştirmeye açık
      yerleri not almamı istedi — plan dosyasına Faz 7 altına eklendi (validasyon
      eksikliği, VMSA kontrolüne aç/kapa yok, Select All/None yok vb.) —
      henüz uygulanmadı, sadece kayıt.
- [x] **(2026-09-04) Proje GitHub'a taşındı + Feedback'in GitHub Issue kanalı
      tamamlandı (Faz 5 bitti)** — kullanıcı Feature Request'lerin doğrudan
      repo'ya issue olarak düşmesini istedi, bu da repo kararını gerektirdi.
      `github.com/canberkys/vlens` **private** olarak oluşturuldu
      (`gh repo create`), ilk commit push edildi (109 dosya). Git identity
      kurulumu kullanıcı tarafından yapıldı (`git config user.name/email`) —
      ben git config'e asla dokunmuyorum, istisnasız bir kural; bu PkgLens'in
      commit geçmişi kontrol edilerek de doğrulandı (orada da Claude
      co-authorship trailer'lı commit'ler var, ama identity kurulumu ayrı
      tutulmuş). `FeedbackView.swift`'e "Open as GitHub Issue" butonu eklendi
      — `bug`/`enhancement` label'ları gerçek `gh api` çağrısıyla doğrulandı,
      varsayılmadı. **"PR otomatik açsın" isteği bilinçli olarak yapılmadı**:
      bir feature request metninden mekanik olarak PR (gerçek kod değişikliği)
      üretmek sorumlu değil — issue'lar GitHub'a düşer, ben (gelecek bir
      oturumda) onları görüp triage edip PR'a çeviririm, bu bir iş akışı, app'e
      gömülü bir özellik değil.
      - **Sessiz/tek-tık gönderim** (kullanıcının ayrı bir isteği) bilinçli
        olarak release zamanına ertelendi — `~/.claude/projects/-Users-c-kilicarsl/memory/project_vlens.md`'e
        not düşüldü, gelecek oturum Faz 3 başladığında bunu proaktif hatırlatmalı.
- [x] **(2026-09-04) Feedback ekranı eklendi (Faz 5, sadece email kanalı)** — kullanıcı
      uzaktan ulaşılamaz durumdaydı ("devam etmen mümkün mü"), bağlı kaldığım
      için sadece GitHub'a muhtaç OLMAYAN kısımla devam ettim. `FeedbackView.swift`
      — Help menüsünden "Send Feedback…" (yeni bir `Window` sahnesi,
      `vLensApp.swift`). Tip (Bug/Feature), başlık, açıklama, ve gönderilmeden
      önce şeffaf şekilde gösterilen tanı bilgisi (macOS versiyonu, bağlıysa
      vCenter versiyonu/build'i — **asla host/kullanıcı/parola değil**).
      "Send via Email" bir `mailto:` URL'i açıyor (`NSWorkspace`), backend/secret
      yok. **GitHub Issue kanalı bilinçli olarak yapılmadı** — proje henüz
      GitHub'da değil, bu public/private kararı kullanıcıya ait, tek taraflı
      karar vermedim. Alıcı email adresi şimdilik kullanıcının kendi adresi
      (`kayit@canberkki.com`) — kendi ürünü için kendi gelen kutusuna gitmesi
      makul bir varsayılan, ama `FeedbackView.recipientEmail`'de teyit/değişiklik
      bekliyor.
- [x] **VMSA güvenlik danışmanlığı farkındalığı eklendi (Faz 4A)** — kullanıcı
      uzaktaydı, "geliştirmeye devam et" dedi; GitHub/signing kararı beklemeyen,
      tamamen bağımsız bir sonraki iş olduğu için buna devam edildi.
      `Sources/vLensCore/VMSAClient.swift` — Go helper'a hiç gitmiyor (vCenter
      bağlantısından bağımsız). Planlamada bulunan resmi GET endpoint'i
      gerçekte 404 veriyor — canlı istekle test edilip POST endpoint'inin
      (`support.broadcom.com/.../getSecurityAdvisoryList`) çalıştığı doğrulandı.
      **Beklenenden daha zengin çıktı**: sadece başlık/tarih/link değil, gerçek
      severity (CRITICAL/HIGH/MEDIUM/LOW), CVE listesi, etkilenen ürün adları
      da geliyor — CVSS sayısal skoru ve build aralığı hâlâ yok (Faz 4B,
      ertelendi). Toolbar'a sadece CRITICAL/HIGH bulunduğunda görünen bir kalkan
      rozeti + popover (`SecurityAdvisoriesView.swift`) eklendi — hiçbir zaman
      alert/interrupt yok, sessizce başarısız oluyor. `severity` kasıtlı olarak
      strict enum değil, ham String (dış/versiyonsuz bir API, tanınmayan bir
      değer decode'u kırmamalı). 4 yeni test — gerçek yakalanmış bir response
      fixture'ı kullanıyor (`VMSAClientTests.swift`, stub `URLProtocol`,
      paylaşılan mutable state yüzünden `@Suite(.serialized)` gerekti —
      Swift Testing'in varsayılan paralel çalıştırması bir race'e yol açtı,
      düzeltildi).
- [x] **UI cilası: Export buton çakışması + tutorial kapsamı genişletildi** —
      kullanıcı bulk data'da GUI'yi inceledi, iki şey buldu: (1) Snapshots
      tab'ında Compare panelinin "Export" butonu toolbar'ın genel "Export"
      butonunun neredeyse tam altına düşüyordu (aynı label, aynı ikon, görsel
      olarak çakışıyor/kafa karıştırıyordu) — `Spacer()` ile sağa itilmesi
      kaldırıldı (artık Baseline/Current picker'larının hemen yanında),
      "Export Comparison" olarak yeniden adlandırıldı. (2) Tutorial kapsamı
      tutarsız hissettiriyordu (sadece Snapshots+vPerformance'ta vardı) —
      kullanıcı uzaktaydı, "sen devam et" dedi, ben de bunu ilke bazlı
      genişlettim: vHealth (tek computed-not-collected tab) ve vNetwork
      (vNic/vSC+VMK ile karışabilir) eklendi; `TutorialID`'ye artık net bir
      kural yazıldı ("RVTools'u bilen bir admin bu tab'a özel kafası mı
      karışır?" testi) — vInfo/vCPU/vDisk gibi doğrudan RVTools ayna
      tab'larına kasıtlı olarak eklenmedi (her tab'da popover = tam da
      kaçınılmak istenen rahatsız edici davranış).
- [x] **In-app Help + Onboarding (yeni bir `/plan` turunun Faz 1+2'si)** —
      kullanıcı bulk data ile son hali inceledi ("çok iyi görünüyor... ama tam
      anlamıyla bitmiş diyemiyorum") ve 5 yeni iş alanı istedi (auto-update,
      VMSA farkındalığı, onboarding, native Help, in-app feedback/bug report).
      Bu tur ilk ikisini bitirdi, kalan 3'ü (`~/.claude/plans/swirling-painting-snail.md`)
      dağıtım altyapısına (code signing/notarization/GitHub) muhtaç oldukları
      için ayrı bir tur bekliyor. **Ek olarak**: kullanıcının bulduğu gerçek bir
      eksik düzeltildi — Snapshot Compare panelinin kendi export'u yoktu,
      artık var (Metric/Baseline/Current/Delta CSV'si, `SnapshotsTabView.swift`).
      - **Help**: `HelpView.swift`, `vLensApp.swift`'te `CommandGroup(replacing: .help)`
        ile varsayılan (boş) Help menü öğesinin yerine geçiyor — dışarı hiç
        çıkmıyor. 6 konu, elle yazılmış kullanıcı-dostu özet metinler (referans
        dokümanı geliştirici odaklı olduğu için doğrudan gömülmedi).
      - **Onboarding**: `TutorialStore.swift` (UserDefaults, diğer *PreferencesStore'larla
        aynı desen) + `Tutorial.swift` (`TutorialID` sabitleri, `.tutorialPopover(id:title:text:)`
        genel view modifier'ı, `WelcomeOverlayView`). İlk açılışta connect
        ekranında tek bir dismissible sheet (3 madde, çok adımlı slide show
        değil — kullanıcının "hafif coachmark" tercihine göre). Snapshots ve
        vPerformance tab'larına (en yeni, ismi kendini açıklamayan iki tab)
        birer kereliğine gösterilen popover eklendi. Preferences'a "Reset
        Tutorials" butonu — `showWelcome`'ın connect ekranının her `onAppear`'ında
        store'dan yeniden okunması sayesinde relaunch gerekmeden çalışıyor.
      - **VMSA için gerçek araştırma yapıldı, uydurulmadı**: Broadcom'un resmi,
        dokümante JSON API'si bulundu (`knowledge.broadcom.com/external/article/408302`)
        — ama CVSS/etkilenen build bilgisi bu endpoint'te yok, her danışmanlığın
        kendi (dokümante edilmemiş) detay sayfasında. Bu yüzden plan feature'ı
        iki faza böldü (güvenli liste/rozet önce, build-eşleştirme ayrı/stretch).
      - 4 yeni test (`TutorialStore`)
- [x] **Yönetici raporu (PDF) eklendi (Özellik 3/3, `/plan` planından — plan
      tamamlandı)** — RVTools'ta yok, "sunumluk/infrapack" rapor fikri. Toolbar'da
      Export'un yanında yeni bir "Report" butonu. `ReportView.swift`: vCenter
      kimliği/versiyonu (yeni `VCenterInfo` — `client.Client.ServiceContent.About`,
      login sonrası zaten bedava mevcut, ekstra vCenter çağrısı yok), VM/host/
      cluster/datastore sayım kartları, native **Swift Charts** ile VM power-state
      donut'u + datastore boş alan bar grafiği (en büyük 10 datastore ile
      sınırlı — okunabilirlik için), vHealth kırmızı/sarı özet. `ReportRenderer.swift`:
      `ImageRenderer`'ın closure-based `render(rasterizationScale:renderer:)` API'si
      ile doğrudan bir `CGContext`'e (PDF context) çiziliyor — tek sayfa, içeriğe göre
      dinamik yükseklik, sayfalama yok (bilinçli: bu bir infografik, okunacak bir
      rapor dokümanı değil). Yeni dependency yok (Swift Charts + ImageRenderer SDK'da
      hazır). `docs/vLens-Reference.md`'deki eski "PDF kapsam dışı" notu düzeltildi —
      o karar tab veri export'u içindi (CSV/XLSX'in işi), bu farklı bir ürün.
      **Not**: GUI'de "Report" butonuna gerçek tıklamayla üretilen PDF'in görsel
      çıktısı bu oturumda doğrulanamadı (ekran görüntüsü otomasyonu bu oturumda daha
      önce güvenilmez çıkmıştı, tekrar denenmedi) — build/type-check temiz ve
      ImageRenderer→CGContext→PDF deseni Apple'ın kendi dokümante ettiği yöntem, ama
      kullanıcının demo modda bir kez elle deneyip görsel olarak onaylaması iyi olur.
- [x] **Snapshots tab eklendi (Özellik 2/3, `/plan` planından)** — RVTools'ta yok,
      kullanıcının kendi fikri: envanterin "anlık görüntüsü"nü alıp zaman içinde
      karşılaştırmak. Yeni bir **History** sidebar grubu (VM/Infrastructure/
      Networking/Storage/Licensing/Health'e ek altıncı grup). Curated 11 metrik
      (`InventorySnapshotMetrics.compute`) — VM/host/cluster/datastore sayıları, en
      kötü datastore boş alan %'i (ortalama değil — tek kritik datastore'u gizlemesin
      diye), aktif snapshot sayısı, Tools sorunlu VM sayısı, vHealth kırmızı/sarı
      bulgu sayısı — hepsi zaten bellekte olan array'lerden hesaplanıyor, ekstra
      vCenter çağrısı yok. `SnapshotStore` (`ConnectionProfileStore` ile aynı JSON/
      Application Support deseni) her vCenter host için ayrı dosya değil, tek dosya +
      host'a göre filtre. Kullanıcı "hangi metrikleri saklayalım" diye sordu — cevap:
      hepsi zaten bedava olduğu için hepsi her zaman kaydediliyor, kullanıcı kontrolü
      bunun yerine Compare panelinde **hangi metriklerin gösterileceğine** taşındı
      (`SnapshotPreferencesStore`, Preferences'a yeni bir bölüm). Her metrik bir
      `MetricComparisonDirection` (higherIsBetter/lowerIsBetter/neutral) taşıyor —
      Compare panelinin delta rengi (yeşil/kırmızı) sadece işarete değil, o metrik
      için hangi yönün gerçekten iyi olduğuna bakıyor. 6 yeni test.
- [x] **vPerformance tab eklendi** — AWS repo taramasının ikinci bulgusu, `/plan`
      turundan sonra uygulandı. RVTools'ta karşılığı yok: `summary.quickStats`'in
      anlık değerlerinin aksine, `PerformanceManager` üzerinden zaman aralığına
      yayılmış (1s/4s/24s/7g/30g, kullanıcı seçimli) CPU/RAM % ve disk IOPS boyutu
      geçmişi. **Mimari not**: `collectAll`'a değil, kendi `HelperAction`'ına
      (`collectPerformance`, kendi login'i) kondu — `QueryPerf` per-entity bir
      çağrı (govmomi'nin `performance.Manager.SampleByName`/`ToMetricSeries` API'si
      kullanıldı, 50'lik batch'ler halinde), `collectAll`'ın "tek login tek
      PropertyCollector batch" hız garantisini kırardı. Tab'ın kendi zaman aralığı
      `Picker`'ı + "Collect" butonu var, ana connect/refresh akışından bağımsız.
      Tüm metrik alanları `Double?`/`Int64?` — vcsim'in disk IOPS sayaçlarını hiç
      desteklemediği gerçek veriyle doğrulandı (`null` dönüyor, `0` değil — "veri
      yok" ile "gerçek sıfır" birbirine karıştırılmıyor, `-1` sentinel örnekleri
      ortalamadan düşülüyor). vcsim'e karşı gerçek CPU/RAM % verisiyle doğrulandı.
      1 yeni test (`VMPerformanceInfo` decode — Go tarafının `avgCpuUsagePercent`
      gibi tam JSON key'leriyle, `avgCPUUsagePercent` gibi yanlış bir Swift alan
      adı yazıp derleme zamanında yakalanamayacak bir bug'ı elle karşılaştırarak
      önceden yakaladım).
- [x] **vNetwork tab eklendi** — AWS'nin `awslabs/export-for-vcenter` (Python/pyVmomi,
      AWS Transform for VMware'in migration assessment girdisi için RVTools-format CSV
      üreten bir CLI) repo'su incelenirken bulundu: RVTools'un belgelediği (rvtools.txt
      ~1581. satır), ama vLens'in daha önce hiç fark etmediği gerçek bir eksikti — VM
      başına sanal NIC bilgisi (`vNic`/host fiziksel pNIC'lerinden ve `vSC+VMK`/host
      VMkernel adaptörlerinden tamamen farklı: "bu VM'in NIC'i hangi port group'a
      bağlı"). `VMNetworkInfo` modeli, `mapVMNetworks` (Go) — `config.hardware.device`
      üzerinden her zaman satır üretiyor (Tools şart değil), `guest.net` varsa
      Network/IPv4/IPv6'yı zenginleştiriyor (eşleme `GuestNicInfo.deviceConfigId`
      üzerinden). Distributed port group ismi çözümü için yeni bir
      `dvPortgroupKeyNameMap` (key→name, `DistributedVirtualPortgroup.key` üzerinden)
      eklendi. vcsim'e karşı gerçek veriyle doğrulandı (distributed port group adı
      `DC0_DVPG0` doğru çözüldü). AWS repo'sunun ikinci bulgusu — `PerformanceManager`
      üzerinden zaman aralığına yayılmış CPU/RAM/IOPS geçmişi (RVTools'ta bile yok) —
      ayrı bir /plan turu bekliyor, kapsamı daha büyük.
- [x] **4 yeni vHealth kuralı wire edildi + doküman güncellemesi**: son turda
      eklenen vCD/vPartition/vMultipath tab'ları artık kendi vHealth kurallarını da
      besliyor — RVTools kural #1 (CD-ROM bağlı), #5 (guest disk boş alan %,
      vPartition'dan), #8 (datastore başına VM sayısı — `numVMsTotal`, power-state
      filtresi yok), #12 (multipath: `active`/`standby` dışındaki her state kırmızı
      bulgu). `HealthCheckThresholds`'a `guestDiskFreeSpacePercent` (varsayılan 10%)
      ve `maxVMsPerDatastore` (varsayılan 30) eklendi, `PreferencesView`'da ikisi de
      ayarlanabilir. Toplam: 5→9 kural, 24'ün 15'i kaldı. `docs/vLens-Reference.md`
      §5 tablosu ve §10 özeti güncellendi; ayrıca §4'ün 8 niş tab girişi (vRP, vHBA,
      vNic, vSC+VMK, vMultipath, vCD, vUSB, vPartition) ve "sadece vApp+vFileInfo
      eksik" notu tamamlandı (önceki turda yarım kalmıştı). 6 yeni test.
- [x] **UI: sidebar navigasyonu + login pencere düzeltmesi + buton hiyerarşisi +
      cert sheet'e kopyalama butonu**. Yatay kaydırmalı tab bar `NavigationSplitView`
      sidebar'a taşındı, gruplu (`AppTabGroup`: VM/Infrastructure/Networking/
      Storage/Licensing/Health) — 23 tab'da artık ölçekleniyor, yeni tab eklemek
      sadece `AppTab`'a `label`+`group` eklemek. Connect ekranı artık kendi
      480×580 frame'inde (eskiden 1000×640 pencerede 420pt'lik form kayboluyordu).
      "Try demo mode" ikincil (`.link`), "Connect" birincil (`.borderedProminent`)
      stile geçti. Cert onay sheet'inde fingerprint'i panoya kopyalayan bir buton var
- [x] **8 niş tab daha: vRP, vHBA, vNic, vSC+VMK (vmk), vMultipath, vCD, vUSB,
      vPartition**. Artık **23 tab** var (vApp ve vFileInfo hariç RVTools'un
      neredeyse tamamı). Hepsi vcsim'e karşı doğrulandı — 5'i gerçek veriyle
      doldu (vRP, vHBA, vNic, vmk, vMultipath, vCD), 2'si vcsim'in simüle
      etmediği için boş ama null değil kaldı (vUSB, vPartition — vPartition
      VMware Tools'un guest disk raporlamasını gerektiriyor, vcsim'in sahte
      VM'lerinde gerçek guest OS yok). vCD/vUSB/vPartition zaten fetch edilen
      `config.hardware.device`/`guest.disk`'ten türetiliyor, ekstra property
      round-trip'i yok. Tüm 22 collector birlikte vcsim'de **0.065 saniyede**
      tamamlandı — 23 tab'da hâlâ performans endişesi yok
- [x] **5 yeni tab: vLicense, vSwitch, vPort, dvSwitch, dvPort** (roadmap Sıra 4,
      genişlik). Hepsi Go tarafında yeni
      collector'larla (`collectLicenses`, `collectVSwitchesAndPorts`,
      `collectDVSwitches`, `collectDVPortgroups`), vcsim'e karşı gerçek veriyle
      tek tek doğrulandı:
      - **vLicense**: `govmomi/license` paketi ile `LicenseManager.List()`.
        İzin yoksa (RVTools'un kendisi de aynı kısıtı belgeliyor — read-only
        hesaplar lisansı göremiyor) `collectAll`'un tamamını düşürmüyor, sadece
        bu tab boş kalıyor. vcsim'in eval lisansına karşı test edildi
        (Features: "Remote virtual Serial Port Concentrator", "vSphere
        Distributed Switch" doğru geldi)
      - **vSwitch/vPort**: tek host geçişinde birlikte topluyor
        (`collectVSwitchesAndPorts`) — **gerçek bir bug'ı burada da yakaladım**:
        port group'un switch'e referansı ham bir "key" string'i
        (`key-vim.host.VirtualSwitch-vSwitch0`), isim değil; host-scoped bir
        key→isim map'i olmadan doğrudan kullanınca yanlış görünüyordu, düzeltildi
      - **dvSwitch/dvPort**: `DistributedVirtualSwitch`/`DistributedVirtualPortgroup`
        container view'ları. dvPort'un VLAN'ı sadece basit tek-VLAN-ID durumunu
        okuyor (trunk/PVLAN type'ları farklı, tahmin yürütülmüyor, nil kalıyor)
      Tüm collector'lar birlikte (13 collector, tam liste) vcsim'de **0.04 saniyede**
      tamamlandı — yeni tab'lar performansı bozmadı
- [x] **Preferences ekranı + veri boşlukları kapatıldı** (roadmap Sıra 3):
      Cmd+, ile açılan `PreferencesView` — vHealth eşiklerini (datastore boş alan %,
      host başına vCPU oranı) `HealthCheckPreferencesStore` (UserDefaults) üzerinden
      ayarlıyor, değişiklik anında mevcut veriye karşı vHealth'i yeniden hesaplıyor
      (reconnect gerekmiyor). `ConnectionViewModel` artık `vLensApp`'ta tek instance
      olarak tutulup hem ana pencereye hem Settings scene'ine enjekte ediliyor.
      `HostInfo.datacenterName` artık gerçekten çözülüyor (host → ComputeResource/Folder
      parent zinciri → Datacenter, tip-agnostik genel bir walk ile) — vHost tab'ına
      Datacenter kolonu geri eklendi (Cores kolonuyla yer değiştirdi, 10-kolon limiti).
      `VMSnapshotInfo.sizeMiBTotal` artık `layoutEx.file`/`layoutEx.snapshot`'tan
      gerçek dosya boyutu topluyor (data+memory dosyaları; disk delta zinciri
      kasıtlı olarak dahil değil — hangi snapshot'a ne kadar ait olduğu belirsiz
      olduğu için tahmin yürütülmüyor). İkisi de vcsim'e karşı gerçek veriyle
      doğrulandı (`helper/vcsim/mksnap` ile gerçek bir test snapshot'ı oluşturulup
      test edildi). 2 yeni test (`HealthCheckPreferencesStore`)
- [x] **Cert-trust-on-first-use** — Docky'nin `Core/SSH/HostKeyTrust.swift` +
      `HostKeyTrustReviewViewModel` pattern'i SSH host key'lerinden TLS
      sertifikalarına uyarlandı (`Sources/vLensCore/CertificateTrust.swift`):
      `CertificateFingerprint`, `TrustedCertificate`, `LocalJSONCertificateTrustStore`
      (JSON, Application Support). Go helper'a `getCertificate` action'ı eklendi —
      login olmadan sadece ham TLS handshake ile sertifikayı okuyup SHA-256
      fingerprint çıkarıyor (`helper/main.go`, `fetchCertificate`). vcsim'e karşı
      CLI seviyesinde gerçek doğrulama yapıldı. Bilinmeyen sertifikada
      `ConnectionViewModel` bir onay sheet'i bekletiyor (`pendingCertificateApproval`,
      `ContentView.certificateApprovalSheet`); önceden pin'lenmiş bir sertifika
      değişirse (olası MITM) sert şekilde reddediyor, sessizce geçmiyor. Eski
      "Allow self-signed certificate" toggle'ı ve `ConnectionProfile`'daki
      kullanılmayan `allowInsecureTLS`/`pinnedCertificateFingerprint` alanları
      kaldırıldı — trust artık host başına, saved-profile'dan bağımsız takip
      ediliyor (kaydedilmemiş/ephemeral bağlantılar da korunuyor). 6 yeni test.
      **Not:** GUI'de sheet'in gerçek tıklamayla çalıştığı bu oturumda görsel
      olarak doğrulanamadı (AppleScript otomasyonu güvenilmez çıktı) — kullanıcı
      manuel doğrulamalı
- [x] **Hijyen turu**: `helper/main.go`'daki ölü `helperClientError` type'ı
      silindi; `FieldComparator` `Sources/vLens/`'ten `Sources/vLensCore/`'a
      taşındı (sadece Foundation'a bağımlı, SwiftUI değil — artık test edilebilir);
      `FieldComparator`/`Searchable`/`ConnectionProfileStore` için testler eklendi
- [x] **XLSX export** — `XLSXWriter` (ZIPFoundation üzerine minimal OOXML writer,
      shared-strings tablosu yok, inline string + gerçek numeric cell detection).
      Export butonu artık "Export as CSV" / "Export as XLSX" menüsü
      (`ExportPanel.swift`, eski `CSVExportPanel.swift`). 3 yeni test: gerçek zip
      round-trip (ZIPFoundation'ın kendi okuma path'inden, bizim yazdığımızdan
      bağımsız), XML özel karakter escaping, 31 karakter sheet-name limiti
- [x] SwiftPM iskeleti (vLens app target + vLensCore lib target)
- [x] **Go/govmomi helper `collectAll` — 9 collector, tek login + tek PropertyCollector
      geçişi**: vInfo, vCPU, vMemory, vDisk, vSnapshot, vTools (hepsi tek VM property
      fetch'inden türetiliyor), vHost, vDatastore, vCluster. Artık canlı bağlantıda
      **tüm 9 tab** dolu geliyor (önceki turda sadece vInfo doluyordu)
- [x] **Standalone-host / cluster karışıklığı düzeltildi**: önceki implementasyon
      generic "ComputeResource" type filter kullanıyordu, bu da her host'un görünmez
      wrapper'ını gerçek cluster sanıyordu. Artık sadece "ClusterComputeResource" tipi
      sorgulanıyor — standalone host'ların Cluster kolonu doğru şekilde boş
- [x] **vcsim ile gerçek entegrasyon testi** — bkz. yukarıdaki bölüm. 1200 VM
      ölçeğinde doğrulandı, 0.58s
- [x] **27 tab'ın tamamı UI'da var**: vInfo, vCPU, vMemory, vDisk, vSnapshot, vTools,
      vNetwork, vCD, vUSB, vPartition, vPerformance, vApp, vHost, vDatastore, vCluster,
      vRP, vSwitch, vPort, dvSwitch, dvPort, vNic, vSC+VMK, vHBA, vMultipath, vLicense,
      vHealth, Snapshots — sidebar (gruplu) + her biri için `Table` view, canlı
      bağlantıda hepsi dolu geliyor (vPerformance ve Snapshots hariç — ikisi de kendi
      aksiyon butonlarıyla ayrı tetiklenir, bkz. ilgili maddeler)
- [x] **Kolon başlığına tıklayarak sıralama** — tüm tab'larda, `FieldComparator`
      (Swift'in `SortComparator` protokolüne uyan, optional alanlarda nil'leri her
      zaman sona atan custom comparator; `FieldComparator.swift`)
- [x] `DemoData` — 40 VM'lik tutarlı mock veri seti, tüm tab'ları besliyor
- [x] `HealthCheckEngine` — RVTools'un 24 vHealth kuralından 10'u gerçek hesaplama
      (CD-ROM bağlı, aktif snapshot, VMware Tools durumu, guest disk boş alan eşiği,
      datastore boş alan eşiği, host başına vCPU oranı, datastore başına VM sayısı,
      multipath durumu, consolidation needed, host config status); tab bar'da bulgu
      sayısı rozeti var.
      4 eşik artık Preferences'ta ayarlanabilir (datastore boş alan %, vCPU/core,
      guest disk boş alan %, datastore başına max VM)
- [x] `swift run` focus sorunu çözüldü (`NSApplicationDelegateAdaptor` +
      `NSApp.activate`)
- [x] **Arama/filtre**, **CSV export**, **Status bar**, **Keychain'e kaydetme** —
      detaylar `docs/vLens-Reference.md`'de
- [x] **Tüm arayüz İngilizce'ye çevrildi** — global bir ürün, Türkçe UI metni kalmadı
- [x] 35 unit test yeşil (`VirtualMachineInfo` decode, 10×`HealthCheckEngine`,
      2×`CSVWriter`, 3×`XLSXWriter`, 3×`FieldComparator`, 4×`Searchable`,
      4×`ConnectionProfileStore`, 6×`CertificateTrust`, 2×`HealthCheckPreferencesStore`)
- [ ] Kullanıcının gerçek vCenter 8 + ESXi 8 ortamına karşı canlı doğrulama — hâlâ
      yapılmadı (VPN erişimi yok), ama vcsim ile mimari zaten gerçek anlamda doğrulandı
- [ ] Kalan 14 vHealth kuralı (floppy bağlı, zombie VMDK/VM, NTP/sertifika bitişi,
      config-issue event'leri vb.) — çoğu `vFileInfo`'ya veya toplanmayan
      event/config verisine muhtaç, kaynak tab'ları büyüdükçe eklenecek
- [x] **(2026-09-04) vApp tab'ı tamamlandı** — `collectVApps`, `collectResourcePools`
      pattern'inin `VirtualApp` üzerinden neredeyse birebir tekrarı (vim25'te
      `VirtualApp`, `ResourcePool`'u extend ediyor). vcsim'de gerçek bir VirtualApp
      instance'ı oluşturan yeni bir dev-tool (`helper/vcsim/mkvapp`) ile doğrulandı —
      vcsim'in `createChild`'ı her `ResourceAllocationInfo` alanının set edilmesini
      zorunlu kılıyor, boş spec ile `InvalidArgument` hatası veriyor (canlı test
      ederek bulundu, tahmin edilmedi). Artık RVTools'un 24 tab'ından sadece
      **vFileInfo** eksik (bilinçli olarak süresiz ertelendi — RVTools'un kendisi
      de yavaş/nadir kullanılan diyor).
- [ ] Multi-vCenter merge, CLI/launchd otomasyonu, tags/custom attributes kolonları
- [ ] App bundle/notarization

## Güvenlik notu

Parola artık `saveCredentials` işaretliyse `KeychainCredentialStore` üzerinden gerçek
Keychain'e yazılıyor (`ConnectionViewModel.persistCurrentConnection`). İşaretli
değilse hâlâ sadece in-memory `@Observable` alanında kalıyor, diske hiç yazılmıyor.

Sertifika doğrulaması artık trust-on-first-use: transport katmanında her zaman
`insecure: true` (govmomi'nin standart CA doğrulamasını atlıyoruz, çünkü on-prem
vCenter'lar neredeyse hepsi self-signed/internal-CA), ama bağlanmadan önce
`getCertificate` ile ham sertifika fingerprint'i çekilip
`LocalJSONCertificateTrustStore`'a karşı kontrol ediliyor. Bilinmeyen host →
kullanıcı onayı bekleniyor; daha önce pin'lenmiş bir host'un sertifikası değişirse
→ sert red (`CertificateMismatchError`), asla sessizce geçmiyor. Bu, RVTools'un
kendisinin bile yapmadığı bir güvenlik iyileştirmesi (RVTools sertifika doğrulaması
yapmaz).
