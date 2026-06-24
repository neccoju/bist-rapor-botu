# BIST Rapor Botu

GitHub Actions üzerinde her BIST işlem günü (Pzt-Cum) 18:15 Europe/Istanbul'da
otomatik çalışan, BIST hisselerini tarayıp skorlayan, model portföyleri yöneten
ve sonucu e-posta + artifact olarak veren bulut botu. Bilgisayar kapalıyken de
çalışır.

> Sayısal taramadır, **yatırım tavsiyesi değildir**. Ücretsiz kaynaklar gecikmeli/
> eksik olabilir; işlem öncesi KAP, Borsa İstanbul, TCMB ve lisanslı kaynaklarla
> doğrulayın.

## ⚠️ Dürüst Performans Notu (önce bunu okuyun)

Aşağıdaki backtest rakamları (örn. "%341 getiri / Sharpe 2,46 / %297 alfa") **iyimser
birer üst sınırdır, gerçekçi beklenti değildir**:

- **Survivorship:** evren her zaman *bugün listede olan* hisselerden çekilir; delist olan
  kaybedenler hiç dahil edilmez. Gelişmekte olan piyasada bu tek başına alfayı kayda değer
  şişirir.
- **Kısa örnek + in-sample:** ~21 aylık tek bir dönem; parametreler (TopN, maliyet, eşikler)
  aynı dönemde seçilmiş, gerçek bir out-of-sample / walk-forward doğrulaması **yoktur**.
- **En önemlisi — botun KENDİ canlı takibi backtest'le çelişiyor:** ileriye dönük izlenen
  sinyal performansı (`data/signal_performance.json`) bugüne kadar **~%47 isabet ve ≈0
  (hatta hafif negatif) edge** gösteriyor. Yani **kanıtlanmış bir alfa henüz yoktur**; bot
  bir *araştırma/gözlem aracı* olarak değerlendirilmelidir, "kazandıran sistem" olarak değil.

Skorlama eşik/ağırlıklarının çoğu **elle seçilmiştir** (veriyle kalibre/OOS doğrulanmamış);
"earnings surprise" gerçek analist konsensüsü içermediğinden trend-temelli bir vekildir
(rapor bunu açıkça belirtir). Backtest motoru gerçekçi dolum (komisyon+kayma+ADV) ve kurumsal
metrikler üretir ama yukarıdaki kısıtlar baskındır.

## Mimari (tek kaynak + kalıcı state)

- Workflow doğrudan repodaki `GunlukRapor.ps1` ve `BistScanner.Core.psm1`'i çalıştırır
  (eski "base64 runtime zip" kaldırıldı). **Repoda gördüğünüz kod = çalışan kod.**
- **State git'te kalıcıdır:** model portföyler, anlık fırsat portföyü, sinyal
  performansı, PEAD, kalibrasyon, paper emir niyetleri, PaperBroker defteri ve
  point-in-time snapshot dosyaları her başarılı çalışmada `data/` altına commit
  edilir (`[skip ci]`). Böylece geçmiş cache tahliyesine bağlı kalmaz, git'te
  görünür/denetlenebilir olur.
- Dayanıklılık: tüm dış veri çağrıları üstel beklemeli **retry**'lıdır; hata olursa
  best-effort **hata bildirimi e-postası** gönderilir; aynı anda iki çalışma
  state'i bozmasın diye `concurrency` kilidi vardır.

## Zamanlama ve Otomatik Çalışma (önemli)

Günlük rapor workflow'u (`bist-cloud-report.yml`) artık **yalnızca
`workflow_dispatch`** ile tetiklenir; GitHub'ın kendi `schedule` (cron) tetikleyicisi
ve `push` tetikleyicisi **kaldırıldı**. Nedeni: GitHub'ın zamanlanmış işleri yoğun
saatlerde **1,5–4 saat gecikebiliyordu** (mailler çok geç geliyordu).

Bunun yerine zamanlama **harici, ücretsiz bir servisle** (örn. **cron-job.org**)
yapılır: servis her hafta içi tam **18:15 Europe/Istanbul**'da GitHub API'sinin
`workflow_dispatch` ucunu çağırır; `workflow_dispatch` gecikmesiz tetiklendiği için
rapor saatinde çıkar.

Kurulum (bir kez):
1. GitHub'da **fine-grained personal access token** üret — sadece bu repo, izin:
   **Actions: Read and write**. (Token'ı kimseyle paylaşma; süresi dolunca yenile.)
2. cron-job.org'da bir iş oluştur:
   - URL: `https://api.github.com/repos/neccoju/bist-rapor-botu/actions/workflows/bist-cloud-report.yml/dispatches`
   - Method: `POST` · Body: `{"ref":"main"}`
   - Header'lar: `Authorization: Bearer <TOKEN>`, `Accept: application/vnd.github+json`,
     `X-GitHub-Api-Version: 2022-11-28`
   - Zaman: Europe/Istanbul, 18:15, Pazartesi–Cuma.
3. Dilediğinde `Actions → BIST Cloud Report → Run workflow` ile elle de tetiklenir.

## Tam Otomasyon Hattı (Pipeline / Katar) — uçtan uca günlük akış

Sistem **üç bağımsız iş**ten (job) oluşur. Hepsi harici zamanlayıcı (cron-job.org)
ile tetiklenir, birbirine **yalnız git'e commit edilen JSON dosyaları** üzerinden
bağlıdır (gevşek bağlılık) ve biri çökse diğerleri çalışır. Bütün KAP/yorum akışı
**gözlem modu**dur — skoru/portföyü/kararı ETKİLEMEZ.

```
  GÜN İÇİ (her ~5 dk, 17:00–17:35)         17:45                 18:15
  ┌─────────────────────────┐      ┌──────────────────┐   ┌──────────────────┐
  │ 1) KAP COLLECTOR         │      │ 2) KAP ENRICH    │   │ 3) GÜNLÜK RAPOR  │
  │ kap-collector.yml (ubuntu)│ ──▶ │ kap-enrich.yml   │──▶│ bist-cloud-report│
  │ borsapy ile KAP başlıkları│      │ izlenenleri LLM  │   │ .yml (windows)   │
  │ → data/kap_disclosures.json│     │ (gpt-4.1) yorumlar│  │ tarar+skorlar+   │
  │   (biriktirir, dönüşümlü) │      │ → kap_enrichment │   │ mail atar        │
  └─────────────────────────┘      └──────────────────┘   └──────────────────┘
        yazar ▼                          yazar ▼               okur ▲  ▲
     data/kap_disclosures.json   data/kap_enrichment.json ─────┘  │
                └──────────────────── ikisini disclosureId ile birleştirir ┘
```

### 1) KAP Collector — `kap-collector.yml` (ubuntu, Python/borsapy)
- **Ne yapar:** borsapy ile BIST hisselerinin KAP **başlıklarını** çeker, kategori/
  önem/yön etiketler, `data/kap_disclosures.json`'a **biriktirerek** yazar (merge,
  `disclosureId` ile tekilleştirme).
- **Dönüşümlü:** her koşu 100 hisse (saf rotasyon); `rotationCursor` git'te tutulur.
  777 hisse 8 partide tam tur. Throttle güvenli bölge (~100 istek/koşu).
- **Tetikleme:** cron-job.org, **17:00–17:35 arası her 5 dk** (8 parti → tüm evren).
- **İzin/secret:** `contents: write` (JSON'u commit eder). Ekstra anahtar yok.
- **Çıktı:** `data/kap_disclosures.json` (başlık + kategori + önem + yön + URL).

### 2) KAP Enrich — `kap-enrich.yml` (ubuntu, Python)
- **Ne yapar:** `kap_disclosures.json`'dan **izlenen hisselerin** (Top picks +
  model portföy + anlık giriş; bot state'inden) **son gün** önemli bildirimlerini
  alır, her birinin **gövde metnini** borsapy `get_news_content` ile çeker, **LLM**
  ile yorumlar → **özet + yön + etki (1-5) + tutarlar** → `data/kap_enrichment.json`
  (ayrı dosya; collector'la yazma yarışı yok).
- **Motor (varsayılan):** GitHub Models + **`openai/gpt-4.1`** (ücretsiz,
  `GITHUB_TOKEN`). Alternatifler: groq / opencode / openrouter / cerebras / llm
  (Claude) / rules. (Bkz. "İçerik yorumlama".)
- **Token tasarrufu:** sadece izlenenler + son gün + ≤25 → günde ~5-10 çağrı.
- **Tetikleme:** cron-job.org, **~17:45** (collector bitince, rapordan önce), günde 1.
- **İzin/secret:** `contents: write` + `models: read`; `GITHUB_TOKEN` (varsayılan
  motor). Diğer motorlar için ilgili secret (GROQ_API_KEY, OPENCODE_ZEN_API_KEY,
  ANTHROPIC_API_KEY...) opsiyonel.
- **Çıktı:** `data/kap_enrichment.json` (disclosureId → özet/yön/etki/tutar).

### 3) Günlük Rapor — `bist-cloud-report.yml` (windows-2025, PowerShell)
- **Ne yapar:** TradingView'den ~600 hisseyi tarar, skorlar, 6 model portföy +
  anlık fırsat portföyünü değerler, makro/gözlem göstergelerini üretir, **KAP
  bölümünü** `kap_disclosures.json` (son gün) + `kap_enrichment.json`'u
  **disclosureId ile birleştirerek** ("Yorum" sütunu = LLM özeti + etki) oluşturur,
  HTML/CSV üretir, **e-posta (+Telegram)** gönderir, sonra **bot state'ini commit**
  eder.
- **Akış kapısı:** önce `Test-BistScanner.Core.ps1` (smoke + birim test) geçmeli.
- **Tetikleme:** cron-job.org, **18:15 Europe/Istanbul, Pzt–Cuma**.
- **İzin/secret:** `contents: write` + `actions: write`; SMTP/Telegram/EVDS
  secret'ları (bkz. "Gerekli GitHub Secrets").
- **Çıktı:** e-posta raporu + `data/*.json` state (model portföy, sinyal performansı,
  PEAD, snapshot...).

### Veri akışı ve kalıcılık
- Tek tutkal **git'e commit'li `data/*.json`**: collector yazar → enrich okur+yazar
  → rapor okur. Pencereler (collector commit'leri, enrich commit'i) farklı saatlerde
  olduğu için çakışma yok; hepsinde `git pull --rebase` + retry var.
- **Bağımsızlık:** enrich çökse rapor başlık-bazlı KAP'ı yine gösterir; collector
  çökse rapor son commit'li veriyi okur; rapor çökse toplayıcılar etkilenmez.
- **Commit'ler `[skip ci]`** taşır (collector/enrich), sonsuz tetikleme olmaz.

### cron-job.org — kurulması gereken 3 iş (hepsi POST, Europe/Istanbul, Pzt–Cuma)
| İş | URL (`.../workflows/<dosya>/dispatches`) | Zaman | Gövde |
|---|---|---|---|
| Collector | `kap-collector.yml` | 17:00–17:35, her 5 dk | `{"ref":"main"}` |
| Enrich | `kap-enrich.yml` | 17:45 | `{"ref":"main"}` |
| Rapor | `bist-cloud-report.yml` | 18:15 | `{"ref":"main"}` |

Header'lar (üçünde de): `Authorization: Bearer <PAT>`,
`Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`. PAT:
fine-grained, bu repo, **Actions: Read and write**. Girdiler boş bırakılır
(varsayılanlar: collector 100/saf-rotasyon, enrich github/gpt-4.1/son-gün).

## Raporda Gelen Bölümler

- **Makro Görünüm:** BIST/BIST30/XBANK trendi, USD/TRY, Türkiye 5Y CDS, TR10Y faiz,
  DXY, VIX, TCMB fonlama faizi ve TÜFE (EVDS). Genel "Makro Zemin" durumu üretir
  (bağlam/teyit amaçlı; hisse skorunu doğrudan değiştirmez).
- **Top Radar:** strateji skoru, RFS100, AFS, görüş, teyit etiketi, temel/teknik/
  makro kolonları + veri-kalite özeti.
- **Akademik Çok-Faktör Skoru (AFS):** momentum 12-1 (Jegadeesh-Titman), kalite
  (Novy-Marx/RMW), değer, düşük volatilite (Frazzini-Pedersen), boyut faktörlerinin
  kesitsel z-skor karışımı; yıllık vol ve getiri/risk metrikleri.
- **Anlık Giriş Fırsatı + Anlık Fırsat Portföyü (kapalı döngü):** temel filtre + haftalık
  MACD ivmesi + 52 hafta konumu + BIST rejimi; çok güçlü sinyalde teorik alım kaydı.
  Portföy **kapalı döngü** çalışır: **100.000 TL sermaye**, günde en fazla **5.000 TL yeni
  alım**. Risk kuralıyla (stop/kâr-al/iz-süren) pozisyon kapanınca **satış hasılatı + kâr
  nakde döner** ve sonraki günlerde tekrar girişte kullanılabilir; **nakit bitince** (sermaye
  tamamen pozisyonlarda) yeni alım durur, bir satış nakit serbest bırakınca devam eder.
  Nakit, değişmez işlem defterinden türetilir (`Get-InstantEntryCashTL`; idempotent: nakit =
  sermaye − kümülatif alım + kümülatif satış hasılatı). Rapor temiz bir özet verir: toplam
  girilen (kümülatif), hissede duran güncel değer, kâr-satışı/gerçekleşen K/Z, kullanılabilir
  nakit ve 100k'ya göre toplam getiri.
- **Yaklaşan Bilanço Takvimi:** son/sonraki bilanço tarihi + kalan gün + olay-riski
  uyarısı (bilançoya ≤7 gün kala skorda ceza).
- **Bilanço Öncesi İvme Radarı (anticipation):** yaklaşan bilanço + güçlenen
  fiyat/hacim; skora küçük bonus.
- **Bilanço Sonrası Sürüklenme (PEAD) Takibi:** yeni bilanço açıklayanları tespit
  fiyatı + sürpriz proxy'siyle izler, ~28 gün sonra sürüklenmeyi ölçer.
- **KAP Son Bildirimleri (deneysel — gözlem):** ayrı bir işle (borsapy) tüm BIST
  için toplanıp `data/kap_disclosures.json`'a yazılan bildirimleri okur; kategori +
  yön ipucu (🟢/🔴/🟡/⚪/❔) gösterir, gürültüyü eler, Top radar hisselerini öne alır.
  Dosya yoksa canlı best-effort'a düşer, o da boşsa bölüm boş kalır. (Bkz. "KAP
  Bildirim Toplayıcısı".)
- **Skor İsabet Takibi (öz-değerlendirme):** Top seçimlerin sonraki getirisini tüm
  evren ortalamasıyla kıyaslayıp yuvarlanan isabet oranı (hit-rate) + getiri
  avantajı (edge) üretir.
- **Sektör Rotasyonu:** günlük/haftalık/1A/3A/1Y sektör vs BIST100 farkları.
- **Model Portföyler (aylık):** Dengeli/Değer/Momentum/Kalite (Get-BistScore) +
  RFS100 (ham teknik faktör) + ayrı `RiskDengeli` portföy. Aşağıya bakın.
- **Risk / Exit Paneli:** her model portföy pozisyonu için teorik stop seviyesi,
  risk kararı (`Tut`, `Azalt`, `Stop Adayı`, `Kar Al / Stop Yükselt`) ve gerekçe.
- **Paper Order Intents + PaperBroker:** gerçek emir göndermez; botun ürettiği
  teorik AL/SAT niyetlerini ve kağıt üzerinde doldurulmuş pozisyon defterini raporlar.
- **Getiri Karşılaştırma Grafiği (mailin en altında):** tek bir çizgi grafik —
  X ekseni tarih, Y ekseni % getiri. Tüm model portföyler + BIST100 + Altın +
  Mevduat + Nasdaq + S&P 500'ün TRY bazında getirisini gösterir. Aşağıya bakın.
- **Gözlem Göstergeleri (deneysel — karar etkisi yok):** üç yeni gösterge **yalnız
  raporda** gösterilir; skoru/portföy seçimini/ağırlıkları **değiştirmez** (gözlem
  modu). (1) **Piyasa genişliği:** evrenin yüzde kaçı 200/50 günlük ortalama üstünde
  ve son ayda pozitif — dar genişlik kırılgan yükseliş işareti. (2) **Göreli Güç (RS)
  liderleri:** her hissenin BIST100'e göre kesitsel güç sırası (0-100); en güçlü 10.
  (3) **Risk/Ödül (R:R):** portföy pozisyonları için stop mesafesine karşı 52 hafta
  zirvesine uzaklık. Veri birikince hangisinin ayrıştırıcı olduğu değerlendirilip
  karara bağlanacaktır.

## Model Portföyler — ne zaman, nasıl seçer?

Bot 6 model portföy yönetir: **Dengeli, Değer, Momentum, Kalite** (klasik strateji
skoruyla), **RFS100** (ham teknik faktör skoruyla — **statik** backtest ağırlıkları)
ve **Risk Dengeli** (Dengeli seçimi + volatilite-tersi ağırlık). Hepsi 100.000 TL ile
başlar ve teoriktir (gerçek emir yok).

Yeterli PIT verisi birikip öğrenme gerçekleştiğinde **7.** bir portföy otomatik eklenir:
**Öğrenen Algoritma** (`OgrenenAlgoritma`) — botun çeyreklik walk-forward IC
oto-kalibrasyonuyla **kendi öğrendiği** faktör ağırlıklarıyla kurulan 5 hisselik portföy.
Öğrenme gerçekleşene kadar **oluşturulmaz** (veri-kapılı). RFS100 statik temel çizgiyi
korur; Öğrenen Algoritma öğrenilmiş ağırlıkları uygular — ikisi **yan yana** izlenerek
öğrenmenin gerçek alfa katkısı ölçülebilir.

### Ne zaman alım/satım yapılır?
- **Yalnız ayın son BIST işlem gününde** yeniden dengelenir (rebalance: sıralama +
  AL/SAT/EŞİTLEME). Diğer tüm günlerde portföy **sadece değerlenir**, hisseler
  değişmez. Tatil/hafta sonu `Get-BistFullClosureDates` ile dışlanır (2026-2030
  dini bayramlar dahil). Yani bir hata gördüğünüzde düzeltme bir sonraki ay-sonu
  rebalance'ında devreye girer; ara günlerde portföy aynı kalır.

### Bir portföy 5 hissesini nasıl seçer? (adım adım)
1. **Skorla:** Tüm evren `Get-BistScore` ile o stratejinin ağırlıklarıyla puanlanır
   (7 bileşen: Trend, Değer, Kalite, Bilanço, Momentum, Likidite, Makro/Sektör).
2. **Uygunluk filtresi** (`Test-ModelPortfolioEligibleStock`): bir hisse portföye
   girebilmek için **hepsini birden** geçmeli — geçerli fiyat, piyasa değeri ≥ 5
   milyar TL, yeterli hacim, son çeyrek pozitif kâr + ≥3 çeyrek pozitif kâr/FAVÖK,
   ROE ≥ %10 (finans hariç), FD/FAVÖK ≤ 12 (finans hariç), makro/sektör puanı ≥ 35,
   teknik teyit (200 günlük ortalama üstü / MACD / RSI 40-65 / hacim — en az 2'si),
   **veri kalitesi kapısı**, **aşırı volatilite kapısı** (günlük oynaklık > 8 elenir)
   ve "yüksek risk" olmaması.
3. **Strateji-özgü sıralama** (`Get-StrategySelectionScore` — bkz. aşağıdaki kutu):
   uygun hisseler stratejinin **kendi karakterine** göre sıralanır.
4. **Sektör sınırı + Top 5:** sektör başına en fazla 2 hisse kuralıyla en yüksek
   5 hisse seçilir (5'e ulaşılamazsa sınır gevşetilerek tamamlanır).
5. **Eşit ağırlık:** Dengeli/Değer/Momentum/Kalite/RFS100/Öğrenen Algoritma
   portföylerinde 5 hisse × %20. (Risk Dengeli farklı; aşağıda.)

### Strateji-özgü seçim — portföyler neden artık birbirinden farklı?
> **Geçmişteki sorun:** Dört strateji de seçimi doğrudan genel `Score` ile
> sıralıyordu. `Score`, her stratejide yüksek ağırlıklı ve **stratejiden bağımsız**
> olan Makro/Sektör + Bilanço bileşenlerince domine edildiği için sıralama
> stratejiden bağımsız hale geliyordu. Sonuç: **Dengeli = Momentum** ve
> **Değer = Kalite** aynı hisseleri seçiyordu.
>
> **Çözüm:** Artık seçim sıralaması her stratejinin **kendi ekseni**ne ~%85 ağırlık
> verir (`Get-StrategySelectionScore`); %15 genel `Score` kalite tabanı olarak kalır.
> Rapordaki görünür `Score` değişmedi, yalnız **seçim sıralaması** ayrıştırıldı:
> - **Dengeli** → genel `Score` (kasıtlı olarak dengeli/genel)
> - **Momentum** → `MomentumScore` + `TrendScore` (trend, RSI, MACD, hacim ivmesi)
> - **Değer** → `ValueScore` (F/K, PD/DD, FD/FAVÖK ucuzluğu)
> - **Kalite** → `QualityScore` + `EarningsScore` (ROE, bilanço gücü, FAVÖK sürekliliği)
>
> Doğrulama: `Simulate-RebalanceSeparation.ps1` ile canlı veride çalıştırıldığında
> önceden 5/5 çakışan çiftler **2/5'e düştü** (gerçekten ayrıştı). Birim test
> (`Test-BistScanner.Core.ps1`) sentetik havuzda kesişimi 0 ölçer.

### Diğer kurallar
- **Risk Dengeli** ayrı izlenir: seçim yine Dengeli skoruyla yapılır (yani Dengeli
  ile aynı 5 hisseyi tutması normaldir), **fark hisse değil ağırlıktır**: ağırlıklar
  günlük volatilitenin tersine göre dağıtılır, tek hisse riskini sınırlamak için
  min/max ağırlık sınırı uygulanır. Normal portföylerin eşit ağırlığı bundan etkilenmez.
- **İşlem maliyeti + kayma** modellenir (varsayılan 20 bps; `BIST_MODEL_COST_BPS`
  veya config `ModelPortfolioCostBps`); raporlanan getiriler **nettir**.
- **BIST100 alfa:** her portföyün kuruluştan beri getirisi BIST100 ile kıyaslanır;
  **Alfa = getiri − BIST100**. Hangi stratejinin endeksi yendiğini gösterir.
- **Maksimum düşüş (drawdown)** her değerlemede izlenir.
- **Lider strateji:** rapor, alfaya göre en iyi stratejiyi öne çıkarır.

## Platform Kontrolleri

- **Risk kuralları:** `config/report_settings.*.json` içindeki `RiskRules`
  bloğu teorik stop-loss, zarar azaltma, kar alma, iz süren stop ve minimum elde
  tutma skoru eşiklerini belirler. Bu kararlar raporda uyarı/denetim amaçlıdır;
  gerçek emir üretmez.
- **PaperBroker / OrderIntent:** günlük raporun ürettiği teorik AL/SAT işlemleri
  `data/order_intents.json` içine yazılır; `data/paper_broker.json` bu niyetleri
  kağıt üzerinde doldurulmuş varsayan ayrı bir denetim defteridir. Aracı kurum
  entegrasyonu yoktur ve varsayılan mod `PaperOnly` kalır.
- **Point-in-time snapshot arşivi:** her başarılı çalışmada en yüksek skorlu
  kompakt evren kesiti `data/latest_point_in_time_snapshot.json` (sonraki koşu için)
  ve tarihli `data/point_in_time_snapshots/YYYYMMDD_HHMM.json` altında üretilir. Amaç,
  gelecekte lookahead/survivorship riskini azaltan **as-observed** canlı veri arşivi
  oluşturmaktır. **Otomatiktir** ve `main`'i şişirmez: tarihli snapshot'lar git'e
  `main`'e değil, ayrı bir **`pit-archive`** orphan branch'ine push edilir (normal
  clone/checkout bu branch'i çekmez). Böylece arşiv gün gün ileriye dönük birikir.

## Getiri Karşılaştırma Grafiği

Raporun en altına, **100.000 TL'yi farklı yerlere koysaydım ne olurdu?** sorusunu
yanıtlayan tek bir çizgi grafik eklenir (X = tarih, Y = % getiri). Aynı grafikte:

- Tüm model portföyler (Dengeli/Değer/Momentum/Kalite/RFS100/Risk Dengeli)
- **BIST100** endeksi
- **Altın** (TRY) — ons altın × USD/TRY
- **Nasdaq** ve **S&P 500** (TRY) — endeks × USD/TRY (yani döviz etkisi dahil)
- **Mevduat** (yaklaşık) — TCMB EVDS faiz serisinden bileşik birikim

Nasıl çalışır:
- **Model portföy çizgileri** her portföyün işlem geçmişi (`Transactions`) + Yahoo
  günlük kapanışlarıyla **kuruluştan bugüne yeniden kurulur** (point-in-time;
  rebalance'ları doğru yansıtır). Grafik her çalışmada otomatik bir gün uzar.
- **Benchmark çizgileri** Yahoo + EVDS'ten tarihsel çekilir; yabancı varlıklar ve
  altın USD/TRY ile TRY'ye çevrilir. Hepsi aynı başlangıç gününde %0'dan başlar.
- Grafik **QuickChart** ile çizilir ve e-postaya **dış görsel URL'i** olarak
  gömülür (CID gömülü görsel Gmail'de tutarsız göründüğü için bu yönteme geçildi).
  Grafik üretilemezse rapor bir **özet tablo** ile yine sayısal karşılaştırmayı verir.
- Gmail ilk seferde "görselleri göster" diyebilir; "her zaman göster" dersen
  sonraki maillerde otomatik açılır.

> Not: Model portföyler ilk kuruldukları tarihten itibaren çizilir; geçmişe
> uzatılmaz (o tarihten önce portföy yoktu). Grafik gün geçtikçe dolar.

## Gözlem Göstergeleri (deneysel — karar etkisi YOK)

Raporun en altında, **"🔬 Gözlem Göstergeleri"** başlıklı bir bölüm vardır. Buradaki
üç gösterge **yalnız bilgi amaçlıdır**: skoru, portföy seçimini ve ağırlıkları
**değiştirmezler**. Amaç, bir özelliği karara bağlamadan önce canlı veride birkaç
hafta izleyip gerçekten ayrıştırıcı olup olmadığını görmektir ("önce göster, sonra
karara bağla" — overfitting'e karşı koruma). Veriler birikince, işe yarayanlar
**senin onayınla** Aşama 2'de (config bayrağıyla) skora/seçime bağlanabilir.

### 1. Piyasa genişliği (market breadth)
- **Ne ölçer:** Taranan tüm evrende (≈600 hisse) yüzde kaç hissenin 200 ve 50 günlük
  ortalamasının üzerinde olduğunu ve son ayda pozitif getirdiğini. Bir özet etiket
  üretir: **Dar / Orta / Geniş**.
- **Neden önemli:** Endeks birkaç dev hisseyle yükseliyor olabilir; genişlik "yükselişe
  kaç hisse gerçekten katılıyor?" sorusunu yanıtlar. **Dar** genişlik kırılgan/tepe
  işareti, **geniş** genişlik sağlıklı katılımdır.
- **Veri:** Ekstra kaynak yok — mevcut tarama üzerinde sayım (`Get-MarketBreadth`).

### 2. Göreli Güç (RS) sırası
- **Ne ölçer:** Her hissenin **BIST100'e göre** gücünü 0-100 arası bir sıraya çevirir
  (mutlak getiri değil — "endeksten daha mı iyi?"). Fazla-getiri ağırlıklı hesaplanır
  (%50 × 3 aylık + %30 × 1 yıllık + %20 × 1 aylık, hepsi endekse göre). Rapor en
  güçlü 10 hisseyi listeler.
- **Neden önemli:** İki hisse de %10 yükselmiş olabilir; ama BIST %20 yükseldiyse
  ikisi de aslında zayıftır. RS bunu yakalar — momentum yatırımının temel taşıdır.
- **Veri:** Ekstra kaynak yok — skorlanmış hisselerdeki getiri alanlarından
  (`Add-RelativeStrengthRank`).

### 3. Risk/Ödül (R:R)
- **Ne ölçer:** Model portföy pozisyonları için **olası kayıp** (stop mesafesi) ile
  **olası kazanç** (52 hafta kapanış zirvesine uzaklık) oranını. R:R ≥ 2 tercih edilir
  (1 birim riske en az 2 birim kazanç beklentisi).
- **Neden önemli:** Skoru yüksek ama yukarı alanı az / stopu uzak (büyük zarar riski)
  hisseleri görünür kılar. Uzun vadede kazandıran, kazançların kayıplardan büyük olmasıdır.
- **Veri:** Stop = `RiskRules` (varsayılan %8); 52h zirve, performans grafiğinin zaten
  çektiği fiyat önbelleğinden alınır — **ekstra ağ çağrısı yok**.

> Bu üç gösterge `Test-BistScanner.Core.ps1` içinde birim testlidir ve rapor bölümü
> best-effort'tur (hata olsa bile rapor normal çıkar). Hiçbiri "getiriyi katlar"
> iddiası taşımaz; kötü alımları azaltıp seçim kalitesi/risk farkındalığını artırmayı
> hedefler.

## Kendini Öğrenen / Öz-Değerlendiren Mekanizmalar

- **Sinyal isabet takibi** (`signal_performance.json`): skorun ayrıştırıcılığını ölçer.
- **PEAD takibi** (`earnings_reactions.json`): bilanço sonrası gerçekleşen sürüklenme.
- **Sinyal kalibrasyonu** (`signal_calibration.json`): PEAD verisi yeterince birikince
  (≥30 yönlü örnek) bilanço-sonrası skor ayarını (sell-the-news cezası ↔ PEAD bonusu)
  **veriye göre otomatik günceller**; yoksa güvenli varsayılana (−3) düşer.
- **Dinamik enflasyon:** TÜFE kıyaslaması TCMB EVDS endeksinden (TP.FG.J0) 1Y/3Y/5Y
  birikimli olarak otomatik hesaplanır; EVDS yoksa statik değere düşer.
- **Kendi içinde süren oto-kalibrasyon (PIT backtest → faktör ağırlığı öğrenme →
  yeni portföy):** `auto-calibrate.yml` **her ayın 1'i otomatik** çalışır;
  `pit-archive` branch'indeki survivorship/look-ahead'siz PIT arşivinden **walk-forward**
  bir değerlendirme yapıp faktör ağırlıklarını yeniden öğrenmeyi dener
  (`Invoke-AutoCalibration.ps1` → `data/learned_factor_weights.json`).
  - **Çıktı = yeni bir model portföy:** öğrenme gerçekleştiğinde **Öğrenen Algoritma**
    (`OgrenenAlgoritma`) portföyü otomatik oluşturulur ve öğrenilmiş ağırlıklarla 5 hisse
    seçer. **RFS100 statik backtest temel çizgisini korur** (öğrenme onu değiştirmez); iki
    portföy yan yana izlenerek öğrenmenin gerçek katkısı ölçülür (A/B).
  - **Yöntem (overfit'e dirençli):** her faktör için kesitsel **IC** (Pearson; faktör ↔
    ileri ~1 aylık getiri), **çakışmayan/bağımsız** dönemler arası ortalama → çok-değişkenli
    regresyonun aşırı-uyum/çoklu-doğrusallık riski ve otokorelasyonla şişme alınmaz; sonuç
    prior ağırlıklara doğru **büzülür** (shrinkage) ve sınırlanır.
  - **Veri kapısı (dürüst) + kendi kendine devam:** yeterli **bağımsız** dönem (≥8) birikene
    kadar **hiçbir şey değişmez** — kuşu commit atmaz, `main`'e dokunmaz, Öğrenen Algoritma
    portföyü **oluşturulmaz** — ve bir **sonraki ay otomatik tekrar denenir**. Yani "3 ay
    yetmezse 5./6./8. ay": arşiv yeterince birikene kadar döngü kendiliğinden bekler, hazır
    olduğu an öğrenir ve **yeni model üretir**. Her ay ~1 bağımsız dönem eklendiğinden öğrenme
    tipik olarak birkaç ay sonra devreye girer. Delist olan hisseler hariç tutulur (hafif
    survivorship — açıkça not edilir).
  - **Kapsam:** yalnızca yeni **Öğrenen Algoritma** portföyünü besler; RFS100 dahil diğer 6
    portföyün ağırlıkları/skoru bilinçli olarak değişmez (tüm botu otomatik optimize edip
    overfit etme riski alınmaz).

## Veri Kaynakları ve Çoklu-Kaynak Yedekleme

- **TradingView** (ana tarama: fiyat/temel/teknik; ayrıca TR10Y için `TVC:TR10Y`).
- **Yahoo Finance** (haftalık/günlük fiyat; makro yedeği: USD/TRY=X, DXY `DX-Y.NYB`,
  VIX `^VIX`; backtest için günlük OHLC).
- **TCMB EVDS** (fonlama faizi, TÜFE, dinamik enflasyon; TR10Y opsiyonel seri).
- **TCMB kur arşivi** (USD/TRY birincil).
- **Investing.com** (CDS/TR10Y için best-effort; runner'dan sık 403).
- Makro metrikler çoklu-kaynak fallback'iyle gelir: USD/TRY → TCMB→Yahoo; DXY/VIX →
  Yahoo→Investing; TR10Y → EVDS→TradingView→Investing. (CDS'nin güvenilir ücretsiz
  kaynağı yoktur; erişilemezse "Veri Yok".)

## KAP Bildirim Toplayıcısı (katar mimarisi — gözlem modu)

KAP'ın (Kamuyu Aydınlatma Platformu) resmî/ücretsiz bir JSON API'si yoktur ve
runner'dan doğrudan HTTP çağrıları 403 döner. Bu yüzden bildirimler **ayrı, gevşek
bağlı bir işle** toplanır ve repoya yazılır; ana PowerShell raporu bu dosyayı
**yalnız okur**. İki taraf birbirinden bağımsızdır: toplayıcı çökse bile rapor
çalışır, rapor değişse bile toplayıcı etkilenmez.

**Akış (katar):**

1. **Toplayıcı** — `collect_kap.py` (Python, `borsapy` kütüphanesi) ayrı bir
   **ubuntu** job'ında (`.github/workflows/kap-collector.yml`) çalışır. `borsapy.companies()`
   ile tüm BIST kodlarını (~777) bulur, **o günün dilimindeki** hisseler için
   `Ticker(sym).news` ile son bildirimleri çeker (Chromium gerekmez), başlığa göre
   **kategori + önem + yön** etiketler ve `data/kap_disclosures.json`'a
   **biriktirerek** yazar.
2. **Depo** — JSON git'te tutulur; böylece Windows runner'daki rapor onu checkout'la
   hazır bulur. Tek yön: Python yazar, PowerShell okur.
3. **Okuyucu** — `Get-StoredKapDisclosures` (çekirdek modül) JSON'u **best-effort**
   okur (sembol/önem/`-MaxAgeDays` filtresi, tarihe göre sıralama; dosya yoksa boş
   döner). `GunlukRapor.ps1` "KAP Son Bildirimleri" bölümünü bundan üretir; gürültü
   (`önem=noise`) elenir, Top radar hisseleri öne alınır.

**Biriktirme + dönüşümlü tarama, küçük partiler (neden böyle):**
borsapy/KAP kaynağı **~100 hızlı istekten sonra** bağlantıyı keserek throttle eder
(canlı ölçüm: 100 hisse 99 sn, **0 hata**; 100'ün üstünde hata patlaması, ilk tam
denemede 777 hissenin 656'sı "Server disconnected"). Bu yüzden tüm evren tek
seferde değil, **gün içinde küçük partiler** halinde toplanır:

- **Varsayılan: saf rotasyon, parti başına 100 hisse** (`--rotate-size 100`,
  `--no-priority`). `rotationCursor` JSON'da tutulur, sonraki parti **kaldığı
  yerden** devam eder. 100 istek ≈ **99 sn, 0 hata** → güvenli eşik.
- **Biriktirme:** Çekilen yeni bildirimler ilgili hissenin **arşivine**
  `disclosureId` ile **tekilleştirerek eklenir** (tekrarları atlar, eskileri korur;
  hisse başına en fazla `--max-archive`=40 kayıt). O partide sıraya gelmeyen
  hisseler önceki verisini **aynen korur** (silinmez).
- 777 hisse, 100'erden **~8 partide** tam tur atar. Partiler `concurrency` ile
  seri çalışır (push çakışması olmaz).
- **Opsiyonel öncelik:** `no_priority=false` ile Top picks + model portföy + anlık
  giriş holdingleri (botun state JSON'larından okunur) her partide **ek olarak**
  taranır — önemli hisseleri daha sık tazelemek istenirse. (Gevşek bağlılık: yalnız
  mevcut JSON'ları okur.)

**Zamanlama (cron-job.org):** Toplayıcı gün içinde **sık** tetiklenir; her tetikleme
sıradaki 100 hisseyi tarar, 8 tetikleme tüm evreni (777) bir tur kapsar. **Kurulu
düzen:** `kap-collector.yml`'yi **17:00–17:35 arası 5 dk'da bir** (8 parti) çağıran
bir cron-job.org işi → tüm evren bu pencerede bir kez taranır. Ana rapor
(`bist-cloud-report.yml`) **18:15**'te birikmiş `kap_disclosures.json`'u okur (son
7 gün filtresiyle). Partiler ~2 dk sürer; 5 dk aralık çakışmayı önler, son parti
(~17:37) ile rapor (18:15) arasında bol pay vardır. GitHub'ın kendi cron'u
geciktiği için harici tetikleyici kullanılır.
- cron-job.org isteği: `POST https://api.github.com/repos/neccoju/bist-rapor-botu/actions/workflows/kap-collector.yml/dispatches`,
  header `Authorization: Bearer <PAT>` + `Accept: application/vnd.github+json` +
  `X-GitHub-Api-Version: 2022-11-28`, gövde `{"ref":"main"}`, saat dilimi
  **Europe/Istanbul**. (Varsayılan girdiler: `rotate_size=100`, `no_priority=true`.)
- Daha sık/geniş istenirse pencere büyütülebilir; cursor git'te tutulduğu için
  ertesi gün kaldığı yerden döner (sıfırlama gerekmez).

**Kategoriler ve yön ipuçları** (başlık anahtar kelimesinden otomatik; kabadır,
**karar etkisi yoktur**, ilk eşleşen kazanır):

| Önem | Kategoriler | Yön |
|---|---|---|
| `high` (fiyat etkili olabilir) | Birleşme/Devralma, İhale/Sözleşme, Geri Alım, Temettü, Yatırım/Tesis, Varlık Alım/Satım, Sermaye Artırımı, Kredi Notu, Hukuki/Dava, Halka Arz, Özel Durum (Genel) | 🟢 olumlu · 🔴 olumsuz · 🟡 karışık · ❔ detay gerekir |
| `earnings` | Bilanço/Finansal | ⚪ nötr |
| `insider` | Insider/Pay Bildirimi | 🟡 bağlamsal |
| `governance` | Genel Kurul, Kurumsal Yönetim, Bağımsız Denetim, Hak Kullanımı, Şirket Bilgi | ⚪ nötr |
| `debt` | Borçlanma Aracı (tahvil/sukuk/ihraç/kupon/itfa) | ⚪ nötr |
| `noise` (raporda elenir) | Piyasa/Teknik (devre kesici, likidite sağlayıcılık, endeks/fiili dolaşım) | ⚪ |
| `other` | Diğer (eşleşmeyen) | ❔ |

> Türkçe `İ`/`I` tuzağı: Python `"İhale".lower()` → `"i̇hale"` (birleşik nokta)
> ürettiğinden ham `.lower()` ile `"ihale"` eşleşmez. `collect_kap.py._norm()`
> İ→i, I→ı dönüşümüyle Türkçe-güvenli küçük harf yapar; bu düzeltme 30 hisselik
> örnekte "Diğer" oranını **%58'den ~%0'a** indirdi.

### İçerik yorumlama (LLM) — `enrich_kap.py` + `kap-enrich.yml`

Başlık sınıflaması, "Özel Durum Açıklaması (Genel)" gibi kör başlıklarda yetersiz
(`❔`). Bu katman, **izlenen hisselerin son-gün önemli bildirimlerinin GÖVDE
metnini** borsapy `Ticker.get_news_content(disclosureId)` ile çeker ve bir LLM ile
yorumlar: **kısa özet + yön + etki skoru (1-5) + tutarlar**. Sonuç ayrı
`data/kap_enrichment.json`'a yazılır; rapor `disclosureId` ile birleştirip "Yorum"
sütununda gösterir. **Gözlem modu — karar etkisi yok.**

- **Motor (varsayılan): GitHub Models + `openai/gpt-4.1` — ÜCRETSİZ.** Actions
  `GITHUB_TOKEN` + `permissions: models: read`; OpenAI-uyumlu endpoint
  (`models.github.ai`), ek bağımlılık yok (urllib). gpt-4.1 ücretsiz katmanda
  güvenilir çalışır (429 yemez), olay/tarih/tarafı doğru yakalar, **bilmediğini
  uydurmaz** (tam rakam ek PDF'teyse bunu açıkça yazar).
- **Diğer motorlar (`model`/`engine` girdisiyle, `enrich_kap.py` preset):**
  `groq` (Llama-3.3-70B, ücretsiz anahtar, ~2 dk), `opencode` (OpenCode Zen
  ücretsiz modeller), `openrouter`, `cerebras`, `llm` (Claude — en keskin ama
  ücretli ~$0,05/gün), `rules` (LLM'siz anahtar kelime). Hepsi OpenAI-uyumlu tek
  yola bağlanır; sağlayıcı = base-url + token-env + model + içerik penceresi.
  > Not: DeepSeek-V3 / Kimi-K2 gibi DEV açık modeller ücretsiz katmanlarda ağır
  > rate-limit (429) yediği için güvenilir değil; bu yüzden varsayılan gpt-4.1.
- **Token tasarrufu:** yalnız **izlenen hisseler** (Top/portföy/anlık giriş; state
  JSON'larından) + **son gün** + en fazla 25 bildirim → günde ~5-10 çağrı. (Günde
  toplam ~90-108 "high" bildirim çıkar; hepsini değil, sadece izlenenleri yorumlar.)
- **İçerik çıkarımı:** KAP sayfası ~60-150 KB (menü/arama çöpü dahil) gelir;
  `_focus_content` ODA formundaki **"Özet Bilgi"** alanına sabitleyerek asıl metni
  küçük pencereye indirir (ücretsiz motorların istek limiti için şart; 60 KB → 413).
- **PDF ek ayrıştırma (tam rakamlar için — AKTİF):** KAP bildirimlerinde tam
  rakamlar (temettü TL, hisse başı, verim %, kredi notu) çoğu zaman **ekteki PDF'te**.
  `find_attachment_urls` bildirim sayfasından PDF/ek linkini bulur, `fetch_pdf_text`
  (`requests` + `pymupdf`, ikisi de borsapy bağımlılığı) PDF'i indirip metne çevirir;
  PDF metni varsa **LLM'e o (temiz, rakamlı) verilir** ve ayrıca PDF+sayfa regex
  tutarları LLM çıktısıyla birleştirilir. Sonuç: ENERY temettü → *"127,5 milyon TL,
  hisse başı 0,01417 TL, %2,92"* gibi **tam rakamlar ücretsiz** geliyor. (`--no-pdf`
  ile kapatılır; `--pdf-max-pages` ile sayfa sınırı.) Eki olmayan bildirimlerde
  sorunsuz sayfa metnine düşer.
- **Küçük pürüz:** gpt-4.1 (Azure barındırmalı) ara sıra bir bildirimi içerik
  filtresine takıp HTTP 400 verebilir (koşuda ~1/8); o kayıt atlanır, akış bozulmaz.
- **Denetim izi:** Her kayda LLM'e **gerçekten gönderilen** odaklanmış metnin ilk
  ~500 karakteri (`inputSnippet`), kaynağı (`inputSource`: pdf|page) ve boyutu
  (`inputChars`) yazılır; ayrıca `pdfUrls`/`disclosureId` ile tam girdi yeniden
  üretilebilir. Böylece "model neden böyle dedi?" denetlenebilir. (Tam girdi metni
  repo'yu şişirmemek için saklanmaz; gerekirse kaynaktan yeniden çekilir.)
- **Zamanlama:** collector partileri bittikten sonra, rapordan önce (örn. **17:45**)
  cron-job.org ile günde bir `kap-enrich.yml` tetiklenir.

## Dosyalar

- `.github/workflows/bist-cloud-report.yml` — günlük rapor (harici zamanlayıcı
  `workflow_dispatch` ile 18:15'te tetikler + elle çalıştırma).
- `GunlukRapor.ps1` — rapor motoru (orkestrasyon, HTML/CSV, e-posta/Telegram).
- `BistScanner.Core.psm1` — tarama, skorlama, AFS, model portföy, makro, EVDS,
  PEAD/kalibrasyon, Yahoo/TradingView yardımcıları.
- `Test-BistScanner.Core.ps1` — workflow başında çalışan smoke + birim testler
  (strateji ayrışma testi dahil).
- `Simulate-RebalanceSeparation.ps1` — strateji ayrışması canlı-veri doğrulaması.
- `collect_kap.py` + `.github/workflows/kap-collector.yml` — tüm BIST için KAP
  bildirim toplayıcısı (borsapy; `data/kap_disclosures.json` üretir/commit eder).
  Ayrı ubuntu job; ana botu etkilemez. (Bkz. "KAP Bildirim Toplayıcısı".)
- `enrich_kap.py` + `.github/workflows/kap-enrich.yml` — KAP içerik yorumlama (LLM):
  izlenen hisselerin son-gün önemli bildirimlerini GitHub Models + `openai/gpt-4.1`
  (ücretsiz; veya groq/opencode/llm...) ile özetler/yön/etki üretir →
  `data/kap_enrichment.json`. (Bkz. "İçerik yorumlama".)
- `BacktestEngine.psm1` / `Backtest-EventDriven.ps1` / `Test-BacktestEngine.ps1` —
  gerçek event-driven backtest motoru, koşucusu ve ağsız birim testi.
- `config/report_settings.cloud.json` / `.example.json` — ayarlar.
- `data/` — kalıcı bot state'i (git'te tutulur): `model_portfolios.json`,
  `instant_entry_portfolio.json`, `signal_performance.json`, `earnings_reactions.json`,
  `signal_calibration.json`, `order_intents.json`, `paper_broker.json`,
  `latest_point_in_time_snapshot.json` ve `point_in_time_snapshots/*.json`.
  Ayrıca KAP hattı: `kap_disclosures.json` (collector) ve `kap_enrichment.json`
  (enrich/LLM yorumları).
- `data/pit/` — point-in-time anlık görüntü arşivi (tarihli `YYYY-MM-DD.json`;
  her gün gözlenen evren + temel veri, ileri-bakış olmadan biriker).

### Analiz / araştırma araçları (elle tetiklenir; günlük raporu etkilemez)

- `Analyze-EarningsEventStudy.ps1` + `earnings-event-study.yml` — bilanço tarihi olay
  çalışması (run-up / tepki / drift korelasyonları).
- `Backtest-EventDriven.ps1` + `backtest-event-driven.yml` — **gerçek event-driven
  backtest** (aşağıya bakın); CI'da önce motorun ağsız birim testi çalışır. Eski
  `Backtest-ModelPortfolio.ps1` (momentum 12-1), `Backtest-Realistic.ps1` ve onun
  parametre taraması `Validate-StrategySweep.ps1` **bu motora taşındığı için kaldırıldı**
  (gerçekçi dolum + kurumsal metrikler hepsini kapsar).
- `BacktestEngine.psm1` — event-driven backtest çekirdeği (`Invoke-EventDrivenBacktest`).
- `Test-BacktestEngine.ps1` — motorun **ağsız, deterministik** birim testleri (CI kapısı).
- `Find-EvdsBondSeries.ps1` + `evds-discovery.yml` — EVDS seri kodu keşfi (tanılama).
- `Simulate-RebalanceSeparation.ps1` + `simulate-separation.yml` — strateji ayrışması
  **gerçek-veri doğrulaması**: verilen tarihli (vars. 30 Haziran) ay-sonu rebalance'ı
  güncel canlı taramayla simüle eder, 6 portföyün holding'lerini ve çiftler arası
  örtüşmeyi log'a yazar. **Gerçek state'e dokunmaz** (bellekte çalışır, kaydetmez).
- `Invoke-AutoCalibration.ps1` + `auto-calibrate.yml` → `data/learned_factor_weights.json`
  — **kendi içinde süren öğrenme** (her ay otomatik; elle tetikleme de var ama **gerekmez**).
  PIT arşivinden (pit-archive branch) walk-forward kesitsel IC ile faktör ağırlıklarını
  yeniden öğrenmeyi dener. Öğrenme gerçekleşince **Öğrenen Algoritma** (`OgrenenAlgoritma`)
  model portföyü otomatik oluşur ve bu ağırlıklarla 5 hisse seçer; RFS100 statik temel
  çizgi olarak kalır (A/B karşılaştırma). **Veri-kapılı**: yeterli bağımsız dönem birikene
  kadar prior korunur (commit yok, `main` dokunulmaz, portföy oluşmaz) ve sonraki ay tekrar
  denenir. Aşırı-uyum korumalı (IC + shrinkage + sınır + min-dönem); yalnız Öğrenen Algoritma
  portföyünü besler.

> Backtest uyarısı: ücretsiz veride **survivorship** (bugün listede olmayan/delist
> hisseler yok) ve geçmiş bilanço anlık görüntüsü eksikliği vardır; backtest
> rakamları **iyimser üst sınırdır**. Yanlılıksız ölçüm için bot **ileriye dönük
> canlı alfa**yı izler.

## Kurumsal-Seviye Altyapı

### Gerçek Event-Driven Backtest Motoru (`BacktestEngine.psm1`)

Eski "aylık döngü" yaklaşımının aksine motor **günlük olay ekseninde** ilerler:
her gün **mark-to-market**; ay sonu rebalance günlerinde sinyal **yalnız o güne
kadarki** fiyat/hacimle hesaplanır (point-in-time, ileri-bakış yok). Dolum
gerçekçidir: komisyon + kayma + **karekök piyasa-etkisi** (işlem TL / günlük TL
hacim) + **ADV katılım sınırı** (`MaxAdvMultiple`: tek isimde günlük hacmin en
fazla bu katı kadar pozisyon → likidite gerçekçiliği). Tam nakit/pozisyon defteri
tutulur. Kurumsal metrikler üretir: CAGR, yıllık vol, **Sharpe, Sortino, Calmar**,
maks düşüş, yıllık **turnover**, BIST100'e karşı **alpha**, aylık **isabet** ve
eşitlik eğrisi. Çekirdek **ağsızdır ve deterministik test edilir**:
`Test-BacktestEngine.ps1` elle hesaplanmış "golden" değerlerle defter korunumu,
maliyet, ADV sınırı, alım/satım geçişi ve metrikleri doğrular; backtest
workflow'unda **kapı** görevi görür.

Çalıştırma: `Actions → Model Portfolio Backtest (Event-Driven) → Run workflow`.
Komisyon/kayma/likidite parametreleri girişten ayarlanır.

#### Örnek canlı koşu (Eylül 2024 → Haziran 2026)

100.000 TL başlangıç, 300 hisselik evren, Top 5 eşit ağırlık, ay sonu rebalance;
komisyon 15 + kayma 10 bps + karekök piyasa-etkisi + ADV likidite sınırı (`%25`):

| Metrik | Değer |
|---|---|
| Toplam getiri | ~%341,8 (≈ 100k → ~442k TL) |
| CAGR | %141,82 |
| Sharpe | 2,46 |
| Sortino | 3,58 |
| Calmar | 4,80 |
| Yıllık volatilite | %39,26 |
| Maksimum düşüş | %-29,52 |
| Aylık isabet | %77,3 |
| Yıllık turnover | 12,19x |
| Toplam işlem maliyeti | 9.808 TL |
| BIST100 getiri | %44,20 |
| **Alfa** | **%297,60** |

> ⚠️ Bu rakamlar **iyimser bir üst sınırdır**: ücretsiz veride survivorship bias
> (yalnız bugün listede olan hisselerle çalışılır) hâlâ baskın faktördür ve geçmiş
> as-reported temel veri yoktur. Sayılar uydurulmaz; gerçek/yanlılıksız ölçüm için
> bot **ileriye dönük canlı alfa**yı izler. Parametreler `Run workflow` ile
> değiştirilebildiği için sonuç değişir.

### Point-in-Time (PIT) Anlık Görüntü Arşivi (`data/pit/`)

Geçmiş **as-reported** temel veri ve delist-dahil bileşen listesi ücretsiz
kaynaklarda yoktur; bu yüzden geçmişe dönük PIT **üretilemez**. Bunun yerine bot,
her çalışmada **o gün gözlenen** evreni + temel/teknik alanları tarihli JSON olarak
(`data/pit/YYYY-MM-DD.json`) biriktirir ve git'e commit'ler. Zamanla, ileri-bakış
içeremeyen **gerçek bir as-observed PIT arşivi** oluşur; ileride backtest'ler bu
arşivden gerçek temel veriyle beslenebilir hale gelir.

- Yazan: `Save-PitSnapshot` (günde tek dosya, idempotent), günlük raporda best-effort.
- Okuyan: `Get-PitSnapshot -Date <gün> [-OnOrBefore]` (tam eşleşme ya da en yakın
  önceki gün).

> Dürüst kısıt: bu motor ve PIT arşivi mimariyi **kurumsal seviyeye** taşır, ancak
> *gerçek tick verisi, broker emir-defteri dolumu ve geçmiş as-reported PIT temel
> veri* hâlâ ücretsiz değildir. Survivorship arşiv biriktikçe ileriye dönük olarak
> azalır; rakamlar uydurulmaz, kısıtlar açıkça belirtilir.

## Son Eklenen İyileştirmeler

### Skeptik İnceleme Sonrası Düzeltmeler
Detaylı eleştirel inceleme (kod tabanı kanıtıyla) sonrası uygulananlar:

- **Dürüstlük (yukarıda):** README'ye canlı izlenen gerçek isabet/edge ve backtest'in
  iyimserliği nicel olarak eklendi; "kanıtlanmış alfa yok" açıkça yazıldı.
- **Veri kalitesi uyarısı (sessiz yanlış veriyi önler):** USD/TRY, BIST100, TR10Y, DXY/VIX
  gibi kritik makro/benchmark girdileri eksik geldiğinde rapora **görünür kırmızı uyarı**
  bandı eklenir (`Get-DataQualitySummary`); temel verisi eksik hisse oranı da gösterilir.
  Artık eksik veri sessizce yanlış skor/alfa üretmez — kullanıcı uyarılır.
- **Portföyler-arası yoğunlaşma (gözlem):** aynı hissenin **tüm** model portföyler
  üzerindeki toplam ağırlığı hesaplanıp rapora **yeni bir tablo** olarak eklendi
  (`Get-CrossPortfolioConcentration`); defterin %12'sini aşan isimler ⚠️ ile işaretlenir.
  Tek portföy içi sektör tavanının görmediği gizli yoğunlaşma artık izlenir.
- **Eksik temel veri cezalı:** eksik F/K, PD/DD, FD/FAVÖK, ROE artık "nötr 45" yerine
  **hafif cezalı (32)** puanlanır; düşük-açıklamalı/illikit hisseleri kayırma önyargısı azaltıldı.
- **İşlem maliyeti gerçekçi:** model portföy maliyeti varsayılanı **20 → 50 bps** (BIST'te
  BSMV + komisyon + kayma); raporlanan getiriler daha gerçekçi (biraz daha düşük) olur.
- **İki tablo tutarlılığı + BIST100 çapraz-kontrol:** "Getiri Karşılaştırması" özet tablosu
  ile model-portföy detay tablosu artık **aynı otorite kaynağı** (canlı TradingView
  mark-to-market) kullanır — model portföy ve BIST100 getirileri iki tabloda **birebir
  aynıdır**. Grafik çizgileri günlük geçmiş için Yahoo kapanışından yeniden kurulur (tek
  günlük seri için tek kaynak), bu yüzden grafik çizgisi tablodan hafif sapabilir; bu açıkça not edilir.
  Ayrıca BIST100'ün **canlı (TradingView)** ve **Yahoo XU100.IS** getirileri >1,5 puan
  ayrışırsa rapora **görünür uyarı** eklenir (alfa sessizce yanlış gösterilmez). Eskiden
  özet tablo Yahoo'dan, detay tablo canlıdan beslendiği için aynı portföy iki farklı getiri
  gösterebiliyordu; bu giderildi.
- **Repo şişmesi durduruldu + PIT arşivi korundu:** tarihli PIT anlık görüntüleri
  (`data/pit/`, `data/point_in_time_snapshots/`) artık `main`'e commit **edilmez**
  (.gitignore + persist'ten çıkarıldı, untrack edildi) — `main` ve normal clone'lar
  hafif kalır. Çalışma anında yalnız `latest_point_in_time_snapshot.json` okunur.
  **Ancak arşiv kaybolmaz:** her koşu, o günkü snapshot'ları **ayrı bir `pit-archive`
  orphan branch'ine** push eder (`bist-cloud-report.yml` → "Archive PIT snapshots"
  adımı, best-effort). Bu branch normal clone/checkout tarafından çekilmez, dolayısıyla
  `main`'i şişirmez; ama zamanla **as-observed** veri biriktirerek ileride
  survivorship/look-ahead'siz backtest'e zemin hazırlar.
- **Dosya temizliği (yinelenen/ölü kod kaldırıldı):** `patches/` klasörü silindi —
  içindeki fonksiyonlar (`Update-InstantEntrySignalPortfolio` vb.) zaten `GunlukRapor.ps1`'de
  canlı tanımlı, hiçbir workflow onu çağırmıyor ve kopya **bayatlamıştı** (yeni risk-çıkış
  mantığı yoktu) → iki ayrışan kaynak riski giderildi. `CLOUD-RUN.md` silindi (README'nin
  "Gerekli GitHub Secrets" bölümünün eski/eksik bir kopyasıydı; "cache" iddiası da güncel değildi).
- **Prompt-injection sertleştirme:** KAP başlığı/kategori/şirket metni LLM prompt'una
  girmeden önce temizlenir (`_safe_field`: tek satır, süslü parantez nötrlenir) — hem
  `.format` kırılmasını hem manipülasyonu engeller.
- **Dürüst etiketleme:** "earnings surprise" raporda artık **trend-temelli vekil** olarak
  açıkça belirtilir (gerçek analist konsensüsü ücretsiz veride yok).

### Strateji/Gerçekçilik Değişiklikleri (ikinci tur)

- **Tam lot (whole-lot) — UYGULANDI:** BIST tam adet işlediğinden, ay sonu yeniden
  dengelemede her pozisyonun adedi **tam sayıya yuvarlanır** (`Optimize-ModelPortfolioSetRisk`);
  değer = adet × fiyat, küçük artık nakit gerçekçi şekilde düşülür, portföy değeri/ağırlık/getiri
  yeniden hesaplanır. Ayar `Report.ModelPortfolioMaxBookPct` (>0 ise pas aktif). Kesirli adet
  kaynaklı ~%0,1-0,3 sahte getiri kaldırıldı.
- **Portföyler-arası sabit TAVAN — bilinçli olarak UYGULANMADI (matematiksel + ürün gerekçesi):**
  Ağırlık-yeniden-dağıtımıyla, *seçimi koruyan* bir tavan bu botta **yakınsamıyor**: 6 portföy
  büyük ölçüde aynı isimleri tuttuğundan, aşan ismin ağırlığını paylaşılan diğer isimlere dağıtmak
  yoğunlaşmayı tekrar üretiyor (salınım) ya da ağır nakit bırakıyor — ikisi de sağlıklı bir fon
  sonucu değil. Sağlıklı tek hard-cap **seçimi değiştirmektir** (her stratejiyi aşırı-kullanılan
  ismi atlamaya zorlamak), ki bu her stratejinin saflığını bozar ve track record'u baştan değiştirir.
  Ayrıca bu risk yalnız 6 portföyü **tek defter** olarak işletirsen vardır (çoğu kullanıcı tek
  strateji seçer). Bu yüzden **hard-cap yerine görünür İZLEME** (rapordaki "Portföyler-Arası
  Yoğunlaşma" tablosu, %12 üstü ⚠️) eklendi. Seçim-temelli hard-cap istenirse ayrı, bilinçli bir
  strateji kararı olarak uygulanabilir.

**Veri/araştırma kısıtı nedeniyle uygulanamayanlar (dürüstçe):**
- *Free-float filtresi:* ücretsiz kaynaklarda fiili dolaşım verisi yok → likidite (10g hacim/
  relatif hacim) eşikleri kullanılır.
- *Tavan-taban (devre kesici) / T+2 takas:* gün-içi/mikroyapı verisi gerektirir; teorik model
  bunları modellemez — kısıt açıkça belgelenir.
- *Skorlamanın OOS yeniden kalibrasyonu:* ayrı bir araştırma işidir; mevcut eşikler "elle
  seçilmiş" olarak dürüstçe işaretlendi.

### Ay Sonu Portföy Yorumu (Claude) — `MonthlyCommentary`
Model portföyler **ay sonunda yeniden dengelendiğinde**, o ayki değişiklikler (çıkan/giren
hisseler, seçim gerekçeleri, ağırlıklar, getiri/alfa) + her pozisyonun **gerçek temel/teknik
verisi** bir **fon yöneticisi gözüyle** Claude'a yorumlatılır ve rapora **"🤖 Ay Sonu Portföy
Yorumu"** bölümü olarak eklenir.

**Ne zaman çalışır?** **Yalnızca rebalance dönemi değiştiğinde** (yani ayda ~1 kez). Her gün
çalışan `Update-ModelPortfolioCommentary` sadece "kayıtlı yorumun dönemi == güncel dönem mi?"
diye bakar; aynı dönemse **API'ye hiç gitmez** (no-op, sıfır maliyet). Yeni dönemde 1 kez üretir,
`data/model_portfolios.json → MonthlyCommentary` (Period/Model/GeneratedAt/Text) olarak saklar ve
sonraki ay sonuna kadar **her gün raporda gösterir**.

**Modele giden prompt.** İki parça:
- **Sistem (rol):** "Kıdemli bir BIST portföy yöneticisisin, yatırımcılarına aylık not yazıyorsun."
  Kurallar: her portföy için 3-5 cümle akıcı paragraf; önce **net tez/karar**, sonra 1-2 somut
  pozisyonu **gerçek rakamlarla** (F/K, ROE, FD/FAVÖK, momentum) gerekçelendir, sonda **en önemli
  risk**; botun iç skorlarını ham sayı olarak ezberleme, **yatırımcı diline çevir**; sektör/isim
  yoğunlaşması, aşırı tek-hisse ağırlığı, değerleme, momentum-strateji tutarsızlığı, negatif alfa
  gibi riskleri vurgula; sonda **"## Genel Değerlendirme"** (portföyler arası ortak isim/sektör
  yoğunlaşması gibi kurumsal gözlemler dahil); profesyonel **Türkçe**, uydurma rakam yok.
- **Veri (kullanıcı mesajı):** `Build-ModelPortfolioCommentaryPrompt` her portföy için dönem
  işlemlerini (AL/SAT/EŞİTLEME + seçim gerekçeleri) ve **güncel pozisyonların gerçek verisini**
  (sektör, piyasa değeri, F/K, PD/DD, FD/FAVÖK, ROE, temettü, 1A/3A getiri, RSI) taranan hisse
  haritasından (`StockMap`) zenginleştirerek verir — böylece model içsel skorları tekrarlamak
  yerine gerçek temel analiz yapar.

**Best-effort:** `ANTHROPIC_API_KEY` yoksa veya çağrı/içerik reddi olursa yorum atlanır, **rapor
bozulmaz**. Yanıt **HttpClient ile açık UTF-8** çözülür (PowerShell 5.1'in `Invoke-RestMethod`'u
UTF-8'i bozduğu için); Fable/Mythos seçilirse reddi **Opus 4.8'e düşüren sunucu-tarafı fallback**
eklenir.

**Ayar:** `config/report_settings.cloud.json → Report.ModelPortfolioCommentary`: `Enabled`
(vars. true), `Model` (vars. `claude-opus-4-8`), `MaxOutputTokens` (vars. 3000). En üst model
`claude-fable-5`'tir ama Anthropic hesabında ayrı erişim ister; erişimin yoksa API **404** döner ve
yorum atlanır (rapor yine üretilir). Erişim açılınca `Model`'i tek satırla `claude-fable-5` yap.

**Maliyet (ölçülen):** girdi ~2,5-3K + çıktı ~1K token. `claude-opus-4-8` ile **çağrı başına ≈
$0,04**; ayda 1 çağrı → **~$0,5/yıl**. `claude-fable-5` birim fiyatın 2 katı (~$0,08/çağrı, ~$1/yıl).
Aynı dönemde tekrar çalışmadığı için günlük ek maliyet yoktur.

### Raporda Türkçeleştirme — emir/işlem bölümleri
Raporun ara-işlem bölümleri tamamen Türkçeleştirildi: **"Emir Niyetleri (Kağıt)"** ve **"Kağıt
Broker Pozisyon Defteri"** başlıkları, ve içlerindeki değerler — yön `Buy/Sell` → **AL/SAT**, kaynak
`ModelPortfolio/InstantEntry` → **Model Portföy / Anlık Fırsat**. Saklanan veri formatı (ileride
aracı kurum entegrasyonu için) `Buy/Sell` olarak korunur; yalnızca **gösterim** Türkçedir.

### Sektör Yoğunlaşma Tavanı (model portföyler)
Hisse başına `MaxWeightPct`'in yanına **sektör bazında ağırlık tavanı** eklendi
(`SectorMaxWeightPct`, vars. **%35**). Hiçbir sektörün toplam ağırlığı bu eşiği geçemez; aşan sektör
oransal küçültülür, serbest kalan ağırlık tavan-altı isimlere dağıtılır (çok-geçişli, toplam %100
korunur). Hem eşit ağırlıklı hem ters-oynaklık (RiskDengeli) portföylerine uygulanır
(`Get-SectorCappedWeights`). Mevcut "sektör başına en fazla 2 isim" sayı kuralıyla birlikte gerçek
çeşitlendirme sağlar.

### Anlık Fırsat Portföyüne Risk Çıkışları (stop / kâr-al / iz-süren stop)
Model portföyler aylık kalmaya devam eder; **anlık fırsat portföyü** ise artık her gün kapanışta
`RiskRules` eşiklerine göre pozisyon kapatır (`Get-InstantEntryExitDecision`): **stop-loss** (getiri ≤
StopLossPct), **kâr-al** (≥ TakeProfitPct), **iz-süren stop** (tepe kazanç TrailingStopPct'i geçtiyse ve
tepeden o kadar geri verildiyse). Teoriktir; gerçek emir gönderilmez (`SAT` kaydı oluşur). Her pozisyonun
**tepe fiyatı** (high-water mark) izlenir. Kapatılan pozisyonun K/Z'si `RealizedGainTL`'de kümülatif
birikir ve raporda **"Gerçekleşen K/Z"** satırı olarak gösterilir (survivorship önlenir).

### KAP Enrich — Otomatik Sağlayıcı Fallback Zinciri
Birincil LLM motoru (varsayılan GitHub Models / gpt-4.1) **günlük kotaya/hız limitine (429)** takılırsa,
enrich otomatik olarak anahtarı **mevcut** bir sonraki ücretsiz sağlayıcıya geçer (varsayılan sıra:
github → groq → cerebras → openrouter → opencode → nvidia). Yalnızca 429'da geçilir; içerik filtresi/parse
hataları zinciri tetiklemez (`RateLimitError`). `--fallback auto|none|liste` argümanı + `kap-enrich.yml`
`fallback` girdisi ile ayarlanır. Enrich öncesi **ağsız birim test kapısı** (`test_enrich_kap.py`, 21 test)
çalışır.

### Otomasyon Sağlamlaştırması
- **Başarısızlık uyarı maili:** günlük rapor koşusu rapor e-postası gönderilmeden çökerse (`if: failure()`)
  koşu log linki + branch/commit içeren ayrı bir uyarı maili gider — sessiz başarısızlık önlenir.
- **State yalnız başarılı koşuda yazılır** (`if: success()`): yarım/başarısız bir koşu bot hafızasını
  (portföy/sinyal state'ini) ileri alamaz.
- `__pycache__/` ve `*.pyc` artık `.gitignore`'da.

### Test Kapsamı
- `Test-BistScanner.Core.ps1`: sektör tavanı ve anlık-fırsat risk çıkışı için deterministik birim testleri.
- `test_enrich_kap.py`: enrich saf yardımcıları + fallback zinciri için 21 ağsız test.

## Gerekli GitHub Secrets

`Settings > Secrets and variables > Actions > New repository secret`:

- `BIST_EMAIL_FROM`, `BIST_EMAIL_TO`, `BIST_SMTP_USERNAME`, `BIST_SMTP_PASSWORD`
  (Gmail uygulama şifresi, boşluksuz).

Opsiyonel secret: `BIST_SMTP_SERVER` (vars. smtp.gmail.com), `BIST_SMTP_PORT` (587),
`BIST_SMTP_USE_SSL` (true), `BIST_TELEGRAM_BOT_TOKEN`, `BIST_TELEGRAM_CHAT_ID`,
`BIST_EVDS_API_KEY` (TÜFE/faiz/dinamik enflasyon için), `ANTHROPIC_API_KEY` (ay sonu portföy
yorumu için; aynı anahtar KAP enrich'in `llm` motorunda da kullanılır — yoksa yorum atlanır,
rapor bozulmaz).

Opsiyonel **Variables** (`Actions > Variables`):
- `BIST_MODEL_COST_BPS` — model portföy işlem maliyeti (bps; vars. 20).
- `BIST_EVDS_TR10Y_SERIES` — TR10Y için EVDS seri kodu (girilirse EVDS'ten çekilir).

## Otomatik Zamanlama ve Elle Çalıştırma

**Günlük işleyişte hiçbir tekrar eden elle adım yoktur — her şey zamanlanmıştır.**
İki zamanlama mekanizması var:

- **Harici cron-job.org** (kesin saat gerektirenler; GitHub cron'u gecikebildiği için):
  **günlük rapor** (`bist-cloud-report`, ~18:15) + **KAP collector** + **KAP enrich**.
  Bu üçünde GitHub cron'u yoktur; cron-job.org GitHub API ile tetikler.
- **GitHub `schedule` cron'u** (GitHub içi, tam otomatik):
  - **Auto-Calibrate** (öğrenme): her ayın 1'i (18:00 UTC). Veri-kapılı; yeterli bağımsız
    dönem birikene kadar prior'u korur, hazır olunca öğrenir ve **Öğrenen Algoritma
    portföyünü otomatik oluşturur** — kendi içinde süren döngü.
  - **Backtest (Event-Driven)**: aylık · **Strategy Separation Simulation**: aylık ·
    **Earnings Event Study**: haftalık · **EVDS Discovery**: aylık · **borsapy KAP probe**: haftalık.

**Tek seferlik (kurulum, tekrar etmez — zaten yapıldı):** cron-job.org işlerinin
tanımlanması, GitHub Secrets/PAT girişi ve bu sürümün `main`'e alınması. Bunlar günlük
işleyişin parçası değildir; bir kez yapılır. Yani **bot artık kendi başına çalışır**:
tarar, skorlar, rebalance eder, KAP yorumlar, ay sonu Claude yorumu üretir, çeyreklik
öğrenir ve öğrendiğinde yeni portföyünü kendi kurar — hiçbiri elle müdahale istemez.

Elle de tetiklenebilir (opsiyonel override) — `Actions` sekmesi → ilgili workflow → `Run workflow`:
- **BIST Cloud Report** — günlük raporu hemen üretir ve e-posta gönderir.
- **Model Portfolio Backtest (Event-Driven)** — günlük olay eksenli gerçek
  event-driven backtest (gerçekçi dolum + kurumsal metrikler; önce motorun birim testi
  çalışır). Eski "Realistic" ve momentum 12-1 backtest'leri ile parametre taraması bu
  motora taşındığı için kaldırıldı.
- **Strategy Separation Simulation** — 30 Haziran (veya seçtiğin tarih) rebalance'ını
  canlı veriyle simüle edip portföylerin ayrıştığını log'da gösterir (state'e dokunmaz).
- **Earnings Event Study** — bilanço olay çalışması.

Çalışma bitince e-posta gelir; `Artifacts` altından HTML/CSV rapor + state
dosyaları indirilebilir.
