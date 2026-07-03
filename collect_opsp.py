#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""collect_opsp.py — Takasbank Ödünç Pay Piyasası (ÖPP) probe + collect.

Amaç (Smart Money): hisse bazında ödünç/açığa-satış yoğunluğu, kısa vadeli
NEGATİF sinyal adayıdır (literatür: yüksek ödünç bakiyesi ~ gelecek düşük
getiri). Takasbank 'ÖPP Günlük Bülten' sayfası herkese açıktır ama dosya URL
kalıbı bilinmediğinden bu script ÖNCE TANI yapar:

  1) Bülten sayfasının HTML'ini çeker, 'bulten/odunc/opp/xls/csv/pdf' geçen
     tüm href'leri loglar (CI logu sonraki iterasyona kalıp verir).
  2) Bilinen aday API/dosya kalıplarını dener; JSON/CSV parse edebilirse
     data/opsp_lending.json yazar.

Kaynak erişilemezse exit 0 + tanılayıcı log (akış bozulmaz).
Çıktı: { generatedAt, asOf, note, count, items: { SYM: { lentShares, ... } } }
"""
import json, re, sys, urllib.request
from datetime import date, datetime, timezone

OUT = "data/opsp_lending.json"
BASE = "https://www.takasbank.com.tr"
PAGE = f"{BASE}/tr/istatistikler/odunc-pay-piyasasi-opp/opp-gunluk-bulten"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
    "Accept-Language": "tr-TR,tr;q=0.9",
    "Referer": BASE,
}


def fetch(url, timeout=30):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def probe_page():
    """Bulten sayfasindaki dosya/endpoint linklerini loga doker (tani)."""
    body = fetch(PAGE).decode("utf-8", "replace")
    print(f"[bilgi] sayfa alindi: {len(body)} bayt", flush=True)
    hrefs = re.findall(r'(?:href|src|data-url)=["\']([^"\']+)["\']', body)
    hits = [h for h in hrefs if re.search(r"bulten|odunc|opp|\.xls|\.csv|\.pdf|api|dosya|download", h, re.I)]
    seen = []
    for h in hits:
        if h not in seen:
            seen.append(h)
    print(f"[tani] aday link sayisi: {len(seen)}", flush=True)
    for h in seen[:40]:
        print(f"  LINK: {h}", flush=True)
    # XHR ipucu: sayfa ici fetch/ajax cagrilari
    for m in re.findall(r'(?:fetch|ajax|axios[.\w]*)\(["\']([^"\']+)["\']', body)[:10]:
        print(f"  XHR: {m}", flush=True)
    return seen


def main():
    try:
        links = probe_page()
    except Exception as e:
        print(f"[probe] sayfa alinamadi -> {type(e).__name__}: {e}", flush=True)
        print("[sonuc] kaynak calismadi; dosya degistirilmedi.")
        return 0

    # Excel/CSV dogrudan gorunuyorsa ilkini indirip boyut/ilk baytlari logla
    # (parser bir sonraki iterasyonda gercek bicime gore yazilacak — durust tani).
    files = [h for h in links if re.search(r"\.(xlsx?|csv)(\?|$)", h, re.I)]
    if files:
        url = files[0] if files[0].startswith("http") else BASE + files[0]
        try:
            blob = fetch(url)
            print(f"[tani] ilk dosya: {url} -> {len(blob)} bayt; ilk 80 bayt: {blob[:80]!r}", flush=True)
        except Exception as e:
            print(f"[tani] dosya indirilemedi: {url} -> {e}", flush=True)
    print("[sonuc] probe tamamlandi; parser CI logundaki kaliba gore yazilacak.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
