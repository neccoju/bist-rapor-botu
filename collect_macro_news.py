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
import hashlib, json, re, sys, time, urllib.parse, urllib.request
from datetime import datetime, timezone
from xml.etree import ElementTree

OUT = "data/macro_news.json"
UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) BIST-Rapor-Botu/1.0"}
QUERIES = [
    "TCMB faiz kararı",
    "Türkiye enflasyon TÜİK",
    "Türkiye CDS risk primi",
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


def tr_lower(s):
    """Türkçe-güvenli küçültme: 'İ'.lower() Unicode'da 'i'+U+0307 (birleşen
    nokta) üretir ve 'indirim' desenini KIRAR; 'I' da 'ı' olmalı. Önce map,
    sonra lower."""
    return str(s or "").replace("İ", "i").replace("I", "ı").lower().replace("̇", "")


# Olumsuzlama kalıpları: yön fiili bu eklerle geliyorsa eşleşme İPTAL edilir
# ("düşmedi", "artmadı", "beklenmiyor", "değil"). Türkçe olumsuzluk ekleri.
NEGATION = re.compile(r"(medi|madı|müyor|mıyor|muyor|mıyacak|meyecek|"
                      r"beklenmiyor|değil|olmadı|edilmedi)\b")
# Tahmin/beklenti dili: bu başlıklarda YÖN, gerçekleşen değil revizyonun ima
# ettiği gelecek fiyat olabilir (EIA vakası). Kural motoru bunları elemez ama
# GÜVENİ düşürür; kesin yön kararı LLM'e/insana bırakılır.
FORECAST = re.compile(r"(tahmin|beklenti|öngör|hedef|projeksiyon|revize)")


def classify(title):
    """Başlığı ilk eşleşen kurala göre sınıflar; eşleşme yoksa None.
    Olumsuzlama içeren başlık ELENİR (yanlış yön riski); tahmin dili güveni düşürür."""
    t = tr_lower(title)
    if NEGATION.search(t):
        return None
    for etype, direction, pattern in RULES:
        if re.search(tr_lower(pattern), t):
            conf = 0.25 if FORECAST.search(t) else 0.35
            return {"eventType": etype, "direction": direction, "confidence": conf}
    return None


VALID_TYPES = {"inflation", "interest_rate", "central_bank_tone", "cds_risk",
               "fx_pressure", "foreign_flow", "global_risk", "commodity_oil",
               "political_regulatory"}


def parse_llm_reply(text, n_titles):
    """LLM yanıtını güvenle ayrıştırır: JSON dizisi [{i,type,direction}|null].
    Geçersiz tip/indeks/yön elenir (SAF — testlenebilir)."""
    try:
        m = re.search(r"\[.*\]", str(text), re.S)
        rows = json.loads(m.group(0)) if m else []
    except (ValueError, AttributeError):
        return {}
    out = {}
    for r in rows:
        if not isinstance(r, dict):
            continue
        i, t, d = r.get("i"), r.get("type"), r.get("direction")
        if (isinstance(i, int) and 0 <= i < n_titles and t in VALID_TYPES
                and d in (-1, 1)):
            out[i] = {"eventType": t, "direction": d, "confidence": 0.4}
    return out


def classify_with_llm(titles, timeout=30):
    """Kural-eşleşmeyen başlıkları GitHub Models ile sınıflar (OPSİYONEL katman).
    GITHUB_TOKEN yoksa/istek düşerse boş döner — kural motoru kalıcı fallback."""
    import os
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if not token or not titles:
        return {}
    numbered = "\n".join(f"{i}: {t}" for i, t in enumerate(titles))
    body = json.dumps({
        "model": "openai/gpt-4o-mini",
        "temperature": 0,
        "messages": [
            {"role": "system", "content":
             "Türkiye/BIST makro haber sınıflandırıcısısın. Her başlık için BIST etkisi yönünü değerlendir. "
             "YALNIZ JSON dizisi döndür: [{\"i\":<indeks>,\"type\":<tip>,\"direction\":1|-1}] — sınıflanamayanı dahil etme. "
             f"Geçerli tipler: {sorted(VALID_TYPES)}. direction=1 BIST için olumlu, -1 olumsuz. "
             "KURAL 1 (olumsuzlama): 'düşmedi/artmadı/beklenmiyor' gibi olumsuz başlıkta yönü TERSİNE çevir veya dahil etme. "
             "KURAL 2 (tahmin dili): Tahmin/beklenti revizyonlarında yön, GERÇEKLEŞEN fiyatı değil, revizyonun ima ettiği "
             "GELECEK fiyatı yansıtır. Örnek: 'EIA petrol fiyatı tahminini düşürdü' -> gelecekte petrol UCUZ -> Türkiye "
             "enflasyon/cari için OLUMLU -> commodity_oil direction=1 (gerçekleşen bir yükseliş DEĞİL). "
             "Örnek: 'Brent petrol bugün yükseldi' -> gerçekleşen yükseliş -> commodity_oil direction=-1."},
            {"role": "user", "content": numbered},
        ],
    }).encode()
    req = urllib.request.Request(
        "https://models.github.ai/inference/chat/completions", data=body,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json",
                 "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            resp = json.loads(r.read().decode("utf-8", "replace"))
        content = resp["choices"][0]["message"]["content"]
    except Exception as e:
        print(f"[uyari] LLM siniflandirma atlandi: {type(e).__name__}: {e}", flush=True)
        return {}
    return parse_llm_reply(content, len(titles))


def fetch_rss(query, timeout=20):
    q = urllib.parse.quote(query)   # bosluk/Turkce karakterler encode edilmeli (InvalidURL duzeltmesi)
    url = f"https://news.google.com/rss/search?q={q}&hl=tr&gl=TR&ceid=TR:tr"
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


def load_previous_items(now):
    """Önceki koşunun hâlâ taze (<MAX_AGE_HOURS) olayları korunur — sınıflanabilir
    haber çıkmayan bir koşu, dünün geçerli olaylarını boş dosyayla EZMESİN."""
    try:
        with open(OUT, encoding="utf-8") as f:
            old = json.load(f).get("items", [])
    except Exception:
        return []
    kept = []
    for it in old:
        try:
            dt = datetime.fromisoformat(str(it.get("date")))
        except (ValueError, TypeError):
            continue
        if (now - dt).total_seconds() <= MAX_AGE_HOURS * 3600:
            kept.append(it)
    return kept


def main():
    now = datetime.now(timezone.utc)
    items, seen, errs, unmatched = [], set(), [], []
    for it in load_previous_items(now):
        if it.get("id") not in seen:
            seen.add(it.get("id"))
            items.append(it)
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
                # Kurala uymayanlar LLM katmanina aday (opsiyonel ikinci gecis)
                unmatched.append({"id": key, "title": r["title"], "source": r["source"],
                                  "date": (dt or now).isoformat()})
                continue
            items.append({"id": key, "title": r["title"], "source": r["source"],
                          "date": (dt or now).isoformat(), "engine": "rule", **cls})
        time.sleep(1)
    if errs:
        print("[uyari] erisilemeyen sorgular:", *errs, sep="\n  ", flush=True)
    if errs and len(errs) == len(QUERIES):
        print("[sonuc] hicbir kaynak calismadi; dosya degistirilmedi (eski olaylar korunur).")
        return 0
    # LLM katmani (opsiyonel): kurala uymayan basliklardan en yeni 12'si.
    if unmatched:
        cand = unmatched[:12]
        llm = classify_with_llm([c["title"] for c in cand])
        for i, cls in llm.items():
            items.append({**cand[i], "engine": "llm", **cls})
        print(f"[bilgi] LLM katmani: {len(cand)} aday -> {len(llm)} siniflandi", flush=True)
    items.sort(key=lambda it: str(it.get("date", "")), reverse=True)
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
