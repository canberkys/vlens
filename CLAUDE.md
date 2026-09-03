# vLens - Claude Code Project Context

## Proje Özeti
RVTools'un macOS-native alternatifi. vCenter/ESXi ortamlarından envanter bilgisi
toplayan, hızlı, modern, native SwiftUI desktop uygulaması. `~/Documents/Projects/vInventory`
(Tauri/React, Windows-only, askıda) ile ilgisi yok — ayrı, macOS-first bir proje.

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
│       ├── TutorialStore.swift     # hangi tutorial/coachmark'ların gösterildiği (UserDefaults)
│       ├── VMSAClient.swift        # Broadcom'un resmi güvenlik danışmanlığı JSON API'si (Go helper'a gitmiyor)
│       ├── CertificateTrust.swift  # trust-on-first-use (Docky'nin HostKeyTrust'ından uyarlandı)
│       ├── Searchable.swift      # her model için searchableText + .matches(query)
│       ├── CSVExport.swift       # her model için CSVExportable + CSVWriter
│       ├── XLSXExport.swift      # ZIPFoundation üzerine minimal OOXML writer
│       ├── ConnectionProfileStore.swift  # kayıtlı bağlantılar (host/user), parola Keychain'de
│       └── FieldComparator.swift   # sıralama comparator'ı (app değil Core'da — sadece
│                                     # Foundation'a bağımlı, SwiftUI değil, bu yüzden test edilebilir)
├── Sources/vLens/ExportPanel.swift  # NSSavePanel ile CSV/XLSX kaydetme (app layer, @MainActor)
├── Tests/vLensCoreTests/    # decode + HealthCheckEngine + CSVWriter + XLSXWriter +
│                             # FieldComparator + Searchable + ConnectionProfileStore +
│                             # CertificateTrust + HealthCheckPreferencesStore + SnapshotStore +
│                             # InventorySnapshotMetrics + TutorialStore + VMSAClient testleri (52 test)
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
```

`ConnectionViewModel` helper binary'yi şu sırayla arıyor: app bundle Resources →
`VLENS_HELPER_PATH` env var → dev fallback (`helper/vlens-helper`, proje kökünde
`go build` ile üretilmiş olmalı).

## Durum (2026-09-03, son maddeler 2026-09-04)

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
