# BIST Rapor Botu

GitHub Actions uzerinde calisan BIST bulut raporu.

Bu repodaki bulut surumu telefon/bilgisayar acik olmadan rapor uretmek icindir. Workflow her hafta ici 18:15 Turkiye saati civari otomatik calisir; istersen GitHub uygulamasindan veya mobil tarayicidan elle de calistirabilirsin.

## Dosyalar

- `.github/workflows/bist-cloud-report.yml`: Bulut calisma plani.
- `CloudRapor.ps1.b64`: Workflow calisirken `CloudRapor.ps1` dosyasina acilir ve raporu uretir.
- `config/report_settings.cloud.json`: Bulut icin ornek ayar dosyasi.
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

Bu ilk bulut surumu, masaustundeki tam botun hafifletilmis calisan rapor motorudur. TradingView BIST taramasi yapar, skor hesaplar, HTML/CSV rapor uretir ve mail atar. Masaustundeki tum ileri ekranlari ve iOS Scriptable surumu ayri dosyalar olarak gelistirilmeye devam edilebilir.
