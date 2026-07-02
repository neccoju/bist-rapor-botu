#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""collect_tefas.py — TEFAS hisse senedi fonu net akış toplayıcı (probe + collect).

Amaç (Smart Money): yerli kurumsal/bireysel fon akışını ölçmek. TEFAS'ın
TarihselVeriler ekranının XHR'ları kullanılır (tefas-crawler ile aynı uçlar):

  1) BindComparisonFundReturns: tüm fonların tür açıklaması (FONTURACIKLAMA)
     -> 'Hisse Senedi' içeren fon kodları seçilir (tek POST).
  2) BindHistoryInfo: bir günün TÜM fon kayıtları (fiyat, tedavüldeki pay
     sayısı, portföy büyüklüğü) — son iş günü, ~1 hafta ve ~4 hafta öncesi.

Net akış = Δ(tedavüldeki pay sayısı) × güncel fiyat — FIYAT ETKISIZ gerçek
katılım/çıkış ölçüsüdür (AUM değişimi fiyatla şişer, o kullanılmaz).

Dürüstlük: TEFAS 1-2 iş günü gecikmeli yayınlar; asOf dosyaya yazılır.
Kaynak erişilemezse exit 0 + tanılayıcı log (akış bozulmaz, CI logu yol gösterir).

Çıktı: data/tefas_flows.json
{ generatedAt, asOf, prevWeekDate, prevMonthDate, equityFundCount,
  totalAumTL, flow1wTL, flow4wTL, topInflow[{code,name,flowTL}], topOutflow[...] }
"""
import json, sys, time, urllib.parse, urllib.request
from datetime import date, datetime, timedelta, timezone

OUT = "data/tefas_flows.json"
BASE = "https://www.tefas.gov.tr"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36",
    "Accept": "application/json, text/javascript, */*; q=0.01",
    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
    "X-Requested-With": "XMLHttpRequest",
    "Origin": BASE,
    "Referer": f"{BASE}/TarihselVeriler.aspx",
}


def post_form(path, form, timeout=40):
    req = urllib.request.Request(BASE + path, data=urllib.parse.urlencode(form).encode(),
                                 headers=HEADERS)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = r.read().decode("utf-8", "replace")
    try:
        return json.loads(body)
    except ValueError:
        raise RuntimeError(f"{path} JSON degil (WAF?); ilk 200: {body[:200]}")


def to_float(v):
    if v is None: return None
    s = str(v).strip()
    if not s: return None
    try:
        return float(s)
    except ValueError:
        try:
            return float(s.replace(".", "").replace(",", "."))  # 1.234,56 -> 1234.56
        except ValueError:
            return None


def equity_fund_codes():
    """FONTURACIKLAMA'sinda 'Hisse Senedi' gecen YAT fonlarinin kodlari."""
    d = post_form("/api/DB/BindComparisonFundReturns", {
        "calismatipi": "2", "fontip": "YAT", "sfontur": "", "kurucukod": "",
        "fongrup": "", "bastarih": "Başlangıç", "bittarih": "Bitiş",
        "fonturkod": "", "fonunvantip": "", "strperiod": "1,1,1,1,1,1,1",
        "islemdurum": "1"})
    rows = d.get("data") if isinstance(d, dict) else d
    if not rows:
        raise RuntimeError(f"BindComparisonFundReturns bos; yanit: {str(d)[:300]}")
    codes = {}
    for r in rows:
        tur = str(r.get("FONTURACIKLAMA") or "")
        kod = str(r.get("FONKODU") or "").strip().upper()
        if kod and "HİSSE" in tur.upper().replace("HISSE", "HİSSE"):
            codes[kod] = str(r.get("FONUNVAN") or "")
    if not codes:
        raise RuntimeError(f"hisse fonu bulunamadi; ornek satir: {str(rows[0])[:400]}")
    return codes


def day_snapshot(target, max_back=6):
    """target gununden geriye dogru ilk dolu gunun {kod:(fiyat,pay)} haritasi."""
    for back in range(max_back + 1):
        day = target - timedelta(days=back)
        if day.weekday() >= 5:  # hafta sonu
            continue
        ds = day.strftime("%d.%m.%Y")
        d = post_form("/api/DB/BindHistoryInfo", {
            "fontip": "YAT", "sfontur": "", "fonkod": "", "fongrup": "",
            "bastarih": ds, "bittarih": ds, "fonturkod": "", "fonunvantip": "",
            "kurucukod": ""})
        rows = d.get("data") if isinstance(d, dict) else None
        if rows:
            snap = {}
            for r in rows:
                kod = str(r.get("FONKODU") or "").strip().upper()
                fiyat = to_float(r.get("FIYAT"))
                pay = to_float(r.get("TEDPAYSAYISI"))
                aum = to_float(r.get("PORTFOYBUYUKLUK"))
                if kod and fiyat is not None and pay is not None:
                    snap[kod] = (fiyat, pay, aum)
            if snap:
                return day, snap
            print(f"[probe] {ds}: satir var ama parse 0; ornek: {str(rows[0])[:300]}", flush=True)
        time.sleep(1)
    raise RuntimeError(f"{target} civarinda dolu gun yok ({max_back} gun geriye bakildi)")


def main():
    try:
        eq = equity_fund_codes()
        print(f"[bilgi] hisse fonu sayisi: {len(eq)}", flush=True)
        today = date.today()
        as_of, now = day_snapshot(today)
        wk_date, wk = day_snapshot(as_of - timedelta(days=7))
        mo_date, mo = day_snapshot(as_of - timedelta(days=28))
    except Exception as e:
        print(f"[probe] tefas basarisiz -> {type(e).__name__}: {e}", flush=True)
        print("[sonuc] kaynak calismadi; dosya degistirilmedi.")
        return 0

    def flows(prev):
        out = {}
        for kod in eq:
            a, b = now.get(kod), prev.get(kod)
            if a and b:
                out[kod] = (a[1] - b[1]) * a[0]  # Δpay × güncel fiyat (TL)
        return out

    f1w, f4w = flows(wk), flows(mo)
    total_aum = sum(v[2] for k, v in now.items() if k in eq and v[2] is not None)
    ranked = sorted(f1w.items(), key=lambda kv: kv[1], reverse=True)
    top_in = [{"code": k, "name": eq[k], "flowTL": round(v)} for k, v in ranked[:5] if v > 0]
    top_out = [{"code": k, "name": eq[k], "flowTL": round(v)} for k, v in ranked[::-1][:5] if v < 0]
    out = {"generatedAt": datetime.now(timezone.utc).isoformat(),
           "asOf": as_of.isoformat(), "prevWeekDate": wk_date.isoformat(),
           "prevMonthDate": mo_date.isoformat(),
           "note": "TEFAS hisse senedi fonlari; net akis = pay adedi degisimi x guncel fiyat (fiyat etkisiz). Yayin 1-2 is gunu gecikmeli.",
           "equityFundCount": len(eq),
           "totalAumTL": round(total_aum),
           "flow1wTL": round(sum(f1w.values())),
           "flow4wTL": round(sum(f4w.values())),
           "topInflow": top_in, "topOutflow": top_out}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print(f"[sonuc] {len(eq)} hisse fonu; 1H akis {out['flow1wTL']:,} TL; 4H {out['flow4wTL']:,} TL -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
