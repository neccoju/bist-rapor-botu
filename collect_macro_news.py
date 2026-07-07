#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""collect_macro_news.py — TR makro haber toplayıcı + KURAL TABANLI olay sınıflandırıcı.

Amaç: Google News RSS'ten (anahtar gerektirmez) Türkiye makro başlıklarını çekip
DETERMİNİSTİK anahtar-kelime kurallarıyla makro olay taksonomisine map etmek:
inflation / interest_rate / central_bank_tone / cds_risk / fx_pressure /
commodity_oil / political_regulatory. Çıktıyı data/macro_news.json'a yazar;
Get-MacroRegime bu dosyayı best-effort okuyup DÜŞÜK GÜVENLİ (0.35) haber
olaylarını veri-türevli olaylara ekler.

DÜRÜSTLÜK: başlık sınıflandırması kabadır; bu yüzden güven düşük tutulur ve
rejim motoru haber olaylarını en fazla 4 adetle sınırlar. LLM yorumlama katmanı
ileride bu dosyanın üstüne (enrich deseniyle) eklenebilir; kural sınıflandırıcı
kalıcı fallback'tir. Kaynak erişilemezse exit 0 + log (akış bozulmaz).
"""
import hashlib, json, re, sys, time, urllib.request
from datetime import datetime, timezone
from xml.etree import ElementTree

OUT = "data/macro_news.json"
UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) BIST-Rapor-Botu/1.0"}
QUERIES = [
    "TCMB faiz karar%C4%B1",
    "T%C3%BCrkiye enflasyon TUIK",
    "T%C3%BCrkiye CDS risk primi",
    "dolar kuru TCMB rezerv",
    "brent petrol fiyat",
]
MAX_PER_QUERY = 8
MAX_AGE_HOURS = 48

# (eventType, direction, pattern) — pattern hem konu hem yön kelimesini arar.
# Yön kelimeleri Türkçe finans basınının standart fiil dağarcığından seçildi.
DOWN = r"(düştü|geriledi|azaldı|indi|beklentilerin altında|beklenenden düşük|yavaşladı|iyileşti)"
UP = r"(yükseldi|arttı|çıktı|beklentilerin üzerinde|beklenenden yüksek|hızlandı|sıçradı|bozuldu)"
RULES = [
    ("inflation", +1, rf"enflasyon[^.]*{DOWN}"),
    ("inflation", -1, rf"enflasyon[^.]*{UP}"),
    ("interest_rate", +1, r"faiz[^.]*(indirim|indirdi|düşürdü)"),
    ("interest_rate", -1, r"faiz[^.]*(artırım|artırdı|yükseltti|sıkılaş)"),
    ("central_bank_tone", +1, r"(TCMB|Merkez Bankası)[^.]*(güvercin|gevşeme sinyali|indirim sinyali)"),
    ("central_bank_tone", -1, r"(TCMB|Merkez Bankası)[^.]*(şahin|sıkı duruş|temkinli mesaj)"),
    ("cds_risk", +1, rf"(CDS|risk primi)[^.]*{DOWN}"),
    ("cds_risk", -1, rf"(CDS|risk primi)[^.]*{UP}"),
    ("fx_pressure", -1, rf"(dolar|kur)[^.]*(rekor|{UP})"),
    ("fx_pressure", +1, r"(rezerv)[^.]*(arttı|yükseldi|rekor)"),
    ("commodity_oil", -1, rf"(brent|petrol)[^.]*{UP}"),
    ("commodity_oil", +1, rf"(brent|petrol)[^.]*{DOWN}"),
    ("political_regulatory", -1, r"(yaptırım|soruşturma|vergi artışı|regülasyon şoku|not indirimi)"),
    ("political_regulatory", +1, r"(not artırımı|kredi notu[^.]*yükseltti)"),
]


def classify(title):
    """Başlığı ilk eşleşen kurala göre sınıflar; eşleşme yoksa None."""
    t = str(title or "").lower()
    for etype, direction, pattern in RULES:
        if re.search(pattern.lower(), t):
            return {"eventType": etype, "direction": direction, "confidence": 0.35}
    return None


def fetch_rss(query, timeout=20):
    url = f"https://news.google.com/rss/search?q={query}&hl=tr&gl=TR&ceid=TR:tr"
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        root = ElementTree.fromstring(r.read())
    out = []
    for item in root.iter("item"):
        title = (item.findtext("title") or "").strip()
        pub = (item.findtext("pubDate") or "").strip()
        src = item.find("source")
        out.append({"title": title, "pubDate": pub,
                    "source": (src.text.strip() if src is not None and src.text else "")})
        if len(out) >= MAX_PER_QUERY:
            break
    return out


def parse_pubdate(s):
    for fmt in ("%a, %d %b %Y %H:%M:%S %Z", "%a, %d %b %Y %H:%M:%S %z"):
        try:
            dt = datetime.strptime(s, fmt)
            return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    return None


def main():
    now = datetime.now(timezone.utc)
    items, seen, errs = [], set(), []
    for q in QUERIES:
        try:
            rows = fetch_rss(q)
        except Exception as e:
            errs.append(f"{q}: {type(e).__name__}: {e}")
            continue
        for r in rows:
            key = hashlib.sha1(r["title"].encode()).hexdigest()[:12]
            if key in seen:
                continue
            seen.add(key)
            dt = parse_pubdate(r["pubDate"])
            if dt is not None and (now - dt).total_seconds() > MAX_AGE_HOURS * 3600:
                continue
            cls = classify(r["title"])
            if cls is None:
                continue  # siniflanamayan basliklar yazilmaz (gurultu)
            items.append({"id": key, "title": r["title"], "source": r["source"],
                          "date": (dt or now).isoformat(), **cls})
        time.sleep(1)
    if errs:
        print("[uyari] erisilemeyen sorgular:", *errs, sep="\n  ", flush=True)
    if not items and errs and len(errs) == len(QUERIES):
        print("[sonuc] hicbir kaynak calismadi; dosya degistirilmedi.")
        return 0
    out = {"generatedAt": now.isoformat(),
           "source": "Google News RSS (TR) + kural tabanli siniflandirici",
           "note": "Baslik-kurali siniflandirmasi kabadir; rejim motoru bu olaylari dusuk guvenle ve sinirli sayida kullanir.",
           "count": len(items), "items": items}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print(f"[sonuc] {len(items)} siniflanmis makro haber -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
