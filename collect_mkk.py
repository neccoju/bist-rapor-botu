#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""collect_mkk.py — Yabancı saklama oranı toplayıcı (probe + collect, tek dosya).

Amaç (Smart Money denetimi #10): hisse bazında yabancı yatırımcı oranını ücretsiz
kaynaktan toplayıp data/mkk_foreign.json'a yazmak. İki aday kaynak sırayla denenir:

  1) İş Yatırım 'Yabancı Oranları' JSON'u (MKK verisinin yeniden yayını; hisse
     bazında, herkese açık, T-gecikmeli). Uzun süredir stabil bilinen endpoint.
  2) MKK VAP (vap.org.tr) sayfa-arkası XHR — biçimi değişkense probe logu yol gösterir.

Dürüstlük: veri MKK kaynaklı ve ~10 iş günü gecikmeli olabilir; dosyaya asOfNote
olarak yazılır ve panelde bu etiketle gösterilmelidir. Kaynak erişilemezse script
exit 0 ile 'veri yok' üretir (akışı bozmaz) ama logda nedenini açıkça söyler.

Çıktı şeması:
{ "generatedAt": iso, "source": "isyatirim|vap", "asOfNote": "...T-gecikmeli...",
  "count": N, "items": { "SYM": {"foreignPct": f, "prevPct": f|null } } }
prevPct: bir önceki koşunun değeri (delta/trend için; ilk koşuda null).
"""
import json, sys, time, urllib.request, urllib.error
from datetime import datetime, timezone

OUT = "data/mkk_foreign.json"
UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) BIST-Rapor-Botu/1.0",
      "Accept": "application/json, text/plain, */*"}

def http_json(url, timeout=25):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", "replace"))

def try_isyatirim():
    """İş Yatırım: tüm hisselerin yabancı oranı (tarih aralıklı sorgu, son değer alınır)."""
    from datetime import date, timedelta
    end = date.today(); start = end - timedelta(days=25)
    url = ("https://www.isyatirim.com.tr/_layouts/15/IsYatirim.Website/Common/Data.aspx/"
           f"YabanciOranlar?startdate={start:%d-%m-%Y}&enddate={end:%d-%m-%Y}")
    d = http_json(url)
    rows = d.get("value") if isinstance(d, dict) else d
    if not rows: raise RuntimeError(f"isyatirim bos yanit: {str(d)[:200]}")
    items = {}
    for row in rows:  # beklenen alanlar: HISSE_KODU / YAB_ORAN / TARIH (probe logu dogrular)
        sym = (row.get("HISSE_KODU") or row.get("Code") or "").strip().upper()
        val = row.get("YAB_ORAN", row.get("YabanciOran"))
        dt = row.get("TARIH") or row.get("Date") or ""
        if not sym or val is None: continue
        cur = items.get(sym)
        if cur is None or str(dt) >= str(cur[1]):
            items[sym] = (float(val), str(dt))
    if not items: raise RuntimeError(f"isyatirim parse 0 kayit; ilk satir: {str(rows[0])[:300]}")
    return "isyatirim", {k: v[0] for k, v in items.items()}

def try_vap():
    """VAP: yerli-yabanci analiz sayfasinin XHR'i (bicim degisebilir; probe amacli)."""
    url = "https://www.vap.org.tr/api/PaySenediAnaliz/YerliYabanci"
    d = http_json(url)
    raise RuntimeError(f"vap yanit alindi ama parser tanimsiz; ornek: {str(d)[:400]}")

def main():
    prev = {}
    try:
        with open(OUT, encoding="utf-8") as f:
            prev = {k: v.get("foreignPct") for k, v in json.load(f).get("items", {}).items()}
    except Exception:
        pass
    source, data, errs = None, None, []
    for name, fn in (("isyatirim", try_isyatirim), ("vap", try_vap)):
        try:
            source, data = fn(); break
        except Exception as e:
            errs.append(f"{name}: {type(e).__name__}: {e}")
            print(f"[probe] {name} basarisiz -> {e}", flush=True)
            time.sleep(1)
    if not data:
        print("[sonuc] hicbir kaynak calismadi; dosya degistirilmedi. Nedenler:", *errs, sep="\n  ")
        return 0  # akisi bozma; probe logu yol gosterir
    out = {"generatedAt": datetime.now(timezone.utc).isoformat(),
           "source": source,
           "asOfNote": "MKK kaynakli yabanci saklama orani; ~10 is gunu gecikmeli olabilir.",
           "count": len(data),
           "items": {s: {"foreignPct": round(p, 2), "prevPct": prev.get(s)} for s, p in sorted(data.items())}}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print(f"[sonuc] {source} kaynagi ile {len(data)} hisse yazildi -> {OUT}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
