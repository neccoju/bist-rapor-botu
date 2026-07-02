#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""collect_tefas.py — TEFAS hisse senedi fonu net akış toplayıcı (v2 API, probe + collect).

Amaç (Smart Money): yerli fon yatırımcısının hisse fonlarına net katılım/çıkışını
ölçmek. Eski /api/DB uçları kaldırıldı (404); 2025+ /api/funds JSON API kullanılır
(uç adları borsapy tefas sağlayıcısından doğrulandı):

  1) fonGetiriBazliBilgiGetir: TÜM fonlar tek POST (fonKodu, fonUnvan,
     fonTurAciklama, ...) -> 'Hisse Senedi' türü fonlar seçilir.
  2) fonBilgiGetir {fonKodu}: guncel sonFiyat + portBuyukluk (AUM) + yatirimciSayi.
     (Liste yanıtında AUM alanı varsa fon başına çağrı atlanır.)

v2 API pay adedi/AUM GEÇMİŞİ vermez; akış bu dosyanın kendi haftalık koşu
geçmişinden hesaplanır: akış ≈ AUM_şimdi − AUM_önce × (Fiyat_şimdi/Fiyat_önce)
— bu, Δ(pay adedi) × güncel fiyat ile matematiksel olarak özdeştir (fiyat
etkisiz). İlk koşu yalnız baz oluşturur (akış null).

Kaynak erişilemezse exit 0 + tanılayıcı log (akış bozulmaz, CI logu yol gösterir).

Çıktı: data/tefas_flows.json
{ generatedAt, asOf, note, equityFundCount, totalAumTL,
  flow1wTL|null, flow4wTL|null, baselineDate|null,
  topInflow[{code,name,flowTL}], topOutflow[...],
  history: [{date, funds:{KOD:{a(um),p(fiyat)}}}, ...]  # son 6 koşu }
"""
import json, sys, time, urllib.request
from datetime import date, datetime, timezone

OUT = "data/tefas_flows.json"
BASE = "https://www.tefas.gov.tr/api/funds"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36",
    "Accept": "application/json",
    "Content-Type": "application/json",
    "Origin": "https://www.tefas.gov.tr",
    "Referer": "https://www.tefas.gov.tr/FonKarsilastirma.aspx",
}
HISTORY_KEEP = 6
AUM_KEYS = ("portBuyukluk", "portfoyBuyukluk", "fonBuyukluk", "portfoyDegeri")
PRICE_KEYS = ("sonFiyat", "fiyat", "birimPayDegeri")


def post_v2(path, payload, timeout=40, retries=3):
    last = None
    for attempt in range(retries):
        if attempt: time.sleep(0.5 * (2 ** (attempt - 1)))
        try:
            req = urllib.request.Request(f"{BASE}/{path}", data=json.dumps(payload).encode(),
                                         headers=HEADERS)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                body = r.read().decode("utf-8", "replace")
            d = json.loads(body)
        except Exception as e:
            last = e; continue
        if isinstance(d, dict):
            if d.get("errorMessage"):
                raise RuntimeError(f"{path} hata: {d['errorMessage']}")
            return d.get("resultList") or []
        return d if isinstance(d, list) else []
    raise RuntimeError(f"{path} {retries} denemede alinamadi: {type(last).__name__}: {last}")


def to_float(v):
    if v is None: return None
    try:
        return float(str(v).replace(",", "."))
    except ValueError:
        return None


def pick(row, keys):
    for k in keys:
        v = to_float(row.get(k))
        if v is not None: return v
    return None


def equity_funds():
    rows = post_v2("fonGetiriBazliBilgiGetir", {
        "fonTipi": "YAT", "dil": "TR", "calismaTipi": 2,
        "donemGetiri1a": "1", "donemGetiri3a": "1", "donemGetiri6a": "1",
        "donemGetiriyb": "1", "donemGetiri1y": "1", "donemGetiri3y": "1",
        "donemGetiri5y": "1"})
    if not rows:
        raise RuntimeError("fonGetiriBazliBilgiGetir bos dondu")
    print(f"[bilgi] toplam fon: {len(rows)}; ilk satir alanlari: {sorted(rows[0].keys())}", flush=True)
    eq = {}
    for r in rows:
        tur = str(r.get("fonTurAciklama") or "").upper().replace("HISSE", "HİSSE")
        kod = str(r.get("fonKodu") or "").strip().upper()
        if kod and "HİSSE" in tur and "SERBEST" not in tur:
            eq[kod] = {"name": str(r.get("fonUnvan") or ""),
                       "aum": pick(r, AUM_KEYS), "price": pick(r, PRICE_KEYS)}
    if not eq:
        raise RuntimeError(f"hisse fonu bulunamadi; ornek satir: {str(rows[0])[:400]}")
    return eq


def fill_details(eq):
    """Liste yanitinda AUM/fiyat yoksa fon basina fonBilgiGetir cek."""
    missing = [k for k, v in eq.items() if v["aum"] is None or v["price"] is None]
    if not missing:
        print("[bilgi] AUM/fiyat liste yanitindan geldi; fon basina cagri gerekmedi.", flush=True)
        return
    print(f"[bilgi] {len(missing)} fon icin fonBilgiGetir cekiliyor...", flush=True)
    for i, kod in enumerate(missing):
        try:
            rows = post_v2("fonBilgiGetir", {"fonKodu": kod}, timeout=25, retries=2)
            if rows:
                eq[kod]["aum"] = pick(rows[0], AUM_KEYS)
                eq[kod]["price"] = pick(rows[0], PRICE_KEYS)
                if i == 0:
                    print(f"[bilgi] fonBilgiGetir ilk satir alanlari: {sorted(rows[0].keys())}", flush=True)
        except Exception as e:
            print(f"[uyari] {kod} detay alinamadi: {e}", flush=True)
        time.sleep(0.25)


def flow_vs(funds_now, funds_prev):
    """akis = AUM_simdi - AUM_once * (P_simdi/P_once)  (== Δpay × guncel fiyat)."""
    per = {}
    for kod, cur in funds_now.items():
        prev = funds_prev.get(kod)
        if not prev: continue
        a1, p1 = cur.get("a"), cur.get("p")
        a0, p0 = prev.get("a"), prev.get("p")
        if None in (a1, p1, a0, p0) or p0 == 0: continue
        per[kod] = a1 - a0 * (p1 / p0)
    return per


def main():
    prev_hist = []
    try:
        with open(OUT, encoding="utf-8") as f:
            prev_hist = json.load(f).get("history") or []
    except Exception:
        pass
    try:
        eq = equity_funds()
        fill_details(eq)
    except Exception as e:
        print(f"[probe] tefas basarisiz -> {type(e).__name__}: {e}", flush=True)
        print("[sonuc] kaynak calismadi; dosya degistirilmedi.")
        return 0

    today = date.today().isoformat()
    snap = {k: {"a": v["aum"], "p": v["price"]} for k, v in eq.items()
            if v["aum"] is not None and v["price"] is not None}
    if not snap:
        print("[probe] hicbir fonda AUM+fiyat cifti yok; dosya degistirilmedi.")
        return 0

    history = [h for h in prev_hist if h.get("date") != today]
    history.append({"date": today, "funds": snap})
    history = sorted(history, key=lambda h: h["date"])[-HISTORY_KEEP:]

    def nearest(days_min):
        cands = [h for h in history[:-1]
                 if (date.fromisoformat(today) - date.fromisoformat(h["date"])).days >= days_min]
        return cands[-1] if cands else None

    base1w, base4w = nearest(4), nearest(21)
    f1w = flow_vs(snap, base1w["funds"]) if base1w else {}
    f4w = flow_vs(snap, base4w["funds"]) if base4w else {}
    ranked = sorted(f1w.items(), key=lambda kv: kv[1], reverse=True)
    out = {"generatedAt": datetime.now(timezone.utc).isoformat(),
           "asOf": today,
           "note": "TEFAS hisse senedi fonlari; net akis = AUM degisiminden fiyat etkisi arindirilmis (Δpay × guncel fiyat esdegeri). Haftalik koşu bazi.",
           "equityFundCount": len(snap),
           "totalAumTL": round(sum(v["a"] for v in snap.values())),
           "flow1wTL": round(sum(f1w.values())) if f1w else None,
           "flow4wTL": round(sum(f4w.values())) if f4w else None,
           "baselineDate": base1w["date"] if base1w else None,
           "topInflow": [{"code": k, "name": eq[k]["name"], "flowTL": round(v)} for k, v in ranked[:5] if v > 0],
           "topOutflow": [{"code": k, "name": eq[k]["name"], "flowTL": round(v)} for k, v in ranked[::-1][:5] if v < 0],
           "history": history}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    msg = f"1H akis {out['flow1wTL']:,} TL" if out["flow1wTL"] is not None else "ilk kosu: baz olusturuldu"
    print(f"[sonuc] {len(snap)} hisse fonu; {msg} -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
