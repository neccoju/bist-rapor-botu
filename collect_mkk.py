#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""collect_mkk.py — Yabancı saklama oranı toplayıcı (İş Yatırım screener, stdlib-only).

Amaç (Smart Money denetimi #10): hisse bazında yabancı yatırımcı oranını ücretsiz
kaynaktan toplu çekip data/mkk_foreign.json'a yazmak.

Kaynak: İş Yatırım "Gelişmiş Hisse Arama" ekranının XHR'ı (getScreenerDataNEW).
MKK kaynaklı "Cari Yabancı Oranı" tüm hisseler için tek POST ile gelir; ayrıca
1 haftalık / 1 aylık değişim (baz puan) kriterleri de istenir. Endpoint session
cookie + XHR header ister; önce arama sayfası GET edilip cookie alınır.
(Kriter kimlikleri 40/44/45 borsapy isyatirim_screener sağlayıcısından doğrulandı.)

Dürüstlük: veri MKK kaynaklı ve yayın gecikmeli olabilir; dosyaya asOfNote olarak
yazılır ve panelde bu etiketle gösterilmelidir. Kaynak erişilemezse script exit 0
ile 'veri yok' üretir (akışı bozmaz) ama logda nedenini açıkça söyler.

Çıktı şeması:
{ "generatedAt": iso, "source": "isyatirim-screener", "asOfNote": "...",
  "count": N, "items": { "SYM": {"foreignPct": f, "prevPct": f|null,
                                  "chg1wBps": f|null, "chg1mBps": f|null } } }
prevPct: bir önceki koşunun değeri (delta/trend için; ilk koşuda null).
"""
import json, re, sys, time, urllib.request, urllib.error
from datetime import datetime, timezone
from http.cookiejar import CookieJar

OUT = "data/mkk_foreign.json"
BASE = "https://www.isyatirim.com.tr"
PAGE_URL = f"{BASE}/tr-tr/analiz/hisse/Sayfalar/gelismis-hisse-arama.aspx"
SCREENER_URL = f"{BASE}/tr-tr/analiz/_Layouts/15/IsYatirim.Website/StockInfo/CompanyInfoAjax.aspx/getScreenerDataNEW"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36"
CRIT_FOREIGN, CRIT_CHG_1W, CRIT_CHG_1M = "40", "44", "45"  # Cari Yabancı Oranı (%), 1H/1A değişim (baz)


def to_float(v):
    if v is None: return None
    try:
        return float(str(v).replace(",", "."))
    except ValueError:
        return None


def fetch_screener():
    """Cookie al, screener'a POST at, ham satır listesini döndür."""
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(CookieJar()))
    req = urllib.request.Request(PAGE_URL, headers={
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"})
    digest = None
    with opener.open(req, timeout=30) as r:
        m = re.search(r'id="__REQUESTDIGEST"[^>]*value="([^"]+)"', r.read().decode("utf-8", "replace"))
        if m: digest = m.group(1)
    payload = {"sektor": "", "endeks": "", "takip": "", "oneri": "",
               "criterias": [[CRIT_FOREIGN, "0", "100", "False"],
                             [CRIT_CHG_1W, "-10000", "10000", "False"],
                             [CRIT_CHG_1M, "-10000", "10000", "False"]],
               "lang": "1055"}
    headers = {"User-Agent": UA,
               "Content-Type": "application/json; charset=UTF-8",
               "X-Requested-With": "XMLHttpRequest",
               "Accept": "application/json, text/javascript, */*; q=0.01",
               "Origin": BASE, "Referer": PAGE_URL}
    if digest: headers["X-RequestDigest"] = digest
    req = urllib.request.Request(SCREENER_URL, data=json.dumps(payload).encode(), headers=headers)
    with opener.open(req, timeout=40) as r:
        outer = json.loads(r.read().decode("utf-8", "replace"))
    rows = json.loads(outer.get("d", "[]"))
    if not rows:
        raise RuntimeError(f"screener bos yanit: {str(outer)[:300]}")
    return rows


def parse_rows(rows):
    """Satırları {SYM: (foreignPct, chg1wBps, chg1mBps)} yap; alan adları savunmacı çözülür."""
    sample = rows[0]
    keys = [k for k in sample.keys() if k != "Hisse"]
    # Beklenen: kriter id'leri anahtar olarak döner ("40"/"44"/"45").
    # Dönmüyorsa istenen kriter sırasına göre Hisse-dışı sayısal alanlar eşlenir.
    if CRIT_FOREIGN in sample:
        kf, kw, km = CRIT_FOREIGN, CRIT_CHG_1W, CRIT_CHG_1M
    else:
        num_keys = [k for k in keys if to_float(sample.get(k)) is not None]
        if len(num_keys) < 1:
            raise RuntimeError(f"screener satirinda sayisal alan yok; ornek: {str(sample)[:400]}")
        print(f"[uyari] kriter id anahtari yok; alan sirasi varsayildi: {num_keys}", flush=True)
        kf = num_keys[0]
        kw = num_keys[1] if len(num_keys) > 1 else None
        km = num_keys[2] if len(num_keys) > 2 else None
    items = {}
    for row in rows:
        hisse = str(row.get("Hisse", ""))
        sym = hisse.split(" - ", 1)[0].strip().upper()
        pct = to_float(row.get(kf))
        if not sym or pct is None: continue
        items[sym] = (pct,
                      to_float(row.get(kw)) if kw else None,
                      to_float(row.get(km)) if km else None)
    if not items:
        raise RuntimeError(f"screener parse 0 kayit; ilk satir: {str(sample)[:400]}")
    return items


def fetch_with_retry(attempts=3):
    """Birincil kaynaga (Is Yatirim screener) artan beklemeli retry.
    NOT: Hisse-bazli yabanci oran icin BAGIMSIZ ucretsiz ikinci kaynak yok —
    VAP 404, borsapy de ayni Is Yatirim endpoint'ini kullanir (bkz. oturum
    incelemesi). Bu yuzden 'yedek kaynak' yerine gecici-hataya karsi retry;
    kalici kirilmada dosya EZILMEZ (rapor son commit'li veriyi okumaya devam)."""
    last = None
    for i in range(1, attempts + 1):
        try:
            return parse_rows(fetch_screener())
        except Exception as e:
            last = e
            print(f"[probe] isyatirim-screener denemesi {i}/{attempts}: {type(e).__name__}: {e}", flush=True)
            if i < attempts:
                time.sleep(3.0 * i)
    raise last


def main():
    prev = {}
    try:
        with open(OUT, encoding="utf-8") as f:
            prev = {k: v.get("foreignPct") for k, v in json.load(f).get("items", {}).items()}
    except Exception:
        pass
    try:
        data = fetch_with_retry()
    except Exception as e:
        print(f"[probe] isyatirim-screener {type(e).__name__}: {e}", flush=True)
        print("[sonuc] kaynak calismadi; dosya degistirilmedi.")
        return 0  # akisi bozma; log yol gosterir
    out = {"generatedAt": datetime.now(timezone.utc).isoformat(),
           "source": "isyatirim-screener",
           "asOfNote": "MKK kaynakli cari yabanci orani (Is Yatirim yeniden yayini); yayin gecikmeli olabilir.",
           "count": len(data),
           "items": {s: {"foreignPct": round(p, 2), "prevPct": prev.get(s),
                         "chg1wBps": w, "chg1mBps": m}
                     for s, (p, w, m) in sorted(data.items())}}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print(f"[sonuc] isyatirim-screener ile {len(data)} hisse yazildi -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
