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
    """borsapy'den tum BIST hisse kodlarini, donen yapidan bagimsiz cikar.

    Yalniz companies() gecerli 'tum evren' kaynagi (search_* bos sorgu kabul
    etmez). Gecici timeout'a karsi 3 deneme + artan bekleme; hepsi basarisizsa
    bos doner ve cagiran onceki commit'li evrene duser (akis bozulmaz)."""
    candidates = []
    for fn_name in ("companies",):
        fn = getattr(borsapy, fn_name, None)
        if not callable(fn):
            continue
        res = None
        for attempt in range(1, 4):
            try:
                res = fn()
                break
            except Exception as e:
                print(f"  {fn_name}() denemesi {attempt}/3 hatasi: {type(e).__name__}: {e}")
                if attempt < 3:
                    time.sleep(3.0 * attempt)
        if res is None:
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


def _parse_date(s):
    """KAP tarih metnini datetime'a cevirir (siralama icin). borsapy 'dd.MM.yyyy'
    (ops. saat) verir; ISO da denenir. Cozulemezse None."""
    s = str(s or "").strip()
    if not s:
        return None
    for fmt in ("%d.%m.%Y %H:%M", "%d.%m.%Y %H:%M:%S", "%d.%m.%Y",
                "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(s[:len(fmt) + 2], fmt)
        except Exception:
            continue
    try:
        return datetime.fromisoformat(s)
    except Exception:
        return None


def _rec_key(r):
    """Bir bildirim icin tekillestirme anahtari: disclosureId varsa o, yoksa
    tarih+baslik."""
    did = r.get("disclosureId")
    if did:
        return ("id", str(did))
    return ("dt", str(r.get("date", "")), str(r.get("title", "")))


def _merge_stock(existing, new_rows, max_archive):
    """Bir hissenin mevcut arsiviyle yeni cekilen bildirimleri birlestirir:
    disclosureId'ye gore tekillestirir, tarihe gore (yeni->eski) siralar, en fazla
    max_archive kayit tutar. Mevcut kayitlar KORUNUR; yalniz yeniler eklenir."""
    merged = {}
    for r in (existing or []):
        merged[_rec_key(r)] = r
    added = 0
    for r in (new_rows or []):
        k = _rec_key(r)
        if k not in merged:
            added += 1
        merged[k] = r  # yeni siniflandirma/alanlarla guncelle
    rows = list(merged.values())
    rows.sort(key=lambda r: (_parse_date(r.get("date")) or datetime.min), reverse=True)
    if max_archive > 0:
        rows = rows[:max_archive]
    return rows, added


def _load_json_bom(path):
    """PowerShell state dosyalari UTF-8 BOM ile yazilir; utf-8-sig ile okur."""
    with open(path, "r", encoding="utf-8-sig") as f:
        return json.load(f)


def load_priority_symbols(data_dir):
    """Botun gunluk yazdigi state dosyalarindan ONCELIKLI hisseleri toplar:
    Top picks (signal_performance.PendingPicks), model portfoy holdingleri ve
    anlik giris portfoyu holdingleri. Bu hisseler her kosuda taranir. Best-effort;
    dosya yoksa/bozuksa sessizce atlanir. Doner: buyuk harf sembol kumesi."""
    import os
    syms = set()

    def add(s):
        if s:
            c = re.sub(r"[^A-Z0-9]", "", str(s).strip().upper())
            if 2 <= len(c) <= 6:
                syms.add(c)

    # Top picks (Top N) — signal_performance.json
    try:
        d = _load_json_bom(os.path.join(data_dir, "signal_performance.json"))
        for p in ((d.get("PendingPicks") or {}).get("Picks") or []):
            if isinstance(p, dict):
                add(p.get("Symbol"))
    except Exception:
        pass
    # Model portfoy holdingleri — model_portfolios.json
    try:
        d = _load_json_bom(os.path.join(data_dir, "model_portfolios.json"))
        for p in (d.get("Portfolios") or []):
            for h in (p.get("Holdings") or []):
                if isinstance(h, dict):
                    add(h.get("Symbol"))
    except Exception:
        pass
    # Anlik giris portfoyu holdingleri — instant_entry_portfolio.json
    try:
        d = _load_json_bom(os.path.join(data_dir, "instant_entry_portfolio.json"))
        for h in (d.get("Holdings") or []):
            if isinstance(h, dict):
                add(h.get("Symbol"))
    except Exception:
        pass
    return syms


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-stocks", type=int, default=0, help="0 = tum evren (rotasyon icin taban liste)")
    ap.add_argument("--news-limit", type=int, default=8, help="hisse basina cekilen en yeni bildirim")
    ap.add_argument("--max-seconds", type=int, default=1500, help="genel sure limiti")
    ap.add_argument("--sleep", type=float, default=0.5, help="hisse arasi bekleme (rate-limit)")
    ap.add_argument("--retries", type=int, default=2, help="hisse basina yeniden deneme")
    ap.add_argument("--retry-wait", type=float, default=4.0, help="retry taban bekleme (artan: wait*deneme)")
    ap.add_argument("--cooldown", type=float, default=45.0, help="ardisik hata kumesinde bir defalik soguma (sn)")
    ap.add_argument("--cooldown-after", type=int, default=8, help="cooldown tetikleyen ardisik hata sayisi")
    ap.add_argument("--max-cooldowns", type=int, default=4, help="en fazla cooldown sayisi")
    # Biriktirme + dönüşümlü tarama (gunluk kullanim icin):
    ap.add_argument("--rotate-size", type=int, default=0,
                    help="bu kosuda taranacak hisse sayisi (0=tum evren). Gunluk icin ~260; "
                         "kalan hisseler onceki verisini korur, sonraki gun siradan devam eder.")
    ap.add_argument("--max-archive", type=int, default=40, help="hisse basina arsivde tutulacak en fazla bildirim")
    ap.add_argument("--no-merge", action="store_true", help="birlestirme kapali; dosyayi sifirdan yaz")
    ap.add_argument("--no-priority", action="store_true",
                    help="oncelikli (Top/portfoy/anlik giris) hisseleri her kosu tarama; sadece rotasyon")
    ap.add_argument("--out", default="data/kap_disclosures.json")
    args = ap.parse_args()

    started = time.time()
    print("=" * 70)
    print("KAP toplayici (borsapy) — biriktirme/dönüşümlü mod")
    print("=" * 70)
    try:
        import borsapy
    except Exception as e:
        print(f"borsapy import HATASI: {e}")
        sys.exit(1)
    ver = getattr(borsapy, "__version__", "?")
    print(f"borsapy {ver}")

    import os
    # Mevcut arsivi yukle (biriktirme icin).
    prev = {}
    if not args.no_merge and os.path.exists(args.out):
        try:
            with open(args.out, "r", encoding="utf-8") as f:
                prev = json.load(f)
        except Exception as e:
            print(f"Mevcut JSON okunamadi ({type(e).__name__}); sifirdan baslanacak.")
            prev = {}
    stocks = dict(prev.get("stocks", {})) if isinstance(prev, dict) else {}
    prev_cursor = int(prev.get("rotationCursor", 0)) if isinstance(prev, dict) else 0

    tickers = extract_tickers(borsapy)
    if not tickers and stocks:
        # borsapy gecici olarak liste veremedi (or. timeout) ama elimizde onceki
        # kosunun evreni var -> onu kullan (yeni bildirim gelmese de akis bozulmaz).
        tickers = sorted(stocks.keys())
        print(f"Canli liste alinamadi; onceki commit'li evren kullaniliyor ({len(tickers)} kod).")
    if not tickers:
        # Ilk kosu + kaynak erisilemez: sessizce ve BASARIYLA cik (MKK/TEFAS ile
        # ayni felsefe). exit 1 her gecici timeout'ta GitHub 'jobs failed' maili
        # uretiyordu; gozlem-modu bir toplayici icin bu gurultu istenmez.
        print("Hisse listesi alinamadi ve onceki evren de yok; bu kosu atlandi (exit 0).")
        sys.exit(0)
    if args.max_stocks > 0:
        tickers = tickers[: args.max_stocks]
    n = len(tickers)
    universe = set(tickers)

    # ONCELIKLI hisseler: her kosuda taranir (Top picks + portfoy + anlik giris).
    data_dir = os.path.dirname(args.out) or "."
    priority = set()
    if not args.no_priority:
        priority = load_priority_symbols(data_dir) & universe
    priority_list = [t for t in tickers if t in priority]   # evren sirasinda, sabit
    rest = [t for t in tickers if t not in priority]         # dönüşümlü taranacaklar
    nrest = len(rest)

    # rest icinde dönüşümlü dilim (cursor rest'e gore).
    rot = args.rotate_size if args.rotate_size > 0 else nrest
    rot = min(rot, nrest)
    start = prev_cursor % nrest if nrest else 0
    rest_slice = [rest[(start + k) % nrest] for k in range(rot)] if nrest else []

    # Bu kosu listesi: once oncelikliler (taze), sonra rest dilimi.
    slice_syms = priority_list + rest_slice
    n_priority = len(priority_list)
    print(f"Evren: {n} | oncelikli (her gun): {n_priority} | rest dilimi: {rot}/{nrest} "
          f"(idx {start}) | toplam bu kosu: {len(slice_syms)} | "
          f"merge={'kapali' if args.no_merge else 'acik'} | sleep={args.sleep}s | max-seconds={args.max_seconds}")
    if n_priority:
        print(f"Oncelikli hisseler: {','.join(priority_list)}")

    fetched_ok = 0
    new_added = 0
    errors = 0
    consecutive_fail = 0
    cooldowns_used = 0
    processed = 0
    rest_done = 0   # cursor yalniz rest ilerlemesini sayar (oncelikliler kaydirmaz)

    for i, sym in enumerate(slice_syms, 1):
        if time.time() - started > args.max_seconds:
            print(f"!! Sure limiti ({args.max_seconds}s) asildi; {i-1}/{len(slice_syms)} hissede durduruldu.")
            break
        processed = i
        is_rest = i > n_priority

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
                merged, added = _merge_stock(stocks.get(sym), rows, args.max_archive)
                stocks[sym] = merged
                fetched_ok += 1
                new_added += added
        else:
            errors += 1
            consecutive_fail += 1
            if errors <= 10:
                print(f"  {sym}: HATA {type(last_err).__name__}: {last_err}")
            if (consecutive_fail >= args.cooldown_after and cooldowns_used < args.max_cooldowns
                    and (time.time() - started) < (args.max_seconds - args.cooldown)):
                cooldowns_used += 1
                print(f"  !! {consecutive_fail} ardisik hata; cooldown {int(args.cooldown)}s "
                      f"({cooldowns_used}/{args.max_cooldowns})")
                time.sleep(args.cooldown)
                consecutive_fail = 0

        if is_rest:
            rest_done += 1

        if i % 50 == 0:
            print(f"  ... {i}/{len(slice_syms)} | yeni cekilen={fetched_ok} | yeni bildirim={new_added} | "
                  f"hata={errors} | {int(time.time()-started)}s")
        if args.sleep > 0:
            time.sleep(args.sleep)

    # Cursor yalniz islenen rest kadar ilerler (kismi kosuda dogru devam icin).
    next_cursor = (start + rest_done) % nrest if nrest else 0

    # Tum arsiv uzerinden ozet (yalniz bu kosu degil).
    cat_summary = {}
    total_disc = 0
    with_news = 0
    for sym, rows in stocks.items():
        if rows:
            with_news += 1
            total_disc += len(rows)
            for r in rows:
                cat = r.get("category", "Diger")
                cat_summary[cat] = cat_summary.get(cat, 0) + 1

    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": f"borsapy {ver}",
        "universeSize": n,
        "rotationCursor": next_cursor,
        "lastRun": {
            "priorityCount": n_priority,
            "prioritySymbols": priority_list,
            "restSliceSize": rot,
            "restSliceStart": start,
            "restProcessed": rest_done,
            "processed": processed,
            "fetchedOk": fetched_ok,
            "newDisclosures": new_added,
            "errors": errors,
            "cooldowns": cooldowns_used,
            "elapsedSec": int(time.time() - started),
        },
        "stocksWithNews": with_news,
        "totalDisclosures": total_disc,
        "errors": errors,
        "categorySummary": dict(sorted(cat_summary.items(), key=lambda kv: -kv[1])),
        "stocks": stocks,
    }
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    print("-" * 70)
    print(f"Bu kosu: oncelikli={n_priority} + rest={rest_done} | {fetched_ok} hisse cekildi | "
          f"{new_added} yeni bildirim | hata={errors} | cooldown={cooldowns_used} | "
          f"sonraki rest-cursor={next_cursor}/{nrest}")
    print(f"Arsiv toplam: bildirimli hisse {with_news}/{n} | toplam bildirim {total_disc}")
    print("Kategori dagilimi (arsiv):", json.dumps(payload["categorySummary"], ensure_ascii=False))
    print(f"Yazildi: {args.out} | sure: {int(time.time()-started)}s")


if __name__ == "__main__":
    main()
