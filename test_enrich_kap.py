#!/usr/bin/env python3
"""
test_enrich_kap.py — enrich_kap.py icin AGSIZ, deterministik birim testleri.

Saf yardimci fonksiyonlari (metin temizleme, tutar/yon/ozet cikarimi, KAP
odak penceresi, PDF ek-URL bulma, LLM JSON ayristirma) ve YENI fallback
zincirini (build_provider_chain + interpret_with_fallback) dogrular. Ag erisimi
yoktur: saglayici cagrilari monkeypatch ile sahte fonksiyonla degistirilir.

Calistirma:
  python test_enrich_kap.py        # bagimsiz (pytest gerekmez)
  pytest test_enrich_kap.py        # pytest ile de kosar
"""
import os
import sys

import enrich_kap as ek


# --------------------------------------------------------------------------
# Saf metin yardimcilari
# --------------------------------------------------------------------------
def test_norm_turkish_lowercase():
    assert ek._norm("İHALE") == "ihale"
    assert ek._norm("ISI") == "ısı"
    assert ek._norm(None) == ""


def test_parse_date_formats():
    assert ek._parse_date("15.06.2026 18:30:00").year == 2026
    assert ek._parse_date("15.06.2026").day == 15
    assert ek._parse_date("2026-06-15").month == 6
    assert ek._parse_date("") is None
    assert ek._parse_date("gecersiz") is None


def test_to_text_variants():
    assert ek.to_text(None) == ""
    assert ek.to_text("  bir   iki ") == "bir iki"
    # HTML etiketleri temizlenir, entity cozulur
    assert ek.to_text("<p>k&amp;r</p>") == "k&r"
    # dict -> degerler birlestirilir
    out = ek.to_text({"a": "satis", "b": "120 TL"})
    assert "satis" in out and "120 TL" in out


def test_extract_amounts():
    text = "Sirket 1,25 milyar TL sozlesme imzaladi ve 500 milyon USD yatirim yapti."
    amts = ek.extract_amounts(text)
    assert any("milyar TL" in a for a in amts)
    assert any("milyon" in a and ("USD" in a) for a in amts)
    # limit'e uyar
    assert len(ek.extract_amounts(text, limit=1)) == 1


def test_refine_direction():
    d, pos, neg = ek.refine_direction("Sirket ihaleyi kazandi, sozlesme imzalandi.", "?")
    assert d == "+" and pos > 0
    d, pos, neg = ek.refine_direction("Hakkinda dava acildi ve ceza verildi.", "?")
    assert d == "-" and neg > 0
    # ipucu yoksa taban yon korunur
    d, _, _ = ek.refine_direction("Olagan genel kurul toplandi.", "0")
    assert d == "0"


def test_make_summary_prefers_numeric_sentences():
    text = ("Sirket bugun bir aciklama yapti. "
            "Yonetim kurulu 250 milyon TL temettu dagitim karari aldi. "
            "Hava bugun guzeldi.")
    s = ek.make_summary(text)
    assert "250 milyon TL" in s
    assert len(s) <= 240 + 1  # ... ekiyle


def test_focus_content_short_passthrough():
    # max_chars'tan kisa metin oldugu gibi doner
    assert ek._focus_content("kisa metin", 1000) == "kisa metin"


def test_focus_content_anchors_on_ozet_bilgi():
    noise = "Tum Kategoriler detayli sorgulama Sik Arananlar " * 50
    body = noise + " Özet Bilgi: 750 milyon TL tutarinda sozlesme imzalandi. " + noise
    focused = ek._focus_content(body, 200)
    assert "750 milyon TL" in focused
    assert len(focused) <= 200


def test_find_attachment_urls():
    raw = ('bkz <a href="https://www.kap.org.tr/tr/yayinindir/12345">ek</a> ve '
           'https://example.com/rapor.PDF ayrica https://site.com/sayfa.html')
    urls = ek.find_attachment_urls(raw)
    assert any(u.lower().endswith(".pdf") for u in urls)
    assert any("kap.org.tr" in u for u in urls)
    assert all(not u.endswith(".html") for u in urls)


# --------------------------------------------------------------------------
# LLM JSON ayristirma
# --------------------------------------------------------------------------
def test_parse_llm_json_clean():
    raw = '{"summary":"ozet","direction":"+","impact":4,"amounts":["1 milyar TL"],"rationale":"gerekce"}'
    r = ek._parse_llm_json(raw)
    assert r["direction"] == "+"
    assert r["impact"] == 4
    assert r["amounts"] == ["1 milyar TL"]


def test_parse_llm_json_embedded_and_normalized():
    # Cevrede fazladan metin + gecersiz yon -> '?' normalize
    raw = 'Iste cevap: {"summary":"x","direction":"yukari","impact":2,"amounts":"tek"} tesekkurler'
    r = ek._parse_llm_json(raw)
    assert r["direction"] == "?"          # gecersiz -> ?
    assert r["amounts"] == ["tek"]        # str -> liste
    assert r["impact"] == 2


def test_parse_llm_json_no_json_raises():
    raised = False
    try:
        ek._parse_llm_json("hic json yok")
    except ValueError:
        raised = True
    assert raised


# --------------------------------------------------------------------------
# Fallback zinciri (YENI) — agsiz, monkeypatch'li
# --------------------------------------------------------------------------
def _set_env(**kw):
    """Verilen env degiskenlerini ayarla/sil; eski degerleri geri vermek icin dondur."""
    old = {}
    for k, v in kw.items():
        old[k] = os.environ.get(k)
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v
    return old


def _restore_env(old):
    for k, v in old.items():
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v


def test_build_provider_chain_auto_filters_by_token():
    old = _set_env(GITHUB_TOKEN="t1", GROQ_API_KEY="t2",
                   CEREBRAS_API_KEY=None, OPENROUTER_API_KEY=None,
                   OPENCODE_ZEN_API_KEY=None, NVIDIA_API_KEY=None)
    try:
        chain = ek.build_provider_chain("github", "auto")
        engines = [p["engine"] for p in chain]
        # Yalniz anahtari olanlar; birincil basta
        assert engines[0] == "github"
        assert "groq" in engines
        assert "cerebras" not in engines  # anahtar yok
    finally:
        _restore_env(old)


def test_build_provider_chain_none_only_primary():
    old = _set_env(GITHUB_TOKEN="t1", GROQ_API_KEY="t2")
    try:
        chain = ek.build_provider_chain("github", "none")
        assert [p["engine"] for p in chain] == ["github"]
    finally:
        _restore_env(old)


def test_build_provider_chain_explicit_and_model_override():
    old = _set_env(GITHUB_TOKEN="t1", GROQ_API_KEY="t2")
    try:
        chain = ek.build_provider_chain("github", "groq", model_override="ozel-model")
        engines = [p["engine"] for p in chain]
        assert engines == ["github", "groq"]
        # model override yalniz birincile
        assert chain[0]["model"] == "ozel-model"
        assert chain[1]["model"] == ek.PROVIDER_PRESETS["groq"]["model"]
    finally:
        _restore_env(old)


def test_build_provider_chain_empty_when_no_tokens():
    old = _set_env(GITHUB_TOKEN=None, GH_TOKEN=None, GROQ_API_KEY=None,
                   CEREBRAS_API_KEY=None, OPENROUTER_API_KEY=None,
                   OPENCODE_ZEN_API_KEY=None, NVIDIA_API_KEY=None)
    try:
        assert ek.build_provider_chain("github", "auto") == []
    finally:
        _restore_env(old)


def _fake_chain():
    return [
        {"engine": "github", "base": "u0", "token": "t", "model": "m0", "cap": 9000, "min_sleep": 0},
        {"engine": "groq", "base": "u1", "token": "t", "model": "m1", "cap": 12000, "min_sleep": 7},
        {"engine": "cerebras", "base": "u2", "token": "t", "model": "m2", "cap": 18000, "min_sleep": 0},
    ]


def test_interpret_with_fallback_advances_on_429():
    chain = _fake_chain()
    calls = []

    def fake(base, token, model, sym, title, cat, focused, cap):
        calls.append(base)
        if base in ("u0", "u1"):
            raise ek.RateLimitError("429")
        return {"direction": "+", "summary": "ok", "impact": 3, "amounts": [], "rationale": ""}

    orig = ek.interpret_openai_compatible
    ek.interpret_openai_compatible = fake
    try:
        res, used_idx, focused = ek.interpret_with_fallback(chain, 0, "AAA", "t", "c", "govde metni")
        assert used_idx == 2          # u0,u1 429 -> u2 tuttu
        assert res["summary"] == "ok"
        assert calls == ["u0", "u1", "u2"]
    finally:
        ek.interpret_openai_compatible = orig


def test_interpret_with_fallback_all_429_raises():
    chain = _fake_chain()

    def fake(*a, **k):
        raise ek.RateLimitError("429")

    orig = ek.interpret_openai_compatible
    ek.interpret_openai_compatible = fake
    try:
        raised = False
        try:
            ek.interpret_with_fallback(chain, 0, "AAA", "t", "c", "govde")
        except ek.RateLimitError:
            raised = True
        assert raised
    finally:
        ek.interpret_openai_compatible = orig


def test_interpret_with_fallback_non_ratelimit_propagates():
    chain = _fake_chain()

    def fake(base, *a, **k):
        raise RuntimeError("HTTP 400: content filter")  # 429 DEGIL -> gecmemeli

    orig = ek.interpret_openai_compatible
    ek.interpret_openai_compatible = fake
    try:
        raised = False
        try:
            ek.interpret_with_fallback(chain, 0, "AAA", "t", "c", "govde")
        except RuntimeError as e:
            raised = "400" in str(e)
        assert raised
    finally:
        ek.interpret_openai_compatible = orig


def test_interpret_with_fallback_starts_from_current_idx():
    chain = _fake_chain()
    calls = []

    def fake(base, *a, **k):
        calls.append(base)
        return {"direction": "0", "summary": "s", "impact": 1, "amounts": [], "rationale": ""}

    orig = ek.interpret_openai_compatible
    ek.interpret_openai_compatible = fake
    try:
        res, used_idx, _ = ek.interpret_with_fallback(chain, 1, "AAA", "t", "c", "govde")
        assert used_idx == 1
        assert calls == ["u1"]   # idx 0'a hic dokunmaz
    finally:
        ek.interpret_openai_compatible = orig


# --------------------------------------------------------------------------
# load_priority_symbols — gecici dosyalarla
# --------------------------------------------------------------------------
def test_load_priority_symbols(tmp_path=None):
    import json
    import tempfile
    d = tmp_path or tempfile.mkdtemp()
    d = str(d)
    with open(os.path.join(d, "model_portfolios.json"), "w", encoding="utf-8") as f:
        json.dump({"Portfolios": [{"Holdings": [{"Symbol": "asels"}, {"Symbol": "THYAO"}]}]}, f)
    with open(os.path.join(d, "instant_entry_portfolio.json"), "w", encoding="utf-8") as f:
        json.dump({"Holdings": [{"Symbol": "garan"}]}, f)
    syms = ek.load_priority_symbols(d)
    assert {"ASELS", "THYAO", "GARAN"} <= syms


# --------------------------------------------------------------------------
# Bagimsiz kosucu (pytest yoksa)
# --------------------------------------------------------------------------
def _run_all():
    tests = [(n, f) for n, f in sorted(globals().items())
             if n.startswith("test_") and callable(f)]
    passed = 0
    failed = []
    for name, fn in tests:
        try:
            fn()
            passed += 1
            print(f"  PASS  {name}")
        except Exception as e:  # noqa: BLE001
            failed.append((name, e))
            print(f"  FAIL  {name}: {type(e).__name__}: {e}")
    print("-" * 60)
    print(f"{passed}/{len(tests)} test gecti.")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(_run_all())
