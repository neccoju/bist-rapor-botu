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
print(f"tum testler gecti ({len(CASES)})")
