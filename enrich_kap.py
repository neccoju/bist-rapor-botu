#!/usr/bin/env python3
"""
enrich_kap.py — KAP bildirim ICERIK yorumlama katmani (gozlem modu).

collect_kap.py yalniz BASLIK siniflandirir; bu script secili (onemli + son N gun)
bildirimlerin GOVDE metnini borsapy `Ticker(sym).get_news_content(disclosureId)`
ile ceker, kural-tabanli yorumlar (rakam cikarimi + sentiment ile yon netlestirme
+ kisa ozet) ve sonucu AYRI bir dosyaya (data/kap_enrichment.json) yazar. Boylece
collector'in kap_disclosures.json'i ile yazma yarisi olmaz; rapor iki dosyayi
disclosureId ile birlestirir. Karar etkisi YOK.

Ilk kosuda kendini-probe eder: ilk birkac bildirim icin ham icerigin tipini/
ornegini loglar; get_news_content yoksa Ticker metodlarini kesfedip dener.

Dayaniklilik: hisse/istek basina try, sure limiti, throttle'a karsi bekleme,
zaten yorumlanmis (disclosureId enrichment'ta var) kayitlari atlar (idempotent).
"""
import argparse
import html
import json
import os
import re
import sys
import time
from datetime import datetime, timezone


# --- Turkce-guvenli kucuk harf (collect_kap._norm ile ayni mantik) ---
def _norm(s: str) -> str:
    s = (s or "").replace("İ", "i").replace("I", "ı")
    return s.lower().replace("̇", "")


def _parse_date(s):
    s = str(s or "").strip()
    for fmt in ("%d.%m.%Y %H:%M:%S", "%d.%m.%Y %H:%M", "%d.%m.%Y",
                "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(s[:len(fmt) + 2], fmt)
        except Exception:
            continue
    return None


def load_priority_symbols(data_dir):
    """Botun state dosyalarindan IZLENEN (oncelikli) hisseleri okur: Top picks +
    model portfoy + anlik giris holdingleri. Token tasarrufu icin LLM yalniz bu
    hisselerin son-gun bildirimlerini yorumlar (rapor da bunlari gosterir).
    Best-effort; dosya yoksa bos kume."""
    syms = set()

    def _load(path):
        with open(path, "r", encoding="utf-8-sig") as f:
            return json.load(f)

    def add(s):
        if s:
            c = re.sub(r"[^A-Z0-9]", "", str(s).strip().upper())
            if 2 <= len(c) <= 6:
                syms.add(c)

    try:
        d = _load(os.path.join(data_dir, "signal_performance.json"))
        for p in ((d.get("PendingPicks") or {}).get("Picks") or []):
            if isinstance(p, dict):
                add(p.get("Symbol"))
    except Exception:
        pass
    try:
        d = _load(os.path.join(data_dir, "model_portfolios.json"))
        for p in (d.get("Portfolios") or []):
            for h in (p.get("Holdings") or []):
                if isinstance(h, dict):
                    add(h.get("Symbol"))
    except Exception:
        pass
    try:
        d = _load(os.path.join(data_dir, "instant_entry_portfolio.json"))
        for h in (d.get("Holdings") or []):
            if isinstance(h, dict):
                add(h.get("Symbol"))
    except Exception:
        pass
    return syms


# --- Sentiment / yon ipucu sozlukleri (normalize edilmis koklerle) ---
POS_HINTS = [
    "imzalan", "imzalad", "kazanıl", "kazandı", "sipariş al", "ihaleyi", "ihale kazan",
    "sözleşme imzal", "anlaşma sağlan", "yeni iş ilişk", "satın alın", "iştirak edin",
    "kapasite artır", "yeni tesis", "yatırım karar", "teşvik", "hibe", "rekor",
    "artış", "arttı", "yükseliş", "olumlu", "onaylan", "tamamlan", "geri alım",
    "kar payı dağıt", "kâr payı dağıt", "temettü dağıt", "nakit kar", "bedelsiz",
]
NEG_HINTS = [
    "dava açıl", "davaya", "fesih", "feshed", "iptal", "olumsuz", "azalış", "azaldı",
    "zarar", "iflas", "konkordato", "durdur", "ceza", "el konul", "haciz",
    "temerrüt", "tahsil edilemey", "gerileme", "kapatıl", "soruşturma", "yaptırım",
]


def to_text(content) -> str:
    """Donen icerigi (str/dict/DataFrame/diger) duz metne cevirir; HTML temizler."""
    if content is None:
        return ""
    if isinstance(content, str):
        s = content
    elif isinstance(content, dict):
        s = " ".join(str(v) for v in content.values())
    elif hasattr(content, "to_string"):
        try:
            s = content.to_string()
        except Exception:
            s = str(content)
    else:
        s = str(content)
    s = re.sub(r"<[^>]+>", " ", s)        # HTML etiketleri
    s = html.unescape(s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


_MONEY_RE = re.compile(
    r"([0-9][0-9.\s]*(?:,[0-9]+)?)\s*(milyar|milyon|bin)?\s*"
    r"(TL|TRY|ABD\s*Dolar|USD|Euro|EUR|\$|€)",
    re.IGNORECASE,
)


def extract_amounts(text, limit=5):
    out = []
    for m in _MONEY_RE.finditer(text):
        num = m.group(1).strip().rstrip(".").strip()
        scale = (m.group(2) or "").strip()
        cur = m.group(3).strip()
        piece = " ".join(x for x in (num, scale, cur) if x)
        if piece and piece not in out:
            out.append(piece)
        if len(out) >= limit:
            break
    return out


def refine_direction(text, base_dir):
    t = _norm(text)
    pos = sum(1 for k in POS_HINTS if k in t)
    neg = sum(1 for k in NEG_HINTS if k in t)
    if pos > neg and pos > 0:
        return "+", pos, neg
    if neg > pos and neg > 0:
        return "-", pos, neg
    return (base_dir or "?"), pos, neg


def make_summary(text, max_len=240):
    """Anahtar kelime + sayi iceren cumleleri one alarak 1-2 cumlelik ozet."""
    if not text:
        return ""
    sentences = re.split(r"(?<=[.!?])\s+", text)
    scored = []
    for s in sentences:
        s = s.strip()
        if len(s) < 15:
            continue
        ns = _norm(s)
        score = sum(1 for k in (POS_HINTS + NEG_HINTS) if k in ns)
        if re.search(r"\d", s):
            score += 1
        scored.append((score, s))
    scored.sort(key=lambda x: -x[0])
    picked = [s for sc, s in scored[:2] if sc > 0]
    if not picked:
        picked = [text[:max_len]]
    summary = " ".join(picked)
    if len(summary) > max_len:
        summary = summary[:max_len].rsplit(" ", 1)[0] + "…"
    return summary


LLM_PROMPT = (
    "Sen BIST KAP bildirimlerini yorumlayan bir analistsin. Aşağıdaki ham metin bir "
    "KAP bildirim sayfasının içeriğidir; BAŞINDA/ARASINDA KAP site menüsü, arama "
    "arayüzü, kategori listeleri ('Tüm Kategoriler', 'detaylı sorgulama', 'Sık "
    "Arananlar' vb.) olabilir — bunları TAMAMEN YOKSAY ve yalnızca şirketin ASIL "
    "açıklamasına odaklan. Yatırımcı gözüyle değerlendir.\n\n"
    "Hisse: {sym}\nBaşlık: {title}\nKategori (ön-sınıf): {cat}\n\n"
    "Ham içerik:\n\"\"\"\n{body}\n\"\"\"\n\n"
    "SADECE şu JSON'u döndür (başka hiçbir metin yok):\n"
    "{{\"summary\": \"Türkçe, en fazla 220 karakter, yatırımcıya net ve somut özet "
    "(rakam/taraf/konu)\", \"direction\": \"+|-|~|0|?\" (fiyata olası etki yönü; + "
    "olumlu, - olumsuz, ~ karışık, 0 nötr, ? belirsiz), \"impact\": 1-5 (1 önemsiz, "
    "5 çok önemli fiyat etkisi), \"amounts\": [\"en fazla 5 önemli tutar, örn '1,25 "
    "milyar TL'\"], \"rationale\": \"en fazla 120 karakter gerekçe\"}}"
)


def _parse_llm_json(raw, usage=None):
    """Model ciktisindaki JSON'u ayikla + normalize et (ortak)."""
    m = re.search(r"\{.*\}", raw or "", re.DOTALL)
    if not m:
        raise ValueError(f"LLM JSON dondurmedi: {str(raw)[:120]}")
    obj = json.loads(m.group(0))
    direction = str(obj.get("direction", "?")).strip()[:1] or "?"
    if direction not in "+-~0?":
        direction = "?"
    amounts = obj.get("amounts") or []
    if not isinstance(amounts, list):
        amounts = [str(amounts)]
    return {
        "summary": str(obj.get("summary", "")).strip()[:240],
        "direction": direction,
        "impact": obj.get("impact"),
        "amounts": [str(a)[:40] for a in amounts][:5],
        "rationale": str(obj.get("rationale", "")).strip()[:140],
        "usage": usage or {},
    }


def interpret_llm(client, model, sym, title, cat, text, max_chars):
    """Claude (anthropic) ile içerik yorumu."""
    prompt = LLM_PROMPT.format(sym=sym, title=title, cat=cat, body=text[:max_chars])
    msg = client.messages.create(
        model=model, max_tokens=500,
        messages=[{"role": "user", "content": prompt}],
    )
    raw = "".join(getattr(b, "text", "") for b in msg.content).strip()
    return _parse_llm_json(raw, {"in": getattr(msg.usage, "input_tokens", None),
                                 "out": getattr(msg.usage, "output_tokens", None)})


def interpret_openai_compatible(base_url, token, model, sym, title, cat, text, max_chars):
    """OpenAI-uyumlu endpoint (GitHub Models) ile içerik yorumu. Ek bagimlilik yok
    (urllib). GitHub Models: ucretsiz, Actions GITHUB_TOKEN ile (models: read)."""
    import urllib.request
    prompt = LLM_PROMPT.format(sym=sym, title=title, cat=cat, body=text[:max_chars])
    payload = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.2,
        "max_tokens": 500,
    }).encode("utf-8")
    req = urllib.request.Request(base_url, data=payload, method="POST", headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    })
    with urllib.request.urlopen(req, timeout=90) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    raw = (data["choices"][0]["message"]["content"] or "").strip()
    u = data.get("usage", {}) or {}
    return _parse_llm_json(raw, {"in": u.get("prompt_tokens"), "out": u.get("completion_tokens")})


def fetch_content(borsapy, sym, did, log=False):
    """borsapy ile bir bildirimin govdesini ceker. Once get_news_content; yoksa
    Ticker uzerinde icerik/detay metodlarini kesfedip dener. (sym, did) ister."""
    tk = borsapy.Ticker(sym)
    candidates = ["get_news_content", "news_content", "get_disclosure",
                  "disclosure_content", "get_news_detail", "news_detail"]
    if log:
        methods = [m for m in dir(tk) if not m.startswith("_")]
        hit = [m for m in methods if any(k in m.lower()
               for k in ("content", "detail", "disclosure", "icerik", "detay"))]
        print(f"    [probe] {sym} Ticker icerik-metodlari: {hit}")
    last_err = None
    for name in candidates:
        fn = getattr(tk, name, None)
        if not callable(fn):
            continue
        try:
            return fn(did), name
        except TypeError:
            # bazi imzalar argumansiz olabilir
            try:
                return fn(), name
            except Exception as e:
                last_err = e
        except Exception as e:
            last_err = e
    if last_err:
        raise last_err
    raise RuntimeError("icerik metodu bulunamadi")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", default="data/kap_disclosures.json")
    ap.add_argument("--out", default="data/kap_enrichment.json")
    ap.add_argument("--max-age-days", type=int, default=1, help="kac gun geriye (son gun = 1)")
    ap.add_argument("--max-items", type=int, default=25, help="bu kosuda en fazla yorumlanacak bildirim (token siniri)")
    ap.add_argument("--importance", default="high", help="virgulle: hangi onem seviyeleri (or. high,insider)")
    ap.add_argument("--max-seconds", type=int, default=400)
    ap.add_argument("--sleep", type=float, default=0.5)
    ap.add_argument("--retries", type=int, default=2)
    ap.add_argument("--retry-wait", type=float, default=4.0)
    ap.add_argument("--engine", default="github", choices=["github", "llm", "rules"],
                    help="yorumlama motoru: github (GitHub Models, UCRETSIZ, GITHUB_TOKEN) | "
                         "llm (Claude API, ANTHROPIC_API_KEY) | rules (anahtar kelime)")
    ap.add_argument("--model", default="",
                    help="model id. Bos ise: github->openai/gpt-4o-mini, llm->claude-haiku-4-5-20251001")
    ap.add_argument("--base-url", default="https://models.github.ai/inference/chat/completions",
                    help="github motoru icin OpenAI-uyumlu inference endpoint")
    ap.add_argument("--max-content-chars", type=int, default=60000,
                    help="LLM'e gonderilecek en fazla icerik karakteri (maliyet siniri)")
    ap.add_argument("--force", action="store_true",
                    help="ayni motorla zaten yorumlanmis kayitlari da yeniden yorumla")
    ap.add_argument("--priority-only", dest="priority_only", action="store_true", default=True,
                    help="yalniz izlenen (Top/portfoy/anlik giris) hisselerin bildirimlerini yorumla (token tasarrufu)")
    ap.add_argument("--all-stocks", dest="priority_only", action="store_false",
                    help="tum hisseleri yorumla (oncelik filtresi kapali)")
    args = ap.parse_args()

    started = time.time()
    print("=" * 70)
    print("KAP icerik yorumlama (enrich)")
    print("=" * 70)
    try:
        import borsapy
    except Exception as e:
        print(f"borsapy import HATASI: {e}")
        sys.exit(1)
    print(f"borsapy {getattr(borsapy, '__version__', '?')}")

    if not os.path.exists(args.inp):
        print(f"Girdi yok: {args.inp}; cikiliyor.")
        sys.exit(0)
    with open(args.inp, "r", encoding="utf-8") as f:
        data = json.load(f)
    stocks = data.get("stocks", {})

    # Mevcut enrichment (idempotent: zaten yorumlanmislari atla).
    enrich = {"items": {}}
    if os.path.exists(args.out):
        try:
            with open(args.out, "r", encoding="utf-8") as f:
                enrich = json.load(f)
        except Exception:
            enrich = {"items": {}}
    items = enrich.get("items", {})

    # Motor kurulumu.
    llm_client = None
    gh_token = None
    model = args.model
    if args.engine == "github":
        gh_token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
        if not gh_token:
            print("!! GITHUB_TOKEN yok; GitHub Models yorumlama atlandi. Cikiliyor (akis bozulmaz).")
            sys.exit(0)
        if not model:
            model = "openai/gpt-4o-mini"
        print(f"Motor: GitHub Models (ucretsiz) / {model} @ {args.base_url}")
    elif args.engine == "llm":
        if not os.environ.get("ANTHROPIC_API_KEY"):
            print("!! ANTHROPIC_API_KEY yok; LLM yorumlama atlandi. Cikiliyor (akis bozulmaz).")
            sys.exit(0)
        try:
            import anthropic
            llm_client = anthropic.Anthropic()
        except Exception as e:
            print(f"!! anthropic istemcisi kurulamadi ({type(e).__name__}: {e}); cikiliyor.")
            sys.exit(0)
        if not model:
            model = "claude-haiku-4-5-20251001"
        print(f"Motor: anthropic / {model}")

    want_imp = set(x.strip() for x in args.importance.split(",") if x.strip())
    cutoff = datetime.now().replace(tzinfo=None)
    cutoff = cutoff.fromordinal(cutoff.toordinal() - args.max_age_days)

    # Izlenen hisseler (token tasarrufu + rapora gosterilenlerle ortusur).
    data_dir = os.path.dirname(args.inp) or "."
    priority = load_priority_symbols(data_dir) if args.priority_only else set()
    if args.priority_only and not priority:
        print("UYARI: oncelikli hisse listesi bos (state dosyalari yok); tum hisseler yorumlanacak.")

    # Hedefleri sec: onemli + son N gun + disclosureId var + henuz yorumlanmamis
    # (+ priority_only ise yalniz izlenen hisseler).
    targets = []
    for sym, rows in stocks.items():
        if priority and sym.upper() not in priority:
            continue
        for r in (rows or []):
            did = r.get("disclosureId")
            if not did:
                continue
            # Idempotent: ayni motorla zaten yorumlanmissa atla (--force haric).
            if not args.force and did in items and items[did].get("engine") == args.engine:
                continue
            if r.get("importance") not in want_imp:
                continue
            dt = _parse_date(r.get("date"))
            if dt is None or dt < cutoff:
                continue
            targets.append((sym, did, r, dt))
    targets.sort(key=lambda x: x[3], reverse=True)   # yeni -> eski
    targets = targets[: args.max_items]
    print(f"Hedef bildirim: {len(targets)} (motor={args.engine}, onem={sorted(want_imp)}, "
          f"son {args.max_age_days} gun, izlenen-hisse={'acik (%d)'%len(priority) if priority else 'kapali'}, "
          f"arsivde {len(items)} kayit, force={args.force})")

    done = 0
    errors = 0
    for i, (sym, did, r, dt) in enumerate(targets, 1):
        if time.time() - started > args.max_seconds:
            print(f"!! Sure limiti; {i-1}/{len(targets)} sonrasi durduruldu.")
            break
        content = None
        last_err = None
        for attempt in range(1, args.retries + 1):
            try:
                content, used = fetch_content(borsapy, sym, did, log=(i <= 3))
                last_err = None
                break
            except Exception as e:
                last_err = e
                if attempt < args.retries:
                    time.sleep(args.retry_wait * attempt)
        if last_err is not None:
            errors += 1
            if errors <= 8:
                print(f"  {sym}/{did}: ICERIK HATA {type(last_err).__name__}: {last_err}")
            time.sleep(args.sleep)
            continue

        text = to_text(content)
        if i <= 3:
            print(f"    [probe] {sym}/{did} icerik tip={type(content).__name__} "
                  f"uzunluk={len(text)} ornek={text[:160]!r}")

        rec = {
            "symbol": sym,
            "title": r.get("title"),
            "category": r.get("category"),
            "date": r.get("date"),
            "directionHint": r.get("direction"),
            "contentChars": len(text),
            "engine": args.engine,
            "enrichedAt": datetime.now(timezone.utc).isoformat(),
        }

        if args.engine in ("github", "llm"):
            try:
                if args.engine == "github":
                    res = interpret_openai_compatible(args.base_url, gh_token, model, sym,
                                                      r.get("title", ""), r.get("category", ""),
                                                      text, args.max_content_chars)
                else:
                    res = interpret_llm(llm_client, model, sym, r.get("title", ""),
                                        r.get("category", ""), text, args.max_content_chars)
            except Exception as e:
                errors += 1
                if errors <= 8:
                    print(f"  {sym}/{did}: {args.engine.upper()} HATA {type(e).__name__}: {e}")
                time.sleep(args.sleep)
                continue
            rec.update({
                "directionRefined": res["direction"],
                "summary": res["summary"],
                "impact": res.get("impact"),
                "amounts": res.get("amounts", []),
                "rationale": res.get("rationale", ""),
            })
            direction = res["direction"]
            summary = res["summary"]
        else:
            amounts = extract_amounts(text)
            direction, pos, neg = refine_direction(text, r.get("direction"))
            summary = make_summary(text)
            rec.update({
                "directionRefined": direction,
                "summary": summary,
                "sentiment": {"pos": pos, "neg": neg},
                "amounts": amounts,
            })

        items[did] = rec
        done += 1
        if done <= 12:
            imp = rec.get("impact")
            print(f"  + {sym} [{r.get('category')}] {direction}"
                  f"{(' etki=' + str(imp)) if imp is not None else ''} | {summary[:90]}")
        time.sleep(args.sleep)

    enrich = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": f"borsapy {getattr(borsapy, '__version__', '?')} get_news_content",
        "count": len(items),
        "lastRun": {"targets": len(targets), "enriched": done, "errors": errors,
                    "elapsedSec": int(time.time() - started)},
        "items": items,
    }
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(enrich, f, ensure_ascii=False, indent=2)
    print("-" * 70)
    print(f"Yorumlanan: {done} | hata: {errors} | toplam arsiv: {len(items)} | "
          f"sure: {int(time.time()-started)}s -> {args.out}")


if __name__ == "__main__":
    main()
