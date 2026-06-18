# BIST Rapor Botu

GitHub Actions üzerinde her BIST işlem günü (Pzt-Cum) 18:15 Europe/Istanbul'da
otomatik çalışan, BIST hisselerini tarayıp skorlayan, model portföyleri yöneten
ve sonucu e-posta + artifact olarak veren bulut botu. Bilgisayar kapalıyken de
çalışır.

> Sayısal taramadır, **yatırım tavsiyesi değildir**. Ücretsiz kaynaklar gecikmeli/
> eksik olabilir; işlem öncesi KAP, Borsa İstanbul, TCMB ve lisanslı kaynaklarla
> doğrulayın.

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

## Raporda Gelen Bölümler

- **Makro Görünüm:** BIST/BIST30/XBANK trendi, USD/TRY, Türkiye 5Y CDS, TR10Y faiz,
  DXY, VIX, TCMB fonlama faizi ve TÜFE (EVDS). Genel "Makro Zemin" durumu üretir
  (bağlam/teyit amaçlı; hisse skorunu doğrudan değiştirmez).
- **Top Radar:** strateji skoru, RFS100, AFS, görüş, teyit etiketi, temel/teknik/
  makro kolonları + veri-kalite özeti.
- **Akademik Çok-Faktör Skoru (AFS):** momentum 12-1 (Jegadeesh-Titman), kalite
  (Novy-Marx/RMW), değer, düşük volatilite (Frazzini-Pedersen), boyut faktörlerinin
  kesitsel z-skor karışımı; yıllık vol ve getiri/risk metrikleri.
- **Anlık Giriş Fırsatı + Anlık Fırsat Portföyü:** temel filtre + haftalık MACD
  ivmesi + 52 hafta konumu + BIST rejimi; çok güçlü sinyalde teorik alım kaydı.
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
skoruyla), **RFS100** (ham teknik faktör skoruyla) ve **Risk Dengeli** (Dengeli
seçimi + volatilite-tersi ağırlık). Hepsi 100.000 TL ile başlar ve teoriktir
(gerçek emir yok).

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
5. **Eşit ağırlık:** Dengeli/Değer/Momentum/Kalite/RFS100 portföylerinde 5 hisse ×
   %20. (Risk Dengeli farklı; aşağıda.)

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
  kompakt evren kesiti `data/latest_point_in_time_snapshot.json` ve
  `data/point_in_time_snapshots/YYYYMMDD_HHMM.json` altında saklanır. Amaç,
  gelecekte lookahead/survivorship riskini azaltan canlı veri arşivi oluşturmaktır.
  **Otomatiktir:** günlük rapor her BIST işlem günü (Pzt-Cum) 18:15 Europe/Istanbul'da
  harici bir zamanlayıcı (örn. cron-job.org) tarafından `workflow_dispatch` ile
  tetiklenirken (ya da elle `Run workflow`'da) snapshot üretilip git'e commit edilir;
  ek bir kurulum gerekmez. Böylece arşiv gün gün ileriye dönük olarak kendiliğinden
  birikir.
- **Validation sweep:** `Validate-StrategySweep.ps1` ve `strategy-validation.yml`
  TopN, maliyet ve likidite eşiği kombinasyonlarını manuel olarak dener; günlük
  rapor state'ini değiştirmez, `reports/strategy_validation.md` ve `.json`
  artifact üretir.

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

**Zamanlama (cron-job.org):** Toplayıcı gün içinde **sık** tetiklenir; örn.
09:30–18:00 arası **her ~30 dk** bir `kap-collector.yml` `workflow_dispatch`
çağrısı (~17 parti → tüm evren gün içinde **~2 kez** taranır). Ana rapor
(`bist-cloud-report.yml`) **18:15**'te birikmiş `kap_disclosures.json`'u okur (son
7 gün filtresiyle). Partileri 18:00'a kadar bitir; rapor 18:15'te. GitHub'ın kendi
cron'u geciktiği için harici tetikleyici kullanılır.

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

## Dosyalar

- `.github/workflows/bist-cloud-report.yml` — günlük rapor (harici zamanlayıcı
  `workflow_dispatch` ile 18:15'te tetikler + elle çalıştırma).
- `GunlukRapor.ps1` — rapor motoru (orkestrasyon, HTML/CSV, e-posta/Telegram).
- `BistScanner.Core.psm1` — tarama, skorlama, AFS, model portföy, makro, EVDS,
  PEAD/kalibrasyon, Yahoo/TradingView yardımcıları.
- `Test-BistScanner.Core.ps1` — workflow başında çalışan smoke + birim testler
  (strateji ayrışma testi dahil).
- `Validate-StrategySweep.ps1` — manuel parametre taraması ve validation raporu.
- `Simulate-RebalanceSeparation.ps1` — strateji ayrışması canlı-veri doğrulaması.
- `collect_kap.py` + `.github/workflows/kap-collector.yml` — tüm BIST için KAP
  bildirim toplayıcısı (borsapy; `data/kap_disclosures.json` üretir/commit eder).
  Ayrı ubuntu job; ana botu etkilemez. (Bkz. "KAP Bildirim Toplayıcısı".)
- `BacktestEngine.psm1` / `Backtest-EventDriven.ps1` / `Test-BacktestEngine.ps1` —
  gerçek event-driven backtest motoru, koşucusu ve ağsız birim testi.
- `config/report_settings.cloud.json` / `.example.json` — ayarlar.
- `data/` — kalıcı bot state'i (git'te tutulur): `model_portfolios.json`,
  `instant_entry_portfolio.json`, `signal_performance.json`, `earnings_reactions.json`,
  `signal_calibration.json`, `order_intents.json`, `paper_broker.json`,
  `latest_point_in_time_snapshot.json` ve `point_in_time_snapshots/*.json`.

### Analiz / araştırma araçları (elle tetiklenir; günlük raporu etkilemez)

- `Analyze-EarningsEventStudy.ps1` + `earnings-event-study.yml` — bilanço tarihi olay
  çalışması (run-up / tepki / drift korelasyonları).
- `Backtest-ModelPortfolio.ps1` + `backtest.yml` — momentum 12-1 aylık backtest.
- `Backtest-Realistic.ps1` + `backtest-realistic.yml` — RFS teknik (point-in-time) +
  o anki likidite kapısı + karekök piyasa-etkisi maliyetiyle gerçekçi backtest.
- `Validate-StrategySweep.ps1` + `strategy-validation.yml` — TopN/maliyet/likidite
  kombinasyonlarını manuel deneyen validation sweep; günlük raporu/state'i etkilemez.
- `Backtest-EventDriven.ps1` + `backtest-event-driven.yml` — **gerçek event-driven
  backtest** (aşağıya bakın); CI'da önce motorun ağsız birim testi çalışır.
- `BacktestEngine.psm1` — event-driven backtest çekirdeği (`Invoke-EventDrivenBacktest`).
- `Test-BacktestEngine.ps1` — motorun **ağsız, deterministik** birim testleri (CI kapısı).
- `Find-EvdsBondSeries.ps1` + `evds-discovery.yml` — EVDS seri kodu keşfi (tanılama).
- `Simulate-RebalanceSeparation.ps1` + `simulate-separation.yml` — strateji ayrışması
  **gerçek-veri doğrulaması**: verilen tarihli (vars. 30 Haziran) ay-sonu rebalance'ı
  güncel canlı taramayla simüle eder, 6 portföyün holding'lerini ve çiftler arası
  örtüşmeyi log'a yazar. **Gerçek state'e dokunmaz** (bellekte çalışır, kaydetmez).

> Backtest uyarısı: ücretsiz veride **survivorship** (bugün listede olmayan/delist
> hisseler yok) ve geçmiş bilanço anlık görüntüsü eksikliği vardır; backtest
> rakamları **iyimser üst sınırdır**. Yanlılıksız ölçüm için bot **ileriye dönük
> canlı alfa**yı izler.

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

## Gerekli GitHub Secrets

`Settings > Secrets and variables > Actions > New repository secret`:

- `BIST_EMAIL_FROM`, `BIST_EMAIL_TO`, `BIST_SMTP_USERNAME`, `BIST_SMTP_PASSWORD`
  (Gmail uygulama şifresi, boşluksuz).

Opsiyonel secret: `BIST_SMTP_SERVER` (vars. smtp.gmail.com), `BIST_SMTP_PORT` (587),
`BIST_SMTP_USE_SSL` (true), `BIST_TELEGRAM_BOT_TOKEN`, `BIST_TELEGRAM_CHAT_ID`,
`BIST_EVDS_API_KEY` (TÜFE/faiz/dinamik enflasyon için).

Opsiyonel **Variables** (`Actions > Variables`):
- `BIST_MODEL_COST_BPS` — model portföy işlem maliyeti (bps; vars. 20).
- `BIST_EVDS_TR10Y_SERIES` — TR10Y için EVDS seri kodu (girilirse EVDS'ten çekilir).

## Elle Çalıştırma

`Actions` sekmesi → ilgili workflow → `Run workflow`:
- **BIST Cloud Report** — günlük raporu hemen üretir ve e-posta gönderir.
- **Model Portfolio Backtest (Realistic)** / **... Backtest** — geriye dönük analiz
  (sonuçlar çalışma log'una yazılır).
- **Model Portfolio Backtest (Event-Driven)** — günlük olay eksenli gerçek
  event-driven backtest (kurumsal metrikler; önce motorun birim testi çalışır).
- **Strategy Validation Sweep** — parametre kombinasyonlarını dener ve markdown/JSON
  validation artifact üretir.
- **Strategy Separation Simulation** — 30 Haziran (veya seçtiğin tarih) rebalance'ını
  canlı veriyle simüle edip portföylerin ayrıştığını log'da gösterir (state'e dokunmaz).
- **Earnings Event Study** — bilanço olay çalışması.

Çalışma bitince e-posta gelir; `Artifacts` altından HTML/CSV rapor + state
dosyaları indirilebilir.
