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
  performansı, PEAD ve kalibrasyon dosyaları her çalışmada `data/` altına commit
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
  RFS100 (ham teknik faktör). Aşağıya bakın.

## Model Portföyler — aylık karar mantığı

- Her **ayın son BIST işlem gününde** 18:15 çalışmasında yeniden dengelenir
  (sıralama + AL/SAT/EŞİTLEME); diğer günler yalnız değerlenir. Tatil/hafta sonu
  `Get-BistFullClosureDates` ile dışlanır (2026-2030 dini bayramlar dahil).
- Eşit ağırlık (5 hisse × %20). Uygunluk: ROE/değer/FAVÖK/makro/teknik + **veri
  kalitesi kapısı** + **aşırı volatilite kapısı** (günlük vol > 8 elenir) + sektör
  sınırı.
- **İşlem maliyeti + kayma** modellenir (varsayılan 20 bps; `BIST_MODEL_COST_BPS`
  veya config `ModelPortfolioCostBps`); getiriler nettir.
- **BIST100 alfa:** her portföyün kuruluştan beri getirisi BIST100 ile kıyaslanır;
  **Alfa = getiri − BIST100**. Hangi stratejinin endeksi yendiğini gösterir.
- **Maksimum düşüş (drawdown)** her değerlemede izlenir.
- **Lider strateji:** rapor, alfaya göre en iyi stratejiyi öne çıkarır.

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

- `.github/workflows/bist-cloud-report.yml` — günlük rapor (cron + manuel).
- `GunlukRapor.ps1` — rapor motoru (orkestrasyon, HTML/CSV, e-posta/Telegram).
- `BistScanner.Core.psm1` — tarama, skorlama, AFS, model portföy, makro, EVDS,
  PEAD/kalibrasyon, Yahoo/TradingView yardımcıları.
- `Test-BistScanner.Core.ps1` — workflow başında çalışan smoke + birim testler.
- `config/report_settings.cloud.json` / `.example.json` — ayarlar.
- `data/` — kalıcı bot state'i (git'te tutulur): `model_portfolios.json`,
  `instant_entry_portfolio.json`, `signal_performance.json`, `earnings_reactions.json`,
  `signal_calibration.json`.
- `data/pit/` — point-in-time anlık görüntü arşivi (tarihli `YYYY-MM-DD.json`;
  her gün gözlenen evren + temel veri, ileri-bakış olmadan biriker).

### Analiz / araştırma araçları (elle tetiklenir; günlük raporu etkilemez)

- `Analyze-EarningsEventStudy.ps1` + `earnings-event-study.yml` — bilanço tarihi olay
  çalışması (run-up / tepki / drift korelasyonları).
- `Backtest-ModelPortfolio.ps1` + `backtest.yml` — momentum 12-1 aylık backtest.
- `Backtest-Realistic.ps1` + `backtest-realistic.yml` — RFS teknik (point-in-time) +
  o anki likidite kapısı + karekök piyasa-etkisi maliyetiyle gerçekçi backtest.
- `Find-EvdsBondSeries.ps1` + `evds-discovery.yml` — EVDS seri kodu keşfi (tanılama).
- `Backtest-EventDriven.ps1` + `backtest-event-driven.yml` — **gerçek event-driven
  backtest** (aşağıya bakın).
- `BacktestEngine.psm1` — event-driven backtest çekirdeği (`Invoke-EventDrivenBacktest`).
- `Test-BacktestEngine.ps1` — motorun **ağsız, deterministik** birim testleri (CI kapısı).

> Backtest uyarısı: ücretsiz veride **survivorship** (bugün listede olmayan/delist
> hisseler yok) ve geçmiş bilanço anlık görüntüsü eksikliği vardır; backtest
> rakamları **iyimser üst sınırdır**. Yanlılıksız ölçüm için bot **ileriye dönük
> canlı alfa**yı izler.

## Kurumsal-Seviye Altyapı

### Gerçek Event-Driven Backtest Motoru (`BacktestEngine.psm1`)

Eski "aylık döngü" yaklaşımının aksine, motor **günlük olay ekseninde** ilerler:

- Her gün **mark-to-market** (nakit + pozisyonlar); ay sonu rebalance günlerinde
  sinyal **yalnız o güne kadarki** fiyat/hacimle hesaplanır (point-in-time, ileri-
  bakış yok).
- **Gerçekçi dolum:** komisyon + kayma + **karekök piyasa-etkisi** (işlem TL /
  günlük TL hacim) + **ADV katılım sınırı** (`MaxAdvMultiple`: tek isimde günlük
  hacmin en fazla bu katı kadar pozisyon → likidite gerçekçiliği).
- **Tam defter (ledger):** nakit/pozisyon akışı; alım/satım korunumu test edilmiştir.
- **Kurumsal metrikler:** CAGR, yıllık vol, **Sharpe, Sortino, Calmar**, maks düşüş,
  yıllık **turnover**, BIST100'e karşı **alpha**, aylık **isabet (hit-rate)**, eşitlik
  eğrisi (equity curve), aylık getiriler.
- **Çekirdek ağsızdır ve deterministik test edilir:** `Test-BacktestEngine.ps1` elle
  hesaplanmış "golden" değerlerle defter korunumu, maliyet muhasebesi, ADV sınırı,
  alım/satım geçişi ve metrikleri doğrular; backtest workflow'unda **kapı** görevi görür.

Çalıştırma: `Actions → Model Portfolio Backtest (Event-Driven) → Run workflow`.
Komisyon/kayma/likidite parametreleri girişten ayarlanır.

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
- **Earnings Event Study** — bilanço olay çalışması.

Çalışma bitince e-posta gelir; `Artifacts` altından HTML/CSV rapor + state
dosyaları indirilebilir.
