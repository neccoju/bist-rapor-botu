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
# onem: high | earnings | insider | governance | debt | noise | other
#   high      -> fiyat etkisi olabilecek kurumsal olay
#   earnings  -> finansal raporlama / bilanco
#   insider   -> pay alim-satim / icsel bilgi (sahiplik degisimi sinyali)
#   governance-> yonetim/genel kurul/denetim (genelde notr)
#   debt      -> borclanma araci / sabit getirili ihrac (genelde notr)
#   noise     -> piyasa mekanigi (devre kesici, likidite, endeks) — bilgi degeri dusuk
#   other     -> eslesmeyen
# yon : +  (genelde olumlu) | -  (olumsuz) | ~ (karisik/baglamsal) | 0 (notr) | ? (detay gerekir)
# Sira onemli: ilk eslesen kazanir; spesifikten genele dogru dizildi.
# NOT: anahtar kelimeler _norm() ile ayni sekilde normalize edilmis (Turkce-guvenli
# kucuk harf) yazilmalidir: noktali kucuk 'i', 'ş', 'ç', 'ğ', 'ü', 'ö' kullanin.
# ---------------------------------------------------------------------------
CATEGORY_RULES = [
    # --- Yuksek etkili kurumsal olaylar ---
    ("Birlesme/Devralma", "high",       "+", ["birleşme", "devralma", "satın alma", "pay devri", "hisse devri", "iştirak edinim", "şirket satın", "bölünme"]),
    ("Ihale/Sozlesme",    "high",       "+", ["ihale", "sözleşme", "yeni iş ilişkisi", "sipariş", "yeni iş", "satış sözleşme", "proje sözleşme", "bayilik", "distribütör", "yurt dışı satış"]),
    ("Geri Alim",         "high",       "+", ["geri alım", "pay geri al", "geri alınan pay", "payların geri"]),
    ("Temettu",           "high",       "+", ["kar payı", "kâr payı", "temettü", "kar dağıt", "kâr dağıt", "nakit kar", "nakit kâr"]),
    ("Yatirim/Tesis",     "high",       "+", ["yatırım kararı", "kapasite artır", "yeni tesis", "fabrika", "üretim tesisi", "kapasite yatırım"]),
    ("Varlik Alim/Satim", "high",       "~", ["finansal duran varlık", "maddi duran varlık", "duran varlık satı", "duran varlık edinim", "gayrimenkul satı", "gayrimenkul alı", "varlık satışı", "varlık edinimi"]),
    ("Sermaye Artirimi",  "high",       "~", ["sermaye artırım", "bedelli", "bedelsiz", "tahsisli", "kayıtlı sermaye"]),
    ("Kredi Notu",        "high",       "~", ["derecelendirme", "kredi not", "rating", "kredi derece", "not güncelleme"]),
    ("Hukuki/Dava",       "high",       "-", ["dava açıl", "davaya ilişkin", "hukuki süreç", "icra", "iflas", "konkordato", "el konul", "soruşturma"]),
    ("Halka Arz",         "high",       "~", ["halka arz", "izahname", "arz fiyat"]),
    # --- Borclanma / sabit getirili (genelde notr, gurultu degil ama fiyat etkisi dusuk) ---
    ("Borclanma Araci",   "debt",       "0", ["borçlanma araç", "kira sertifika", "ihraç tavan", "ihraç belge", "tertip ihraç", "kupon", "itfa", "tahvil", "sukuk", "varant", "finansman bonosu", "sermaye piyasası aracı"]),
    # --- Icsel/Insider/Pay bildirimleri ---
    ("Insider/Pay Bildirimi", "insider", "~", ["pay alım satım", "ortaklık pay", "yönetici işlem", "içsel bilgi", "pay satış bilgi", "pay  satış", "mali hak kullanım"]),
    ("Hak Kullanimi",     "governance", "0", ["hak kullan"]),
    # --- Bilanco / finansal raporlama ---
    ("Bilanco/Finansal",  "earnings",   "0", ["finansal rapor", "faaliyet rapor", "sorumluluk beyan", "finansal tablo", "bilanço", "ara dönem", "mali tablo", "yatırımcı raporu", "yatırımcı sunum", "faaliyet sonuç"]),
    # --- Kurumsal yonetim / governance ---
    ("Bagimsiz Denetim",  "governance", "0", ["bağımsız denetim"]),
    ("Genel Kurul",       "governance", "0", ["genel kurul", "gündem", "olağan genel", "olağanüstü genel"]),
    ("Kurumsal Yonetim",  "governance", "0", ["kurumsal yönetim", "yönetim kurulu komite", "ilişkili taraf", "esas sözleşme", "yönetim kurulu üye", "istifa", "atama"]),
    ("Sirket Bilgi",      "governance", "0", ["genel bilgi formu", "yatırımcı ilişkileri", "şirket genel bilgi", "geleceğe dönük"]),
    # --- Piyasa mekanigi / teknik (gurultu — bilgi degeri dusuk) ---
    ("Piyasa/Teknik",     "noise",      "0", ["devre kesici", "likidite sağlayıc", "bistech", "bıstech", "fiili dolaşım", "tipe dönüşüm", "endeks", "işlem görmeye başla", "işlem sıras", "sıra kapat", "brüt takas", "açığa satış", "tedbir"]),
    # --- Genel ODA (yon icin detay gerekir; cogu zaman gercek haber burada) ---
    ("Ozel Durum (Genel)", "high",      "?", ["özel durum"]),
]


def _norm(s: str) -> str:
    """Turkce-guvenli kucuk harf. Python str.lower() 'İ' -> 'i' + U+0307 (birlesik
    nokta) urettigi icin 'ihale' gibi anahtarlar İ ile baslayan basliklarda
    eslesmez. Once İ->i, I->ı haritalayip sonra lower; birlesik noktayi temizle."""
    s = (s or "").replace("İ", "i").replace("I", "ı")
    return s.lower().replace("̇", "")


def classify(title: str):
    t = _norm(title)
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


def _fetch_news_rows(borsapy, sym, news_limit):
    """Tek hisse icin KAP bildirim satirlarini ceker (siniflandirilmis). Her
    cagrida yeni Ticker olusturur (olu keep-alive baglantisini tazelemek icin)."""
    news = borsapy.Ticker(sym).news
    rows = []
    if news is not None and hasattr(news, "iterrows"):
        for _, r in news.head(news_limit).iterrows():
            title = str(r.get("Title", "") if hasattr(r, "get") else r["Title"])
            url = str(r.get("URL", "") if hasattr(r, "get") else r["URL"])
            date = str(r.get("Date", "") if hasattr(r, "get") else r["Date"])
            cat, imp, direction = classify(title)
            rows.append({
                "date": date, "title": title, "category": cat,
                "importance": imp, "direction": direction,
                "disclosureId": disclosure_id_from_url(url), "url": url,
            })
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-stocks", type=int, default=0, help="0 = tum hisseler")
    ap.add_argument("--news-limit", type=int, default=8, help="hisse basina en fazla bildirim")
    ap.add_argument("--max-seconds", type=int, default=1500, help="genel sure limiti")
    ap.add_argument("--sleep", type=float, default=0.6, help="hisse arasi bekleme (rate-limit; ~0.6s ile <1 istek/sn)")
    # Throttle dayanikliligi: kaynak ~100 hizli istekten sonra baglantiyi kesiyor
    # ("Server disconnected"). Per-hisse backoff retry + ardisik hata kumelenince
    # bir defalik cooldown ile pencerenin sifirlanmasi saglanir.
    ap.add_argument("--retries", type=int, default=3, help="hisse basina yeniden deneme")
    ap.add_argument("--retry-wait", type=float, default=6.0, help="retry taban bekleme (artan: wait*deneme)")
    ap.add_argument("--cooldown", type=float, default=45.0, help="ardisik hata kumesinde bir defalik soguma (sn)")
    ap.add_argument("--cooldown-after", type=int, default=6, help="cooldown tetikleyen ardisik hata sayisi")
    ap.add_argument("--max-cooldowns", type=int, default=8, help="en fazla cooldown sayisi")
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
    print(f"Islenecek hisse: {len(tickers)} | sleep={args.sleep}s retries={args.retries} "
          f"cooldown={args.cooldown}s/{args.cooldown_after} max-seconds={args.max_seconds}")

    stocks = {}
    cat_summary = {}
    total_disc = 0
    with_news = 0
    errors = 0
    consecutive_fail = 0
    cooldowns_used = 0

    for i, sym in enumerate(tickers, 1):
        if time.time() - started > args.max_seconds:
            print(f"!! Sure limiti ({args.max_seconds}s) asildi; {i-1} hissede durduruldu.")
            break

        rows = None
        last_err = None
        for attempt in range(1, args.retries + 1):
            if time.time() - started > args.max_seconds:
                break
            try:
                rows = _fetch_news_rows(borsapy, sym, args.news_limit)
                last_err = None
                break
            except Exception as e:
                last_err = e
                if attempt < args.retries:
                    time.sleep(args.retry_wait * attempt)

        if last_err is None:
            consecutive_fail = 0
            if rows:
                stocks[sym] = rows
                total_disc += len(rows)
                with_news += 1
                for r in rows:
                    cat_summary[r["category"]] = cat_summary.get(r["category"], 0) + 1
        else:
            errors += 1
            consecutive_fail += 1
            if errors <= 10:
                print(f"  {sym}: HATA {type(last_err).__name__}: {last_err}")
            # Ardisik hata kumesi -> kaynak bizi throttle ediyor olabilir; bir
            # defalik daha uzun soguma ile pencereyi sifirlamayi dene.
            if (consecutive_fail >= args.cooldown_after and cooldowns_used < args.max_cooldowns
                    and (time.time() - started) < (args.max_seconds - args.cooldown)):
                cooldowns_used += 1
                print(f"  !! {consecutive_fail} ardisik hata; cooldown {int(args.cooldown)}s "
                      f"({cooldowns_used}/{args.max_cooldowns})")
                time.sleep(args.cooldown)
                consecutive_fail = 0

        if i % 50 == 0:
            print(f"  ... {i}/{len(tickers)} islendi | bildirimli hisse={with_news} | "
                  f"hata={errors} | {int(time.time()-started)}s")
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
