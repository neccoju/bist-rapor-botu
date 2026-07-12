#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""collect_fundamentals_secondary.py — İKİNCİ temel-veri kaynağı (İş Yatırım screener).

Amaç (P2: veri kalitesi / tek-satıcı riskini azalt): botun birincil temel verisi
(F/K, PD/DD, ROE) TradingView'den geliyor — TEK kaynak. Bu script BAĞIMSIZ ikinci
kaynaktan (İş Yatırım "Gelişmiş Hisse Arama" screener'ı, MKK toplayıcısıyla aynı
kanıtlanmış XHR) F/K, PD/DD, ROE'yi toplu çeker; bot bunu birincil veriyle ÇAPRAZ
DOĞRULAR ve belirgin sapmayı 'veri çelişkili' olarak bayraklar (skoru değiştirmez;
şeffaflık). İki kaynak aynı endpoint'e bağlı DEĞİL: TradingView vs İş Yatırım.

Kriter kimlikleri borsapy isyatirim_screener sağlayıcısından doğrulandı:
  28 = Cari F/K, 30 = Cari PD/DD, 422 = Cari ROE (%), 8 = Piyasa Değeri (mn TL).

Dürüstlük: İş Yatırım F/K/PD/DD "cari" (anlık) değerlerdir; sağlayıcı ve dönem
farkıyla TradingView'den bir miktar sapabilir — çapraz-kontrol eşiği bunu tolere
eder, yalnız BELİRGİN farkı bayraklar. Kaynak erişilemezse exit 0 + dosyayı EZME
(rapor son commit'li veriyi okur), nedenini logda söyler.

Çıktı şeması:
{ "generatedAt": iso, "source": "isyatirim-screener",
  "asOfNote": "...", "count": N,
  "items": { "SYM": {"pe": f|null, "pb": f|null, "roe": f|null, "mcapMnTL": f|null} } }
"""
import json, re, sys, time, urllib.request, urllib.error
from datetime import datetime, timezone
from http.cookiejar import CookieJar

OUT = "data/fundamentals_secondary.json"
TARGET_HISTORY = "data/target_history.jsonl"   # P5-A2: hedef fiyat REVİZYON arşivi (günde 1 satır)
BASE = "https://www.isyatirim.com.tr"
PAGE_URL = f"{BASE}/tr-tr/analiz/hisse/Sayfalar/gelismis-hisse-arama.aspx"
SCREENER_URL = f"{BASE}/tr-tr/analiz/_Layouts/15/IsYatirim.Website/StockInfo/CompanyInfoAjax.aspx/getScreenerDataNEW"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36"
# borsapy isyatirim_screener: 28=Cari F/K, 30=Cari PD/DD, 422=Cari ROE, 8=Piyasa Değeri,
# 51=Hedef Fiyat (TL), 61=Getiri Potansiyeli (%) — İş Yatırım analist hedefleri.
# Hedef SEVİYESİYLE skorlanmaz (tek kurum + değer-proxy); asıl sinyal REVİZYON olduğu
# için günlük arşiv (TARGET_HISTORY) tutulur; revizyon faktörü geçmiş birikince kurulur.
CRIT_PE, CRIT_PB, CRIT_ROE, CRIT_MCAP = "28", "30", "422", "8"
CRIT_TARGET, CRIT_UPSIDE = "51", "61"
WIDE = ("-1000000", "1000000", "False")  # geniş aralık: değeri olan tüm hisseler


def to_float(v):
    """İş Yatırım sayı biçimi: ondalık ',' ve (varsa) binlik '.'. Hem 'binlik.ondalık,'
    hem düz 'ondalık,' hem düz float'ı çöz. Boş/'-'/çözülemeyen -> None."""
    if v is None:
        return None
    s = str(v).strip()
    if s in ("", "-", "N/A", "n/a"):
        return None
    if "," in s:                      # ',' ondalık -> '.' binliği at, ',' -> '.'
        s = s.replace(".", "").replace(",", ".")
    try:
        return float(s)
    except ValueError:
        return None


def fetch_screener():
    """Cookie + digest al, screener'a F/K+PD/DD+ROE+PD kriterleriyle POST at."""
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(CookieJar()))
    req = urllib.request.Request(PAGE_URL, headers={
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"})
    digest = None
    with opener.open(req, timeout=30) as r:
        m = re.search(r'id="__REQUESTDIGEST"[^>]*value="([^"]+)"', r.read().decode("utf-8", "replace"))
        if m:
            digest = m.group(1)
    payload = {"sektor": "", "endeks": "", "takip": "", "oneri": "",
               "criterias": [[CRIT_PE, *WIDE], [CRIT_PB, *WIDE], [CRIT_ROE, *WIDE], [CRIT_MCAP, *WIDE],
                             [CRIT_TARGET, *WIDE], [CRIT_UPSIDE, *WIDE]],
               "lang": "1055"}
    headers = {"User-Agent": UA,
               "Content-Type": "application/json; charset=UTF-8",
               "X-Requested-With": "XMLHttpRequest",
               "Accept": "application/json, text/javascript, */*; q=0.01",
               "Origin": BASE, "Referer": PAGE_URL}
    if digest:
        headers["X-RequestDigest"] = digest
    req = urllib.request.Request(SCREENER_URL, data=json.dumps(payload).encode(), headers=headers)
    with opener.open(req, timeout=40) as r:
        outer = json.loads(r.read().decode("utf-8", "replace"))
    rows = json.loads(outer.get("d", "[]"))
    if not rows:
        raise RuntimeError(f"screener bos yanit: {str(outer)[:300]}")
    return rows


def parse_rows(rows):
    """Satırları {SYM: (pe, pb, roe, mcap, target, upside)} yap; kriter-id anahtarları savunmacı çözülür."""
    sample = rows[0]
    if CRIT_PE in sample:
        kp, kb, kr, km, kt, ku = CRIT_PE, CRIT_PB, CRIT_ROE, CRIT_MCAP, CRIT_TARGET, CRIT_UPSIDE
    else:
        # Kriter id anahtarı dönmediyse Hisse-dışı sayısal alanları istenen SIRAYLA eşle.
        keys = [k for k in sample.keys() if k != "Hisse"]
        num_keys = [k for k in keys if to_float(sample.get(k)) is not None]
        if len(num_keys) < 3:
            raise RuntimeError(f"screener satirinda yeterli sayisal alan yok; ornek: {str(sample)[:400]}")
        print(f"[uyari] kriter id anahtari yok; alan sirasi varsayildi: {num_keys}", flush=True)
        pad = num_keys + [None] * 6
        kp, kb, kr, km, kt, ku = pad[0], pad[1], pad[2], pad[3], pad[4], pad[5]
    items = {}
    for row in rows:
        sym = str(row.get("Hisse", "")).split(" - ", 1)[0].strip().upper()
        if not sym:
            continue
        pe = to_float(row.get(kp)) if kp else None
        pb = to_float(row.get(kb)) if kb else None
        roe = to_float(row.get(kr)) if kr else None
        mcap = to_float(row.get(km)) if km else None
        target = to_float(row.get(kt)) if kt else None
        upside = to_float(row.get(ku)) if ku else None
        if pe is None and pb is None and roe is None and target is None:
            continue
        items[sym] = (pe, pb, roe, mcap, target, upside)
    if not items:
        raise RuntimeError(f"screener parse 0 kayit; ilk satir: {str(sample)[:400]}")
    return items


def fetch_with_retry(attempts=3):
    """Geçici hataya karşı artan beklemeli retry; kalıcı kırılmada dosya EZİLMEZ."""
    last = None
    for i in range(1, attempts + 1):
        try:
            return parse_rows(fetch_screener())
        except Exception as e:
            last = e
            print(f"[probe] isyatirim-fund denemesi {i}/{attempts}: {type(e).__name__}: {e}", flush=True)
            if i < attempts:
                time.sleep(3.0 * i)
    raise last


def append_target_history(data):
    """P5-A2: hedef fiyatları günde 1 kompakt JSONL satırı olarak arşivle
    (revizyon sinyali = hedefin ZAMAN içindeki değişimi; geçmiş olmadan hesaplanamaz).
    Aynı gün ikinci koşuda satır tekrarlanmaz."""
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    targets = {s: t for s, (_, _, _, _, t, _) in data.items() if t is not None and t > 0}
    if not targets:
        print("[hedef] hic hedef fiyat donmedi; arsiv satiri yazilmadi.")
        return
    try:
        with open(TARGET_HISTORY, encoding="utf-8") as f:
            for line in f:
                if f'"d": "{today}"' in line or f'"d":"{today}"' in line:
                    print(f"[hedef] {today} satiri zaten var; tekrar yazilmadi.")
                    return
    except FileNotFoundError:
        pass
    with open(TARGET_HISTORY, "a", encoding="utf-8") as f:
        f.write(json.dumps({"d": today, "targets": dict(sorted(targets.items()))},
                           ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"[hedef] {len(targets)} hisse hedef fiyati arsivlendi -> {TARGET_HISTORY}")


def main():
    try:
        data = fetch_with_retry()
    except Exception as e:
        print(f"[probe] isyatirim-fund {type(e).__name__}: {e}", flush=True)
        print("[sonuc] ikinci temel-veri kaynagi calismadi; dosya degistirilmedi.")
        return 0  # akisi bozma
    out = {"generatedAt": datetime.now(timezone.utc).isoformat(),
           "source": "isyatirim-screener",
           "asOfNote": "Is Yatirim cari F/K, PD/DD, ROE + analist hedef fiyat/potansiyel (ikinci kaynak).",
           "count": len(data),
           "items": {s: {"pe": pe, "pb": pb, "roe": roe, "mcapMnTL": mcap,
                         "targetPriceTL": target, "upsidePotentialPct": upside}
                     for s, (pe, pb, roe, mcap, target, upside) in sorted(data.items())}}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print(f"[sonuc] isyatirim ikinci temel-veri: {len(data)} hisse yazildi -> {OUT}")
    try:
        append_target_history(data)
    except Exception as e:
        print(f"[hedef] arsiv yazilamadi (kritik degil): {type(e).__name__}: {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
