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
- **KAP Son Bildirimleri (deneysel):** best-effort; erişilemezse boş kalır.
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

## Model Portföyler — aylık karar mantığı

- Her **ayın son BIST işlem gününde** 18:15 çalışmasında yeniden dengelenir
  (sıralama + AL/SAT/EŞİTLEME); diğer günler yalnız değerlenir. Tatil/hafta sonu
  `Get-BistFullClosureDates` ile dışlanır (2026-2030 dini bayramlar dahil).
- Dengeli/Değer/Momentum/Kalite/RFS100 portföyleri eşit ağırlıkla çalışır
  (5 hisse × %20). Bu portföylerin ağırlık davranışı korunur. Uygunluk:
  ROE/değer/FAVÖK/makro/teknik + **veri kalitesi kapısı** + **aşırı volatilite
  kapısı** (günlük vol > 8 elenir) + sektör sınırı.
- **RiskDengeli** portföy ayrı izlenir: seçim yine Dengeli skor ve aynı uygunluk
  filtresiyle yapılır; ağırlıklar günlük volatilitenin tersine göre dağıtılır ve
  tek hisse riskini sınırlamak için min/max ağırlık sınırları uygulanır. Normal
  model portföylerin eşit ağırlığı bu portföy yüzünden değişmez.
- **İşlem maliyeti + kayma** modellenir (varsayılan 20 bps; `BIST_MODEL_COST_BPS`
  veya config `ModelPortfolioCostBps`); getiriler nettir.
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

## Dosyalar

- `.github/workflows/bist-cloud-report.yml` — günlük rapor (harici zamanlayıcı
  `workflow_dispatch` ile 18:15'te tetikler + elle çalıştırma).
- `GunlukRapor.ps1` — rapor motoru (orkestrasyon, HTML/CSV, e-posta/Telegram).
- `BistScanner.Core.psm1` — tarama, skorlama, AFS, model portföy, makro, EVDS,
  PEAD/kalibrasyon, Yahoo/TradingView yardımcıları.
- `Test-BistScanner.Core.ps1` — workflow başında çalışan smoke + birim testler.
- `Validate-StrategySweep.ps1` — manuel parametre taraması ve validation raporu.
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
- **Earnings Event Study** — bilanço olay çalışması.

Çalışma bitince e-posta gelir; `Artifacts` altından HTML/CSV rapor + state
dosyaları indirilebilir.
