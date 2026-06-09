# Bulutta Calistirma

Bu kurulum, botu GitHub Actions uzerinde her is gunu saat 18:15 Europe/Istanbul zamanina denk gelecek sekilde calistirir. Bilgisayar kapali olsa bile `GunlukRapor.ps1` calisir, HTML/CSV raporu uretir, model portfoy durumunu sonraki kosu icin cache'e tasir ve e-posta gonderir.

## Gerekli GitHub Secrets

Repository ekraninda `Settings -> Secrets and variables -> Actions -> New repository secret` alanindan sunlari ekleyin:

- `BIST_EMAIL_FROM`: gonderen e-posta adresi
- `BIST_EMAIL_TO`: alici e-posta adresi. Birden fazla adres icin virgulle ayirin
- `BIST_SMTP_USERNAME`: SMTP kullanici adi. Gmail icin genelde e-posta adresi
- `BIST_SMTP_PASSWORD`: SMTP sifresi. Gmail icin normal sifre degil, uygulama sifresi kullanin
