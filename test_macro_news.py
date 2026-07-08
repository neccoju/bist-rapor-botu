#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Agsiz birim testler: collect_macro_news.classify kural siniflandiricisi.
Workflow, collector'dan ONCE calistirir; kural bozulursa haber yazilmaz."""
import sys
from collect_macro_news import classify

CASES = [
    ("Haziran enflasyonu beklentilerin altında geriledi", "inflation", +1),
    ("Yıllık enflasyon beklenenden yüksek geldi", "inflation", -1),
    ("TCMB'den 250 baz puanlık faiz indirimi", "interest_rate", +1),
    ("Merkez Bankası faiz artırımına gitti, sıkılaşma sürüyor", "interest_rate", -1),
    ("Türkiye CDS risk primi 250'nin altına geriledi", "cds_risk", +1),
    ("Dolar kuru rekor tazeledi", "fx_pressure", -1),
    ("Brent petrol yükseldi, 90 doları aştı", "commodity_oil", -1),
    ("Moody's Türkiye'nin kredi notunu yükseltti", "political_regulatory", +1),
    ("TCMB'den Faiz İndirimi Sinyali Geldi", "interest_rate", +1),  # Turkce 'İ' casefold kilidi
    ("SIKILAŞMA SÜRÜYOR: faiz artırımı masada", "interest_rate", -1),  # buyuk-I/ı yolu
    ("Enflasyon beklenenden düşmedi, baskı sürüyor", None, None),  # olumsuzlama -> elenmeli
    ("Brent petrol bu hafta artmadı", None, None),  # olumsuzlama -> elenmeli
    ("Galatasaray derbisinde kritik sonuç", None, None),  # alakasiz -> None
]

fails = 0
for title, etype, direction in CASES:
    got = classify(title)
    if etype is None:
        ok = got is None
    else:
        ok = got is not None and got["eventType"] == etype and got["direction"] == direction
    status = "OK " if ok else "FAIL"
    if not ok:
        fails += 1
    print(f"{status} {title!r} -> {got}")

if fails:
    print(f"{fails} test FAIL")
    sys.exit(1)

# parse_llm_reply: gecerli/gecersiz LLM yanitlari guvenle ayristirilmali
from collect_macro_news import parse_llm_reply
good = parse_llm_reply('Sonuç: [{"i":0,"type":"inflation","direction":1},{"i":1,"type":"uydurma","direction":1},{"i":9,"type":"cds_risk","direction":-1},{"i":2,"type":"fx_pressure","direction":0}]', 3)
assert good == {0: {"eventType": "inflation", "direction": 1, "confidence": 0.4}}, good  # gecersiz tip/indeks/yon elendi
assert parse_llm_reply("bozuk cikti", 3) == {}
assert parse_llm_reply('[]', 3) == {}
print("parse_llm_reply testleri gecti (3)")

# Tahmin dili guveni dusurmeli (0.25), gerceklesen olay 0.35
from collect_macro_news import classify as _cls
fc = _cls("Brent petrol tahmini yükseldi")
assert fc is not None and abs(fc["confidence"] - 0.25) < 1e-9, fc
rl = _cls("Brent petrol bugün yükseldi")
assert rl is not None and abs(rl["confidence"] - 0.35) < 1e-9, rl
print("tahmin-dili guven testi gecti (2)")
print(f"tum testler gecti ({len(CASES)}+3)")
