# BIST Rapor Botu

GitHub Actions uzerinde calisan BIST bulut raporu.

Bu surum masaustundeki gunluk rapor motoruyla ayni mantigi calistirir: workflow dogrudan repodaki `GunlukRapor.ps1` ve `BistScanner.Core.psm1` dosyalarini kullanir (tek kaynak), rapor uretilir ve mail/artifact olarak verilir. Calistirilan kod repoda gorunen kodla aynidir; dosyalari duzenlemek davranisi dogrudan degistirir.

## Bulutta Gelen Bolumler

- Makro Gorunum: BIST trendi, banka relatif gucu, USD/TRY, Turkiye 5Y CDS, TR10Y, DXY, VIX ve izleme notlari.
- Anlik Giris Firsati: temel filtre + haftalik MACD histogram ivmesi + 52 hafta konumu + BIST rejimi.
- Top Radar: skor, gorus, teyit etiketi, eksik teyitler, temel/teknik/makro kolonlari.
- Sektor Rotasyonu: gunluk, haftalik, 1 ay, 3 ay ve 1 yil sektor/BIST100 farklari.
- Model Portfoyler: dengeli, deger, momentum ve kalite portfoyleri; state cache ile ay sonu yeniden dengeleme mantigi korunur.
- Skor Isabet Takibi (oz-degerlendirme): her kosu o gunku Top secimleri ve fiyatlari saklar; sonraki kosuda secimlerin gerceklesen getirisini tum evren ortalamasiyla kiyaslayarak yuvarlanan isabet orani (hit-rate) ve ortalama getiri avantaji (edge) uretir. Bu, skorlama mantiginin zaman icinde gercekten ayristirici olup olmadigini olcen geri-besleme sinyalidir.

## Dosyalar

- `.github/workflows/bist-cloud-report.yml`: Bulut calisma plani.
- `GunlukRapor.ps1`: Rapor motoru (orkestrasyon, HTML/CSV uretimi, e-posta/Telegram gonderimi).
- `BistScanner.Core.psm1`: Tarama, skorlama, model portfoy ve makro/sektor mantigi.
- `Test-BistScanner.Core.ps1`: Workflow basinda calisan smoke test.
- `config/report_settings.cloud.json`: Bulut ayarlari.
- `config/report_settings.example.json`: Lokal ayar ornegi.
- `reports/`: Workflow calistiktan sonra artifact olarak HTML/CSV rapor uretir.

## Gerekli GitHub Secrets

Repo sayfasinda `Settings > Secrets and variables > Actions > New repository secret` alanina su secretlari tek tek gir:

- `BIST_EMAIL_FROM`: Gonderen Gmail adresi.
- `BIST_EMAIL_TO`: Raporun gidecegi email adresi.
- `BIST_SMTP_USERNAME`: Genelde gonderen Gmail adresi.
- `BIST_SMTP_PASSWORD`: Gmail uygulama sifresi. Bosluksuz yaz.

Opsiyonel:

- `BIST_SMTP_SERVER`: Varsayilan `smtp.gmail.com`.
- `BIST_SMTP_PORT`: Varsayilan `587`.
- `BIST_SMTP_USE_SSL`: Varsayilan `true`.
- `BIST_TELEGRAM_BOT_TOKEN`
- `BIST_TELEGRAM_CHAT_ID`

## Elle Calistirma

1. GitHub'da repoya gir: `neccoju/bist-rapor-botu`.
2. `Actions` sekmesine gir.
3. `BIST Cloud Report` workflow'unu sec.
4. `Run workflow` dugmesine bas.
5. Calisma bitince mail gelmeli. Ayrica `Artifacts` altindan HTML/CSV raporu indirebilirsin.

## Not

Bu rapor sayisal taramadir, yatirim tavsiyesi degildir. Ucretsiz kaynaklar gecikmeli, eksik veya zaman zaman erisilemez olabilir; islem karari oncesi KAP, Borsa Istanbul, TCMB ve lisansli veri kaynaklariyla kontrol gerekir.
