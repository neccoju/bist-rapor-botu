#!/usr/bin/env python3
"""
probe_borsapy_kap.py — borsapy ile KAP erişimi FIZIBILITE testi.

Amac: borsapy gercekten KAP son bildirimlerini / bildirim takvimini cekebiliyor
mu, runner'da kac saniyede, headless tarayici (Chromium/patchright) gerekiyor mu
olcmek. Ana bota DOKUNMAZ; sadece introspection + olcum yapar, log'a basar.

API fonksiyon adlarini tahmin etmek yerine kutuphaneyi tarar (KAP/disclosure/
news/bildirim/calendar/earnings iceren isimleri kesfeder) ve cagirmayi dener.
"""
import sys
import time
import traceback


def short(obj, limit=1400):
    try:
        if hasattr(obj, "head") and hasattr(obj, "to_string"):  # pandas DataFrame
            return obj.head(3).to_string()[:limit]
        return str(obj)[:limit]
    except Exception as e:
        return f"<gosterilemedi: {e}>"


def describe(val):
    try:
        n = len(val) if hasattr(val, "__len__") else "?"
    except Exception:
        n = "?"
    return f"tip={type(val).__name__} uzunluk={n}"


def try_call(label, fn):
    """Bir cagiriyi sure + sonuc + hata ile dener, log'a basar."""
    t0 = time.time()
    try:
        val = fn()
        dt = time.time() - t0
        print(f"  [OK]  {label}  ({dt:.1f}s)  {describe(val)}")
        print("        ornek:")
        for line in short(val).splitlines()[:12]:
            print(f"        {line}")
        return True
    except Exception as e:
        dt = time.time() - t0
        print(f"  [HATA] {label}  ({dt:.1f}s)  {type(e).__name__}: {e}")
        # Chromium/patchright/scrapling izi var mi?
        msg = (str(e) + " " + traceback.format_exc()).lower()
        if any(k in msg for k in ("chromium", "patchright", "playwright", "scrapling", "browser")):
            print("        >> NOT: headless tarayici (Chromium) gerekiyor gibi gorunuyor.")
        return False


KAP_KEYS = ("kap", "disclos", "news", "bildirim", "calendar", "announc", "earning")

print("=" * 70)
print("borsapy KAP fizibilite testi")
print("=" * 70)

t_import = time.time()
try:
    import borsapy
except Exception as e:
    print(f"borsapy IMPORT HATASI: {e}")
    print("pip install borsapy basarisiz ya da bagimlilik eksik.")
    sys.exit(0)
print(f"borsapy import OK ({time.time() - t_import:.1f}s) | surum={getattr(borsapy, '__version__', '?')}")

# 1) Top-level KAP-ilgili isimler
top = [n for n in dir(borsapy) if not n.startswith('_')]
top_kap = [n for n in top if any(k in n.lower() for k in KAP_KEYS)]
print(f"\nTop-level KAP-ilgili isimler: {top_kap}")
print(f"Tum top-level isimler: {top}")

# 2) Top-level KAP fonksiyonlarini cagirmayi dene
for n in top_kap:
    obj = getattr(borsapy, n, None)
    if callable(obj):
        try_call(f"borsapy.{n}()", lambda obj=obj: obj())

# 3) Ticker uzerinden KAP/disclosure/earnings
SYM = "ASELS"
print(f"\n--- Ticker('{SYM}') uzerinden ---")
try:
    tk = borsapy.Ticker(SYM)
    attrs = [a for a in dir(tk) if not a.startswith('_')]
    kap_attrs = [a for a in attrs if any(k in a.lower() for k in KAP_KEYS)]
    print(f"Ticker KAP-ilgili attribute'lar: {kap_attrs}")
    print(f"Ticker tum attribute'lar: {attrs}")
    for a in kap_attrs:
        def getit(a=a, tk=tk):
            v = getattr(tk, a)
            return v() if callable(v) else v
        try_call(f"Ticker('{SYM}').{a}", getit)
except Exception as e:
    print(f"Ticker olusturulamadi: {type(e).__name__}: {e}")

# 4) CLI ipucu
print("\nNot: borsapy CLI de var (borsapy price/history/scan...). KAP icin "
      "Python API yukaridaki kesif sonucuna gore kullanilir.")
print("=" * 70)
print("Fizibilite testi tamam.")
