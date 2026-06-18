#!/usr/bin/env python3
"""
collect_kap.py — TUM BIST hisseleri icin KAP son bildirimlerini borsapy ile ceker,
kategorilere ayirir ve data/kap_disclosures.json olarak yazar.

Ana PowerShell rapor bu JSON'i best-effort okur (gozlem modu). Bu script ana
botu/Windows runner'i ETKILEMEZ; ayri (ubuntu) job olarak calisir.

Dayaniklilik: her hisse try/catch; genel sure limiti; ilerleme logu. Rate-limit'e
karsi hisse arasi kucuk bekleme (opsiyonel).
"""
import argparse
import json
import re
import sys
import time
from datetime import datetime, timezone

# ---------------------------------------------------------------------------
# KAP kategori semasi: baslik anahtar kelimesi -> (kategori, onem, yon ipucu)
# onem: high | earnings | insider | governance | other
# yon : +  (genelde olumlu) | -  (olumsuz) | ~ (karisik/baglamsal) | 0 (notr) | ? (detay gerekir)
# Sira onemli: ilk eslesen kazanir; spesifikten genele dogru dizildi.
# ---------------------------------------------------------------------------
CATEGORY_RULES = [
    ("Birlesme/Devralma", "high",       "+", ["birleşme", "devralma", "satın alma", "pay devri", "hisse devri", "iştirak edinim"]),
    ("Ihale/Sozlesme",    "high",       "+", ["ihale", "sözleşme", "yeni iş ilişkisi", "sipariş", "anlaşma", "yurt dışı satış", "satış sözleşme", "proje"]),
    ("Geri Alim",         "high",       "+", ["geri alım", "pay geri al", "geri alim"]),
    ("Temettu",           "high",       "+", ["kar payı", "kâr payı", "temettü", "kar dağıt", "kâr dağıt", "nakit kar"]),
    ("Sermaye Artirimi",  "high",       "~", ["sermaye artırım", "bedelli", "bedelsiz", "tahsisli", "kayıtlı sermaye"]),
    ("Kredi Notu",        "high",       "~", ["derecelendirme", "kredi not", "rating", "kredi derece"]),
    ("Yatirim/Tesis",     "high",       "+", ["yatırım kararı", "kapasite artır", "yeni tesis", "fabrika", "üretim tesisi"]),
    ("Insider/Pay Bildirimi", "insider", "~", ["pay alım satım", "ortaklık pay", "yönetici işlem", "içsel bilgi", "geri alınan pay", "payların geri"]),
    ("Bilanco/Finansal",  "earnings",   "0", ["finansal rapor", "faaliyet rapor", "sorumluluk beyan", "finansal tablo", "bilanço", "ara dönem"]),
    ("Genel Kurul",       "governance", "0", ["genel kurul", "gündem", "olağan genel", "olağanüstü genel"]),
    ("Sirket Bilgi",      "governance", "0", ["genel bilgi formu", "yatırımcı ilişkileri", "esas sözleşme", "şirket genel bilgi"]),
    ("Ozel Durum (Genel)", "high",      "?", ["özel durum"]),  # genel ODA — yon icin detay gerekir
]


def classify(title: str):
    t = (title or "").lower()
    for category, importance, direction, keys in CATEGORY_RULES:
        if any(k in t for k in keys):
            return category, importance, direction
    return "Diger", "other", "?"


def disclosure_id_from_url(url: str):
    m = re.search(r"/Bildirim/(\d+)", str(url or ""))
    return m.group(1) if m else None


def extract_tickers(borsapy):
    """borsapy'den tum BIST hisse kodlarini, donen yapidan bagimsiz cikar."""
    candidates = []
    for fn_name in ("companies", "search_bist", "search_companies"):
        fn = getattr(borsapy, fn_name, None)
        if not callable(fn):
            continue
        try:
            res = fn() if fn_name == "companies" else fn("")
        except Exception as e:
            print(f"  {fn_name}() hatasi: {type(e).__name__}: {e}")
            continue
        # DataFrame mi?
        if hasattr(res, "columns"):
            cols = [str(c).lower() for c in res.columns]
            for key in ("ticker", "symbol", "code", "kod", "stockcode", "stock_code"):
                if key in cols:
                    col = res.columns[cols.index(key)]
                    candidates = [str(x).strip().upper() for x in res[col].tolist() if str(x).strip()]
                    break
            if not candidates:
                # index'i dene
                try:
                    candidates = [str(x).strip().upper() for x in res.index.tolist() if str(x).strip()]
                except Exception:
                    pass
        elif isinstance(res, (list, tuple)):
            for item in res:
                if isinstance(item, str):
                    candidates.append(item.strip().upper())
                elif isinstance(item, dict):
                    for key in ("ticker", "symbol", "code", "kod"):
                        if key in item:
                            candidates.append(str(item[key]).strip().upper())
                            break
        if candidates:
            print(f"Hisse listesi kaynagi: borsapy.{fn_name}() -> {len(candidates)} kod")
            break
    # temizle: 3-6 harf/rakam BIST kodlari
    seen, out = set(), []
    for c in candidates:
        c = re.sub(r"[^A-Z0-9]", "", c)
        if 2 <= len(c) <= 6 and c not in seen:
            seen.add(c)
            out.append(c)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-stocks", type=int, default=0, help="0 = tum hisseler")
    ap.add_argument("--news-limit", type=int, default=8, help="hisse basina en fazla bildirim")
    ap.add_argument("--max-seconds", type=int, default=900, help="genel sure limiti")
    ap.add_argument("--sleep", type=float, default=0.0, help="hisse arasi bekleme (rate-limit)")
    ap.add_argument("--out", default="data/kap_disclosures.json")
    args = ap.parse_args()

    started = time.time()
    print("=" * 70)
    print("KAP toplayici (borsapy)")
    print("=" * 70)
    try:
        import borsapy
    except Exception as e:
        print(f"borsapy import HATASI: {e}")
        sys.exit(1)
    ver = getattr(borsapy, "__version__", "?")
    print(f"borsapy {ver}")

    tickers = extract_tickers(borsapy)
    if not tickers:
        print("HATA: hisse listesi alinamadi; cikiliyor.")
        sys.exit(1)
    if args.max_stocks > 0:
        tickers = tickers[: args.max_stocks]
    print(f"Islenecek hisse: {len(tickers)}")

    stocks = {}
    cat_summary = {}
    total_disc = 0
    with_news = 0
    errors = 0

    for i, sym in enumerate(tickers, 1):
        if time.time() - started > args.max_seconds:
            print(f"!! Sure limiti ({args.max_seconds}s) asildi; {i-1} hissede durduruldu.")
            break
        try:
            news = borsapy.Ticker(sym).news
            rows = []
            if news is not None and hasattr(news, "iterrows"):
                for _, r in news.head(args.news_limit).iterrows():
                    title = str(r.get("Title", "") if hasattr(r, "get") else r["Title"])
                    url = str(r.get("URL", "") if hasattr(r, "get") else r["URL"])
                    date = str(r.get("Date", "") if hasattr(r, "get") else r["Date"])
                    cat, imp, direction = classify(title)
                    rows.append({
                        "date": date, "title": title, "category": cat,
                        "importance": imp, "direction": direction,
                        "disclosureId": disclosure_id_from_url(url), "url": url,
                    })
                    cat_summary[cat] = cat_summary.get(cat, 0) + 1
            if rows:
                stocks[sym] = rows
                total_disc += len(rows)
                with_news += 1
        except Exception as e:
            errors += 1
            if errors <= 10:
                print(f"  {sym}: HATA {type(e).__name__}: {e}")
        if i % 50 == 0:
            print(f"  ... {i}/{len(tickers)} islendi | bildirimli hisse={with_news} | {int(time.time()-started)}s")
        if args.sleep > 0:
            time.sleep(args.sleep)

    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": f"borsapy {ver}",
        "processedStocks": len(tickers),
        "stocksWithNews": with_news,
        "totalDisclosures": total_disc,
        "errors": errors,
        "categorySummary": dict(sorted(cat_summary.items(), key=lambda kv: -kv[1])),
        "stocks": stocks,
    }
    import os
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    print("-" * 70)
    print(f"Bildirimli hisse: {with_news}/{len(tickers)} | toplam bildirim: {total_disc} | hata: {errors}")
    print("Kategori dagilimi:", json.dumps(payload["categorySummary"], ensure_ascii=False))
    print(f"Yazildi: {args.out} | sure: {int(time.time()-started)}s")


if __name__ == "__main__":
    main()
