/* =========================================================================
   BIST Yatırım Paneli — uygulama mantığı (vanilla JS, framework yok)
   Yükleme sırası: data/latest_report.json -> data/sample_report.json -> gömülü örnek.
   Eksik/bozuk alanlar paneli KIRMAZ; her bölüm kendi fallback'ini gösterir.
   Mevcut bot kodundan tamamen bağımsızdır.
   ========================================================================= */
(function () {
  "use strict";

  /* ---------------- Gömülü örnek (file:// ile sunucusuz açılış için) -------- */
  // Not: data/sample_report.json ile aynı şema. fetch erişilemezse bu kullanılır.
  const EMBEDDED_SAMPLE = {
    meta: { schemaVersion: 1, reportDate: "2026-06-30", generatedAt: "2026-06-30T21:12:18+03:00",
      lastUpdatedText: "30.06.2026 21:12", marketStatus: "Kapalı", strategy: "Dengeli", scannedCount: 612,
      source: "Gömülü örnek veri (file://)", isSample: true, disclaimer: "Bu panel karar destek amaçlıdır, yatırım tavsiyesi değildir." },
    history: [ { date: "2026-06-30", label: "Son rapor" }, { date: "2026-06-29", label: "29.06.2026" } ],
    summary: { portfolioValueTL: 101856.13, initialCapitalTL: 100000, dailyChangePct: 0.42, weeklyChangePct: 1.21,
      monthlyChangePct: 1.86, bestStock: { ticker: "DSTKF", changePct: 4.83 }, worstStock: { ticker: "YGGYO", changePct: -2.14 },
      riskScore: { value: 38, label: "Orta" }, llmStance: "Nötr" },
    performance: { series: [
      { name: "Dengeli Model Portföy", key: "pf_Dengeli", points: [["2026-06-11",0],["2026-06-17",1.3],["2026-06-24",1.6],["2026-06-30",1.86]].map(p=>({t:p[0],v:p[1]})) },
      { name: "Değer Model Portföyü", key: "pf_Deger", points: [["2026-06-11",0],["2026-06-17",3.1],["2026-06-24",5.4],["2026-06-30",7.70]].map(p=>({t:p[0],v:p[1]})) },
      { name: "Risk Dengeli Model Portföyü", key: "pf_RiskDengeli", points: [["2026-06-11",0],["2026-06-17",-1.1],["2026-06-24",-2.5],["2026-06-30",-3.30]].map(p=>({t:p[0],v:p[1]})) },
      { name: "BIST100", key: "bist100", points: [["2026-06-11",0],["2026-06-17",0.5],["2026-06-24",0.33],["2026-06-30",0.33]].map(p=>({t:p[0],v:p[1]})) },
      { name: "Nasdaq (TRY)", key: "nasdaq", points: [["2026-06-11",0],["2026-06-20",2.8],["2026-06-30",4.64]].map(p=>({t:p[0],v:p[1]})) },
      { name: "Altın (TRY)", key: "gold", points: [["2026-06-11",0],["2026-06-20",1.4],["2026-06-30",2.46]].map(p=>({t:p[0],v:p[1]})) }
    ]},
    allocation: { rebalanceNeeded: true, rebalanceNote: "CCOLA hedef ağırlığın üzerinde.",
      holdings: [ { ticker: "CCOLA", weightPct: 21.3, targetPct: 20 }, { ticker: "GLYHO", weightPct: 20.1, targetPct: 20 },
        { ticker: "TUPRS", weightPct: 19.8, targetPct: 20 }, { ticker: "AKSA", weightPct: 19.4, targetPct: 20 }, { ticker: "ARASE", weightPct: 19.4, targetPct: 20 } ] },
    modelPortfolios: [
      { id: "Dengeli", name: "Dengeli Model Portföy", strategy: "Dengeli", valueTL: 101856.13, returnPct: 1.86, alphaPct: 1.53, holdings: [{ticker:"CCOLA",weightPct:21.3},{ticker:"GLYHO",weightPct:20.1},{ticker:"TUPRS",weightPct:19.8}] },
      { id: "Momentum", name: "Momentum Model Portföyü", strategy: "Momentum", valueTL: 106592.24, returnPct: 6.59, alphaPct: 6.26, holdings: [{ticker:"GLYHO",weightPct:20},{ticker:"THYAO",weightPct:20},{ticker:"DSTKF",weightPct:20}] },
      { id: "Deger", name: "Değer Model Portföyü", strategy: "Değer", valueTL: 107704.23, returnPct: 7.70, alphaPct: 7.37, holdings: [{ticker:"NTGAZ",weightPct:20},{ticker:"TUPRS",weightPct:20},{ticker:"TTKOM",weightPct:20}] },
      { id: "RiskDengeli", name: "Risk Dengeli Model Portföyü", strategy: "Dengeli", valueTL: 96699.26, returnPct: -3.30, alphaPct: -3.95, holdings: [{ticker:"CCOLA",weightPct:24},{ticker:"TUPRS",weightPct:22}] }
    ],
    instantEntry: { initialCapitalTL: 100000, dailyBudgetTL: 5000, cashTL: 73428.22, holdingsValueTL: 28427.91, totalValueTL: 101856.13, totalReturnPct: 1.86, totalBoughtTL: 30000, realizedGainTL: 928.22, statusNote: "Bugünkü alım: THYAO 5.000 TL.",
      holdings: [ {ticker:"THYAO",company:"Türk Hava Yolları",valueTL:5120.5,weightPct:18,gainPct:2.4},{ticker:"ARASE",company:"Aras Elektrik",valueTL:6207,weightPct:21.8,gainPct:5.1},{ticker:"DSTKF",company:"Destek Faktoring",valueTL:5200.2,weightPct:18.3,gainPct:-1.2} ] },
    stocks: [
      { ticker: "CCOLA", company: "Coca-Cola İçecek", price: 612.5, dailyPct: 1.8, weeklyPct: 4.2, rsi: 61.2, macd: 3.4, volume: "4.1M", signal: "AL", llmNote: "Defansif tüketim, güçlü bilanço.", action: "alım bölgesi" },
      { ticker: "DSTKF", company: "Destek Faktoring", price: 14.88, dailyPct: 4.8, weeklyPct: 9.7, rsi: 73.1, macd: 0.9, volume: "31.2M", signal: "AL", llmNote: "Hacim patlaması; kâr-al bölgesi.", action: "riskli" },
      { ticker: "THYAO", company: "Türk Hava Yolları", price: 312.2, dailyPct: 1.1, weeklyPct: 3.0, rsi: 60.4, macd: 4.7, volume: "18.9M", signal: "AL", llmNote: "Trend sağlam.", action: "alım bölgesi" },
      { ticker: "YGGYO", company: "Yeşil GYO", price: 7.34, dailyPct: -2.1, weeklyPct: -5.2, rsi: 31.5, macd: -0.6, volume: "12.4M", signal: "BEKLE", llmNote: "Aşırı satım, dönüş teyidi yok.", action: "bekle" }
    ],
    sectorRotation: [ { sector: "Enerji", dailyPct: 1.4, weeklyPct: 3.8, monthlyPct: 9.2, flow: "giriş" }, { sector: "Ulaştırma", dailyPct: 1.1, weeklyPct: 2.9, monthlyPct: 6.5, flow: "giriş" },
      { sector: "Kimya", dailyPct: -0.5, weeklyPct: -1.1, monthlyPct: -2.4, flow: "çıkış" }, { sector: "Gayrimenkul", dailyPct: -1.3, weeklyPct: -4.0, monthlyPct: -7.8, flow: "çıkış" } ],
    sectorFlow: [
      { from: "Gayrimenkul", to: "Enerji", flow: 5.85 }, { from: "Gayrimenkul", to: "Ulaştırma", flow: 4.13 },
      { from: "Kimya", to: "Enerji", flow: 1.8 }, { from: "Kimya", to: "Ulaştırma", flow: 1.27 }
    ],
    sectorFlowBasis: "aylık",
    smartMoney: { commentary: "Akış enerji ve ulaştırmada; gayrimenkulde realizasyon.",
      items: [ { ticker: "DSTKF", type: "Büyük alım", note: "Hacim 3,1x." }, { ticker: "YGGYO", type: "Çıkış", note: "Hacimli satış." } ],
      strengthening: ["DSTKF", "ARASE", "THYAO"], weakening: ["YGGYO", "GUBRF"] },
    technicalSignals: { overbought: [{ ticker: "DSTKF", rsi: 73.1 }], oversold: [{ ticker: "YGGYO", rsi: 31.5 }],
      macdCross: [{ ticker: "TUPRS", note: "Al kesişimi" }], trendStrengthening: [{ ticker: "THYAO", note: "200g üstü" }],
      momentumLosing: [{ ticker: "GUBRF", note: "Negatif ivme" }], breakout: [{ ticker: "DSTKF", note: "Direnç kırılımı" }] },
    llmCommentary: { stance: "Nötr", marketSummary: "BIST yataya yakın, momentum hisseleri ayrıştı.", portfolioComment: "Portföy %1,86 ile endeksin üzerinde.",
      risks: ["DSTKF aşırı alım bölgesine yakın."], opportunities: ["TUPRS kademeli alım."], levels: ["BIST100: 14.450 destek."], watchNext: "Enerji akışını izle." },
    actionItems: { watch: ["THYAO", "TUPRS"], rebalance: ["CCOLA hafif azalt"], riskReduction: ["DSTKF kâr-al"], buyWatchlist: ["TUPRS"], note: "Karar destek amaçlıdır, yatırım tavsiyesi değildir." }
  };

  /* ---------------- Yardımcılar ---------------- */
  const $ = (sel, root) => (root || document).querySelector(sel);
  const fmtTR = (n, d = 2) => new Intl.NumberFormat("tr-TR", { minimumFractionDigits: d, maximumFractionDigits: d }).format(n);
  const isNum = (v) => typeof v === "number" && isFinite(v);
  const has = (v) => v !== null && v !== undefined && v !== "";
  const SERIES_COLORS = { bist100: "#e7ecf3", nasdaq: "#1db17a", sp500: "#22a3c0", gold: "#d9a23b", usdtry: "#9a7bff", deposit: "#e5849b" };
  const PALETTE = ["#6e8bff", "#e7ecf3", "#1db17a", "#d9a23b", "#22a3c0", "#9a7bff", "#e5849b"];
  // Model portföy çizgileri için ayrı, canlı bir palet (BIST100/Altın gibi benchmark
  // renkleriyle çakışmasın) — portföyler solid+kalın, benchmark'lar dashed+ince çizilir.
  const PF_PALETTE = ["#6e8bff", "#f0a23c", "#31c48d", "#f4615f", "#a78bfa", "#22c1c3", "#e879b9"];
  function shortPfName(name) { return String(name || "").replace(/\s*Model Portföyü?\s*$/i, ""); }

  function pctText(v) { if (!isNum(v)) return "—"; const s = v > 0 ? "+" : ""; return s + fmtTR(v) + "%"; }
  function pctClass(v) { if (!isNum(v)) return "flat"; return v > 0 ? "pos" : v < 0 ? "neg" : "flat"; }
  function tlText(v, d = 0) { return isNum(v) ? fmtTR(v, d) + " TL" : "—"; }
  function esc(s) { const d = document.createElement("div"); d.textContent = s == null ? "" : String(s); return d.innerHTML; }
  function emptyHTML(title, msg) {
    return '<div class="empty"><span class="empty__title">' + esc(title || "Veri bulunamadı") + "</span>" +
      (msg ? "<span>" + esc(msg) + "</span>" : "") + "</div>";
  }
  function inlineEmpty(msg) { return '<div class="inline-empty">' + esc(msg || "Bu alan henüz üretilmedi.") + "</div>"; }
  function arr(v) { return Array.isArray(v) ? v : []; }

  /* ---------------- 1) Header ---------------- */
  function renderHeader(report) {
    const m = report.meta || {};
    const meta = $("#headerMeta");
    if (meta) {
      const bits = [];
      if (has(m.reportDate)) bits.push("<span>Rapor tarihi: <b>" + esc(m.reportDate) + "</b></span>");
      if (has(m.lastUpdatedText)) bits.push("<span>Son güncelleme: <b>" + esc(m.lastUpdatedText) + "</b></span>");
      if (has(m.strategy)) bits.push("<span>Strateji: <b>" + esc(m.strategy) + "</b></span>");
      if (isNum(m.scannedCount)) bits.push("<span><b>" + fmtTR(m.scannedCount, 0) + "</b> hisse tarandı</span>");
      meta.innerHTML = bits.length ? bits.join("") : inlineEmpty("Rapor üst bilgisi yok.");
    }
    const status = $("#marketStatus"), statusText = $("#marketStatusText");
    if (status && statusText) {
      const s = (m.marketStatus || "").toString().toLowerCase();
      status.classList.remove("is-open", "is-closed");
      if (s.includes("açık") || s.includes("acik") || s.includes("open")) status.classList.add("is-open");
      else if (s.includes("kapal") || s.includes("closed")) status.classList.add("is-closed");
      statusText.textContent = has(m.marketStatus) ? m.marketStatus : "Bilinmiyor";
    }
    const note = $("#sourceNote");
    if (note) note.textContent = has(m.source) ? m.source : "";
    const sel = $("#historySelect");
    if (sel) {
      const hist = arr(report.history);
      if (!hist.length) { sel.innerHTML = "<option>Son rapor</option>"; sel.disabled = true; }
      else { sel.disabled = false; sel.innerHTML = hist.map((h, i) =>
        '<option value="' + esc(h.date) + '"' + (i === 0 ? " selected" : "") + ">" + esc(h.label || h.date) + "</option>").join(""); }
    }
    const disc = m.disclaimer || "Karar destek amaçlıdır, yatırım tavsiyesi değildir.";
    const sd = $("#sidebarDisclaimer"); if (sd) sd.textContent = disc;
    const fd = $("#footDisclaimer"); if (fd) fd.textContent = disc;
  }

  /* ---------------- 2) KPI kartları ---------------- */
  function renderKpiCards(report) {
    const host = $("#kpiCards"); if (!host) return;
    const s = report.summary;
    if (!s || typeof s !== "object") { host.innerHTML = emptyHTML("Özet veri yok", "summary alanı üretilmemiş."); return; }
    const stanceClass = stanceToClass(s.llmStance);
    const cards = [
      kpi("Portföy Değeri", isNum(s.portfolioValueTL) ? fmtTR(s.portfolioValueTL) + " TL" : "—", true,
        isNum(s.initialCapitalTL) ? "Sermaye " + fmtTR(s.initialCapitalTL, 0) + " TL" : ""),
      kpiChange("Günlük Değişim", s.dailyChangePct),
      kpiChange("Haftalık Değişim", s.weeklyChangePct),
      kpiChange("Aylık Değişim", s.monthlyChangePct),
      kpiStock("En İyi Hisse", s.bestStock),
      kpiStock("En Zayıf Hisse", s.worstStock),
      kpiRisk("Risk Skoru", s.riskScore),
      kpi("YZ Genel Görüş", "", false, "", '<span class="badge ' + stanceClass + '"><span class="badge__dot"></span>' + esc(has(s.llmStance) ? s.llmStance : "—") + "</span>")
    ];
    host.innerHTML = cards.join("");
  }
  function kpi(label, value, mono, sub, chip) {
    return '<div class="kpi"><span class="kpi__label">' + esc(label) + "</span>" +
      (chip ? '<div class="kpi__chip">' + chip + "</div>" : '<span class="kpi__value' + (mono ? " mono" : "") + '">' + esc(value) + "</span>") +
      (sub ? '<span class="kpi__sub">' + esc(sub) + "</span>" : "") + "</div>";
  }
  function kpiChange(label, v) {
    return '<div class="kpi"><span class="kpi__label">' + esc(label) + "</span>" +
      '<span class="kpi__value mono ' + pctClass(v) + '">' + pctText(v) + "</span>" +
      '<span class="kpi__sub">' + (isNum(v) ? "önceki döneme göre" : "veri yok") + "</span></div>";
  }
  function kpiStock(label, o) {
    if (!o || !has(o.ticker)) return kpi(label, "—", false, "veri yok");
    return '<div class="kpi"><span class="kpi__label">' + esc(label) + "</span>" +
      '<span class="kpi__value">' + esc(o.ticker) + "</span>" +
      '<span class="kpi__sub ' + pctClass(o.changePct) + '">' + pctText(o.changePct) + "</span></div>";
  }
  function kpiRisk(label, o) {
    if (!o) return kpi(label, "—", false, "veri yok");
    const v = isNum(o.value) ? fmtTR(o.value, 0) : "—";
    return '<div class="kpi"><span class="kpi__label">' + esc(label) + "</span>" +
      '<span class="kpi__value mono">' + v + "<span style='font-size:13px;color:var(--text-faint)'>/100</span></span>" +
      '<span class="kpi__sub">' + esc(has(o.label) ? o.label : "") + "</span></div>";
  }
  function stanceToClass(st) {
    const s = (st || "").toLowerCase();
    if (s.includes("pozitif") || s.includes("positive")) return "badge--pos";
    if (s.includes("negatif") || s.includes("negative")) return "badge--neg";
    return "badge--neutral";
  }

  /* ---------------- 3) Performans grafiği ---------------- */
  let perfChart = null;
  function renderPerformanceChart(report) {
    const wrap = $("#perfChart"), empty = $("#perfEmpty"), legend = $("#perfLegend");
    if (!wrap) return;
    const perf = report.performance || {};
    const series = arr(perf.series).filter((s) => s && arr(s.points).length > 0);
    if (!series.length || typeof window.Chart === "undefined") {
      if (empty) { empty.hidden = false; empty.innerHTML = emptyHTML(
        series.length ? "Grafik kütüphanesi yüklenemedi" : "Performans verisi yok",
        perf.note || "Veri biriktikçe grafik otomatik dolacaktır."); }
      wrap.style.display = "none"; if (legend) legend.innerHTML = ""; return;
    }
    if (empty) empty.hidden = true; wrap.style.display = "";
    const labels = longestLabels(series);
    // Model portföyler (pf_*) önce, sonra benchmark'lar — legend'de portföyler öne çıksın.
    const ordered = series.slice().sort((a, b) => {
      const ap = a.key && a.key.indexOf("pf_") === 0 ? 0 : 1, bp = b.key && b.key.indexOf("pf_") === 0 ? 0 : 1;
      return ap - bp;
    });
    let pfIdx = 0;
    const datasets = ordered.map((s) => {
      const isPf = s.key && s.key.indexOf("pf_") === 0;
      const color = isPf ? PF_PALETTE[pfIdx % PF_PALETTE.length] : (SERIES_COLORS[s.key] || PALETTE[0]);
      if (isPf) pfIdx++;
      const map = {}; arr(s.points).forEach((p) => { map[p.t] = p.v; });
      return { label: isPf ? shortPfName(s.name) : (s.name || s.key || "Seri"),
        data: labels.map((t) => (isNum(map[t]) ? map[t] : null)),
        borderColor: color, backgroundColor: color, borderWidth: isPf ? 2.2 : 1.3,
        borderDash: isPf ? [] : [5, 3],
        tension: 0.28, pointRadius: 0, pointHoverRadius: 4, spanGaps: true, hidden: false, _isPf: isPf };
    });
    const css = getComputedStyle(document.body);
    const gridc = css.getPropertyValue("--grid-line").trim() || "rgba(255,255,255,.05)";
    const textc = css.getPropertyValue("--text-dim").trim() || "#97a3b6";
    if (perfChart) perfChart.destroy();
    perfChart = new window.Chart(wrap.getContext("2d"), {
      type: "line", data: { labels: labels, datasets: datasets },
      options: { responsive: true, maintainAspectRatio: false, interaction: { mode: "index", intersect: false },
        plugins: { legend: { display: false },
          tooltip: { callbacks: { label: (c) => " " + c.dataset.label + ": " + (isNum(c.parsed.y) ? (c.parsed.y > 0 ? "+" : "") + fmtTR(c.parsed.y) + "%" : "—") } } },
        scales: { x: { grid: { color: gridc }, ticks: { color: textc, maxTicksLimit: 8, font: { size: 11 } } },
          y: { grid: { color: gridc }, ticks: { color: textc, font: { size: 11 }, callback: (v) => v + "%" } } } }
    });
    if (legend) {
      legend.innerHTML = datasets.map((d, i) =>
        '<span class="legend__item" data-idx="' + i + '"><span class="legend__swatch" style="background:' + d.borderColor + '"></span>' + esc(d.label) + "</span>").join("");
      legend.querySelectorAll(".legend__item").forEach((it) => {
        it.addEventListener("click", () => {
          const idx = +it.dataset.idx; const meta = perfChart.getDatasetMeta(idx);
          meta.hidden = meta.hidden === null ? !perfChart.data.datasets[idx].hidden : !meta.hidden;
          it.classList.toggle("is-off", meta.hidden); perfChart.update();
        });
      });
    }
  }
  function longestLabels(series) {
    let best = []; series.forEach((s) => { const pts = arr(s.points); if (pts.length > best.length) best = pts.map((p) => p.t); });
    return best;
  }

  /* ---------------- 4) Portföy dağılımı ---------------- */
  let allocPieCharts = [];
  function renderPortfolioTable(report) {
    const host = $("#allocList"); const alert = $("#rebalanceAlert");
    const a = report.allocation || {};
    const holdings = arr(a.holdings);
    if (host) {
      if (!holdings.length) { host.innerHTML = inlineEmpty("Portföy dağılımı verisi yok."); }
      else {
        const maxW = Math.max.apply(null, holdings.map((h) => (isNum(h.weightPct) ? h.weightPct : 0)).concat([1]));
        host.innerHTML = holdings.map((h) => {
          const w = isNum(h.weightPct) ? h.weightPct : 0;
          const t = isNum(h.targetPct) ? h.targetPct : null;
          const fill = Math.min(100, (w / maxW) * 100);
          const targetPos = t != null ? Math.min(100, (t / maxW) * 100) : null;
          return '<div class="alloc__row"><span class="alloc__tk">' + esc(h.ticker || "—") + "</span>" +
            '<span class="alloc__bar"><span class="alloc__fill" style="width:' + fill.toFixed(1) + '%"></span>' +
            (targetPos != null ? '<span class="alloc__target" style="left:' + targetPos.toFixed(1) + '%" title="Hedef %' + fmtTR(t) + '"></span>' : "") +
            "</span><span class='alloc__vals'>%" + fmtTR(w) + (t != null ? " · hedef %" + fmtTR(t) : "") + "</span></div>";
        }).join("");
      }
    }
    if (alert) {
      if (a.rebalanceNeeded) {
        alert.innerHTML = '<div class="rebalance-alert"><span class="badge badge--warn"><span class="badge__dot"></span>Dengeleme</span>' +
          "<div><b>Dengeleme öneriliyor.</b> " + esc(a.rebalanceNote || "Ağırlıklar hedeften sapmış.") + "</div></div>";
      } else if ("rebalanceNeeded" in a) {
        alert.innerHTML = '<div class="rebalance-alert" style="background:var(--pos-soft);border-color:color-mix(in srgb,var(--pos) 30%,transparent)"><span class="badge badge--pos"><span class="badge__dot"></span>Dengede</span><div>Ağırlıklar hedefe yakın; dengeleme gerekmiyor.</div></div>';
      } else { alert.innerHTML = ""; }
    }
  }

  /* ---------------- 4a-2) Ağırlık dağılımı — TÜM portföyler (her biri kendi pastası) ---------------- */
  function renderAllocationPies(report) {
    const host = $("#allocPies"); if (!host) return;
    allocPieCharts.forEach((c) => { try { c.destroy(); } catch (e) {} });
    allocPieCharts = [];
    const list = arr(report.modelPortfolios).filter((p) => arr(p.holdings).length > 0);
    if (!list.length) { host.innerHTML = inlineEmpty("Model portföy dağılımı verisi yok."); return; }
    if (typeof window.Chart === "undefined") { host.innerHTML = emptyHTML("Grafik kütüphanesi yüklenemedi"); return; }
    host.innerHTML = list.map((p, i) =>
      '<div class="piecard"><h4 class="piecard__title">' + esc(shortPfName(p.name) || p.id || "—") + "</h4>" +
      '<div class="piecard__body"><canvas id="pie_' + i + '"></canvas></div></div>').join("");
    const css = getComputedStyle(document.body);
    const border = css.getPropertyValue("--surface").trim() || "#141925";
    const textc = css.getPropertyValue("--text-dim").trim();
    list.forEach((p, i) => {
      const cv = document.getElementById("pie_" + i); if (!cv) return;
      const holds = arr(p.holdings);
      const chart = new window.Chart(cv.getContext("2d"), {
        type: "doughnut",
        data: { labels: holds.map((h) => h.ticker || "—"),
          datasets: [{ data: holds.map((h) => (isNum(h.weightPct) ? h.weightPct : 0)),
            backgroundColor: holds.map((_, j) => PALETTE[j % PALETTE.length]), borderColor: border, borderWidth: 2 }] },
        options: { responsive: true, maintainAspectRatio: false, cutout: "58%",
          plugins: { legend: { position: "bottom", labels: { color: textc, boxWidth: 8, font: { size: 10 }, padding: 8 } },
            tooltip: { callbacks: { label: (c) => " " + c.label + ": %" + fmtTR(c.parsed) } } } }
      });
      allocPieCharts.push(chart);
    });
  }

  /* ---------------- 4b) Model portföyler (hepsi) ---------------- */
  let pfCompareChart = null;
  function renderPortfolioCompareChart(report) {
    const wrap = $("#pfCompareChart"), empty = $("#pfCompareEmpty"); if (!wrap) return;
    const list = arr(report.modelPortfolios).filter((p) => isNum(p.returnPct));
    if (!list.length || typeof window.Chart === "undefined") {
      if (empty) { empty.hidden = false; empty.innerHTML = emptyHTML("Karşılaştırma verisi yok", "modelPortfolios alanı üretilmemiş."); }
      wrap.style.display = "none"; return;
    }
    if (empty) empty.hidden = true; wrap.style.display = "";
    const sorted = list.slice().sort((a, b) => b.returnPct - a.returnPct);
    // Kısa etiket: "Model Portföy(ü)" son ekini at — dar ekranda Y ekseni etiketi kesilmesin.
    const labels = sorted.map((p) => (p.name || p.id || "—").replace(/\s*Model Portföyü?\s*$/i, ""));
    const css = getComputedStyle(document.body);
    const posC = css.getPropertyValue("--pos").trim() || "#1db17a";
    const negC = css.getPropertyValue("--neg").trim() || "#e5484d";
    const accC = css.getPropertyValue("--accent").trim() || "#6e8bff";
    const gridc = css.getPropertyValue("--grid-line").trim();
    const textc = css.getPropertyValue("--text-dim").trim();
    const hasAlpha = sorted.some((p) => isNum(p.alphaPct));
    const datasets = [{
      label: "Getiri %", data: sorted.map((p) => p.returnPct),
      backgroundColor: sorted.map((p) => (p.returnPct >= 0 ? posC : negC)), borderRadius: 4, maxBarThickness: 28
    }];
    if (hasAlpha) {
      datasets.push({ label: "Alfa % (BIST100'e karşı)", data: sorted.map((p) => (isNum(p.alphaPct) ? p.alphaPct : null)), backgroundColor: accC, borderRadius: 4, maxBarThickness: 14 });
    }
    if (pfCompareChart) pfCompareChart.destroy();
    pfCompareChart = new window.Chart(wrap.getContext("2d"), {
      type: "bar",
      data: { labels: labels, datasets: datasets },
      options: {
        indexAxis: "y", responsive: true, maintainAspectRatio: false,
        plugins: { legend: { display: hasAlpha, position: "top", labels: { color: textc, boxWidth: 10, font: { size: 11 } } },
          tooltip: { callbacks: { label: (c) => " " + c.dataset.label + ": " + (isNum(c.parsed.x) ? (c.parsed.x > 0 ? "+" : "") + fmtTR(c.parsed.x) + "%" : "—") } } },
        scales: { x: { grid: { color: gridc }, ticks: { color: textc, font: { size: 11 }, callback: (v) => v + "%" } },
          y: { grid: { display: false }, ticks: { color: textc, font: { size: 12, weight: "600" } } } }
      }
    });
  }

  function renderModelPortfolios(report) {
    const host = $("#modelPortfolios"); if (!host) return;
    const list = arr(report.modelPortfolios);
    if (!list.length) { host.innerHTML = inlineEmpty("Model portföy verisi yok."); return; }
    host.innerHTML = list.map((p) => {
      const holds = arr(p.holdings).map((h) =>
        '<span class="pf__chip">' + esc(h.ticker || "—") + (isNum(h.weightPct) ? ' <em>%' + fmtTR(h.weightPct, 0) + "</em>" : "") + "</span>").join("");
      return '<div class="pf">' +
        '<div class="pf__head"><span class="pf__name">' + esc(p.name || p.id || "—") + "</span>" +
          (p.strategy ? '<span class="badge badge--neutral">' + esc(p.strategy) + "</span>" : "") + "</div>" +
        '<div class="pf__metrics">' +
          pfMetric("Değer", isNum(p.valueTL) ? fmtTR(p.valueTL, 0) + " TL" : "—", "flat") +
          pfMetric("Getiri", pctText(p.returnPct), pctClass(p.returnPct)) +
          pfMetric("Alfa", pctText(p.alphaPct), pctClass(p.alphaPct)) +
        "</div>" +
        '<div class="pf__holdings">' + (holds || inlineEmpty("—")) + "</div>" +
      "</div>";
    }).join("");
  }
  function pfMetric(label, val, cls) {
    return '<div class="pf__metric"><span class="pf__ml">' + esc(label) + '</span><span class="pf__mv ' + cls + '">' + esc(val) + "</span></div>";
  }

  /* ---------------- 4c) Anlık giriş portföyü ---------------- */
  function renderInstantEntry(report) {
    const host = $("#instantEntry"); if (!host) return;
    const ie = report.instantEntry;
    if (!ie || typeof ie !== "object") { host.innerHTML = emptyHTML("Anlık giriş verisi yok", "instantEntry alanı üretilmemiş."); return; }
    const tl = (v) => (isNum(v) ? fmtTR(v, 0) + " TL" : "—");
    const kpis = [
      ["Toplam Sermaye", tl(ie.initialCapitalTL), "flat"],
      ["Günlük Alım Hakkı", tl(ie.dailyBudgetTL), "flat"],
      ["Kullanılabilir Nakit", tl(ie.cashTL), "flat"],
      ["Hissede (Güncel)", tl(ie.holdingsValueTL), "flat"],
      ["Toplam Girilen", tl(ie.totalBoughtTL), "flat"],
      ["Kâr-Satışı (Gerçekleşen)", tl(ie.realizedGainTL), pctClass(ie.realizedGainTL)],
      ["Toplam Değer", tl(ie.totalValueTL), "flat"],
      ["Getiri", pctText(ie.totalReturnPct), pctClass(ie.totalReturnPct)]
    ];
    const holds = arr(ie.holdings);
    const holdHtml = holds.length
      ? '<div class="tablewrap"><table class="table"><thead><tr><th>Ticker</th><th>Şirket</th><th style="text-align:right">Değer</th><th style="text-align:right">Ağırlık</th><th style="text-align:right">K/Z %</th></tr></thead><tbody>' +
        holds.map((h) => "<tr><td class='td-ticker'>" + esc(h.ticker || "—") + "</td><td class='td-company'>" + esc(h.company || "") + "</td>" +
          "<td class='td-num'>" + (isNum(h.valueTL) ? fmtTR(h.valueTL, 0) : "—") + "</td>" +
          "<td class='td-num'>" + (isNum(h.weightPct) ? "%" + fmtTR(h.weightPct) : "—") + "</td>" +
          "<td class='td-num " + pctClass(h.gainPct) + "'>" + pctText(h.gainPct) + "</td></tr>").join("") +
        "</tbody></table></div>"
      : inlineEmpty("Açık pozisyon yok.");
    host.innerHTML =
      '<div class="ie__kpis">' + kpis.map((k) => '<div class="ie__kpi"><span class="ie__kl">' + esc(k[0]) + '</span><span class="ie__kv ' + k[2] + '">' + esc(k[1]) + "</span></div>").join("") + "</div>" +
      '<h4 class="ie__subtitle">Açık Pozisyonlar</h4>' + holdHtml +
      (ie.statusNote ? '<p class="ie__note">' + esc(ie.statusNote) + "</p>" : "");
  }

  /* ---------------- 5) Hisse tablosu ---------------- */
  const STOCK_COLS = [
    { key: "ticker", label: "Ticker", type: "str", cls: "td-ticker" },
    { key: "company", label: "Şirket", type: "str", cls: "td-company" },
    { key: "price", label: "Fiyat", type: "num" },
    { key: "dailyPct", label: "Günlük %", type: "num", pct: true },
    { key: "weeklyPct", label: "Haftalık %", type: "num", pct: true },
    { key: "rsi", label: "RSI", type: "num" },
    { key: "macd", label: "MACD", type: "num" },
    { key: "volume", label: "Hacim", type: "str", cls: "td-num" },
    { key: "signal", label: "Sinyal", type: "str", noSort: true },
    { key: "llmNote", label: "YZ Yorum", type: "str", noSort: true, cls: "td-note" },
    { key: "action", label: "Aksiyon", type: "str", noSort: true }
  ];
  let stockState = { rows: [], sortKey: null, sortDir: 1, q: "" };
  function renderPortfolioStocks(report) { // 5. bölüm tablo
    const thead = $("#stockThead"), tbody = $("#stockTbody"), empty = $("#stockEmpty");
    if (!thead || !tbody) return;
    stockState.rows = arr(report.stocks);
    if (!stockState.rows.length) {
      thead.innerHTML = ""; tbody.innerHTML = "";
      if (empty) { empty.hidden = false; empty.innerHTML = emptyHTML("Hisse verisi yok", "stocks alanı üretilmemiş."); }
      return;
    }
    if (empty) empty.hidden = true;
    thead.innerHTML = "<tr>" + STOCK_COLS.map((c) =>
      '<th class="' + (c.noSort ? "no-sort" : "") + '" data-key="' + c.key + '" data-type="' + c.type + '">' +
      esc(c.label) + (c.noSort ? "" : '<span class="arrow">▲</span>') + "</th>").join("") + "</tr>";
    thead.querySelectorAll("th").forEach((th) => {
      if (th.classList.contains("no-sort")) return;
      th.addEventListener("click", () => {
        const k = th.dataset.key;
        if (stockState.sortKey === k) stockState.sortDir *= -1; else { stockState.sortKey = k; stockState.sortDir = 1; }
        drawStockRows();
      });
    });
    drawStockRows();
  }
  function drawStockRows() {
    const tbody = $("#stockTbody"); if (!tbody) return;
    let rows = stockState.rows.slice();
    const q = stockState.q.trim().toLowerCase();
    if (q) rows = rows.filter((r) => ((r.ticker || "") + " " + (r.company || "")).toLowerCase().includes(q));
    if (stockState.sortKey) {
      const col = STOCK_COLS.find((c) => c.key === stockState.sortKey);
      rows.sort((a, b) => {
        let va = a[stockState.sortKey], vb = b[stockState.sortKey];
        if (col && col.type === "num") { va = isNum(va) ? va : -Infinity; vb = isNum(vb) ? vb : -Infinity; return (va - vb) * stockState.sortDir; }
        return String(va == null ? "" : va).localeCompare(String(vb == null ? "" : vb), "tr") * stockState.sortDir;
      });
    }
    $("#stockThead").querySelectorAll("th").forEach((th) => {
      th.classList.remove("sort-asc", "sort-desc");
      if (th.dataset.key === stockState.sortKey) th.classList.add(stockState.sortDir === 1 ? "sort-asc" : "sort-desc");
    });
    if (!rows.length) { tbody.innerHTML = '<tr><td colspan="' + STOCK_COLS.length + '">' + inlineEmpty("Eşleşen hisse yok.") + "</td></tr>"; return; }
    tbody.innerHTML = rows.map((r) => "<tr>" + STOCK_COLS.map((c) => {
      const v = r[c.key];
      if (c.key === "signal") return "<td>" + signalBadge(v) + "</td>";
      if (c.key === "action") return "<td>" + actionBadge(v) + "</td>";
      if (c.type === "num") {
        if (!isNum(v)) return '<td class="td-num flat">—</td>';
        if (c.pct) return '<td class="td-num ' + pctClass(v) + '">' + pctText(v) + "</td>";
        return '<td class="td-num">' + fmtTR(v) + "</td>";
      }
      return '<td class="' + (c.cls || "") + '">' + (has(v) ? esc(v) : '<span class="flat">—</span>') + "</td>";
    }).join("") + "</tr>").join("");
  }
  function signalBadge(s) {
    if (!has(s)) return '<span class="badge badge--neutral">—</span>';
    const u = String(s).toUpperCase();
    let cls = "badge--neutral";
    if (u.includes("AL") && !u.includes("ALMA")) cls = "badge--pos";
    else if (u.includes("SAT") || u.includes("RİSK") || u.includes("RISK")) cls = "badge--neg";
    else if (u.includes("İZLE") || u.includes("IZLE") || u.includes("BEKLE")) cls = "badge--warn";
    return '<span class="badge ' + cls + '">' + esc(s) + "</span>";
  }
  function actionBadge(a) {
    if (!has(a)) return '<span class="badge badge--neutral">—</span>';
    const u = String(a).toLowerCase();
    let cls = "badge--neutral";
    if (u.includes("alım") || u.includes("alim")) cls = "badge--pos";
    else if (u.includes("riskli")) cls = "badge--neg";
    else if (u.includes("izle") || u.includes("bekle")) cls = "badge--warn";
    return '<span class="badge ' + cls + '">' + esc(a) + "</span>";
  }

  /* ---------------- 6a) Sektör rotasyonu — Sankey (tahmini akış) ---------------- */
  let sectorSankey = null;
  let sankeyRegistered = false;
  function renderSectorSankeyChart(report) {
    const wrap = $("#sectorSankey"), empty = $("#sectorSankeyEmpty"); if (!wrap) return;
    const flows = arr(report.sectorFlow);
    const sankeyLib = window["chartjs-chart-sankey"];
    if (!flows.length || typeof window.Chart === "undefined" || !sankeyLib) {
      if (empty) { empty.hidden = false; empty.innerHTML = emptyHTML(
        flows.length ? "Sankey kütüphanesi yüklenemedi" : "Sektör akış verisi yok",
        "En az bir zayıflayan ve bir güçlenen sektör gerekir."); }
      wrap.style.display = "none"; return;
    }
    if (empty) empty.hidden = true; wrap.style.display = "";
    if (!sankeyRegistered) { window.Chart.register(sankeyLib.SankeyController, sankeyLib.Flow); sankeyRegistered = true; }
    const css = getComputedStyle(document.body);
    const negC = css.getPropertyValue("--neg").trim() || "#e5484d";
    const posC = css.getPropertyValue("--pos").trim() || "#1db17a";
    const textc = css.getPropertyValue("--text").trim();
    if (sectorSankey) sectorSankey.destroy();
    // colorFrom/colorTo + colorMode:'gradient' her akışı kaynakta kırmızı, hedefte yeşil
    // olacak şekilde boyar — zayıflayandan güçlenene akış görsel olarak nettir.
    sectorSankey = new window.Chart(wrap.getContext("2d"), {
      type: "sankey",
      data: { datasets: [{
        label: "Rotasyon",
        data: flows.map((f) => ({ from: f.from, to: f.to, flow: f.flow })),
        colorFrom: () => negC, colorTo: () => posC, colorMode: "gradient",
        borderWidth: 0, nodeWidth: 10, nodePadding: 14,
        color: textc, font: { size: 12, family: "inherit" }
      }] },
      options: {
        responsive: true, maintainAspectRatio: false,
        plugins: { legend: { display: false },
          tooltip: { callbacks: { label: (c) => " " + c.raw.from + " → " + c.raw.to } } }
      }
    });
  }

  /* ---------------- 6) Sektör rotasyonu ---------------- */
  let sectorChart = null;
  function renderSectorRotation(report) {
    const wrap = $("#sectorChart"), empty = $("#sectorEmpty"); if (!wrap) return;
    const rows = arr(report.sectorRotation);
    if (!rows.length || typeof window.Chart === "undefined") {
      if (empty) { empty.hidden = false; empty.innerHTML = emptyHTML(
        rows.length ? "Grafik kütüphanesi yüklenemedi" : "Sektör rotasyonu verisi yok",
        "Veri biriktikçe grafik otomatik dolacaktır."); }
      wrap.style.display = "none"; return;
    }
    if (empty) empty.hidden = true; wrap.style.display = "";
    // Backend haftalığa göre azalan sıralı veriyor (en güçlü ilk); Chart.js yatay
    // çubukta dizinin ilk ögesini en üste çizer, bu yüzden sırayı DEĞİŞTİRMEDEN
    // kullanıyoruz — en güçlü sektör en üstte görünür (portföy karşılaştırma
    // grafiğiyle tutarlı).
    const sorted = rows.slice();
    const labels = sorted.map((r) => r.sector || "—");
    const css = getComputedStyle(document.body);
    const textc = css.getPropertyValue("--text-dim").trim();
    const gridc = css.getPropertyValue("--grid-line").trim();
    const hasMonthly = sorted.some((r) => isNum(r.monthlyPct));
    const datasets = [
      { label: "Günlük", data: sorted.map((r) => (isNum(r.dailyPct) ? r.dailyPct : null)), backgroundColor: "#6e8bff", borderRadius: 3, maxBarThickness: 14 },
      { label: "Haftalık", data: sorted.map((r) => (isNum(r.weeklyPct) ? r.weeklyPct : null)), backgroundColor: "#31c48d", borderRadius: 3, maxBarThickness: 14 }
    ];
    if (hasMonthly) datasets.push({ label: "Aylık", data: sorted.map((r) => (isNum(r.monthlyPct) ? r.monthlyPct : null)), backgroundColor: "#f0a23c", borderRadius: 3, maxBarThickness: 14 });
    if (sectorChart) sectorChart.destroy();
    sectorChart = new window.Chart(wrap.getContext("2d"), {
      type: "bar",
      data: { labels: labels, datasets: datasets },
      options: {
        indexAxis: "y", responsive: true, maintainAspectRatio: false,
        plugins: { legend: { display: true, position: "top", labels: { color: textc, boxWidth: 10, font: { size: 11 } } },
          tooltip: { callbacks: { label: (c) => " " + c.dataset.label + ": " + (isNum(c.parsed.x) ? (c.parsed.x > 0 ? "+" : "") + fmtTR(c.parsed.x) + "%" : "—") } } },
        scales: { x: { grid: { color: gridc }, ticks: { color: textc, font: { size: 11 }, callback: (v) => v + "%" } },
          y: { grid: { display: false }, ticks: { color: textc, font: { size: 11.5, weight: "600" } } } }
      }
    });
  }

  /* ---------------- 7) Smart money / para akışı ---------------- */
  function renderSmartMoney(report) {
    const host = $("#smartMoneyList"), cols = $("#strengthLists");
    const sm = report.smartMoney || {};
    if (host) {
      const items = arr(sm.items);
      let html = sm.commentary ? '<p class="flow__commentary">' + esc(sm.commentary) + "</p>" : "";
      if (!items.length && !sm.commentary) html = inlineEmpty("Para akışı verisi yok.");
      else html += items.map((it) => {
        const t = (it.type || "").toLowerCase();
        const cls = t.includes("çıkış") || t.includes("cikis") || t.includes("sat") ? "badge--neg" : "badge--pos";
        return '<div class="flow__item"><span class="flow__tk">' + esc(it.ticker || "—") + "</span>" +
          '<span class="badge ' + cls + '">' + esc(it.type || "—") + "</span>" +
          '<span class="flow__note">' + esc(it.note || "") + "</span></div>";
      }).join("");
      host.innerHTML = html;
    }
    if (cols) {
      const up = arr(sm.strengthening), down = arr(sm.weakening);
      if (!up.length && !down.length) { cols.innerHTML = inlineEmpty("Güç verisi yok."); return; }
      cols.innerHTML =
        '<div><h4>Güçlenenler</h4><div class="chiprow">' +
        (up.length ? up.map((t) => '<span class="badge badge--pos">' + esc(t) + "</span>").join("") : inlineEmpty("—")) + "</div></div>" +
        '<div><h4>Zayıflayanlar</h4><div class="chiprow">' +
        (down.length ? down.map((t) => '<span class="badge badge--neg">' + esc(t) + "</span>").join("") : inlineEmpty("—")) + "</div></div>";
    }
  }

  /* ---------------- 8) Teknik sinyaller ---------------- */
  function renderTechnicalSignals(report) {
    const host = $("#signalGrid"); if (!host) return;
    const t = report.technicalSignals || {};
    const groups = [
      { key: "overbought", title: "Aşırı Alım", cls: "badge--neg", fmt: (x) => (x.ticker || "—") + (isNum(x.rsi) ? " · RSI " + fmtTR(x.rsi, 1) : "") },
      { key: "oversold", title: "Aşırı Satım", cls: "badge--pos", fmt: (x) => (x.ticker || "—") + (isNum(x.rsi) ? " · RSI " + fmtTR(x.rsi, 1) : "") },
      { key: "macdCross", title: "MACD Kesişimleri", cls: "badge--accent", fmt: (x) => (x.ticker || "—") + (x.note ? " · " + x.note : "") },
      { key: "trendStrengthening", title: "Trend Güçlenen", cls: "badge--pos", fmt: (x) => (x.ticker || "—") + (x.note ? " · " + x.note : "") },
      { key: "momentumLosing", title: "Momentum Kaybeden", cls: "badge--warn", fmt: (x) => (x.ticker || "—") + (x.note ? " · " + x.note : "") },
      { key: "breakout", title: "Kırılım / Risk", cls: "badge--accent", fmt: (x) => (x.ticker || "—") + (x.note ? " · " + x.note : "") }
    ];
    const any = groups.some((g) => arr(t[g.key]).length);
    if (!any) { host.innerHTML = inlineEmpty("Teknik sinyal verisi yok."); return; }
    host.innerHTML = groups.map((g) => {
      const items = arr(t[g.key]);
      return '<div class="sigcard"><h4><span class="badge ' + g.cls + '" style="padding:2px 7px">' + items.length + "</span>" + esc(g.title) + "</h4>" +
        (items.length ? "<ul>" + items.map((x) => "<li><b>" + esc(g.fmt(x).split(" · ")[0]) + "</b>" +
          (g.fmt(x).includes(" · ") ? "<span>" + esc(g.fmt(x).split(" · ").slice(1).join(" · ")) + "</span>" : "") + "</li>").join("") + "</ul>"
          : inlineEmpty("—")) + "</div>";
    }).join("");
  }

  /* ---------------- 9) YZ yorumu ---------------- */
  function paragraphsHtml(text) {
    return String(text).split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean)
      .map((p) => "<p>" + esc(p).replace(/\n/g, "<br>") + "</p>").join("");
  }
  function renderLLMCommentary(report) {
    const host = $("#llmCommentary"), stance = $("#llmStance");
    const c = report.llmCommentary || {};
    if (stance) {
      const st = c.stance || (report.summary && report.summary.llmStance);
      stance.className = "stance badge " + stanceToClass(st);
      stance.textContent = has(st) ? st : "—";
    }
    if (!host) return;
    const sections = arr(c.portfolioCommentSections);
    const hasAny = has(c.marketSummary) || has(c.portfolioComment) || sections.length ||
      arr(c.risks).length || arr(c.opportunities).length || arr(c.levels).length || has(c.watchNext);
    if (!hasAny) { host.innerHTML = emptyHTML("Yorum henüz üretilmedi", "Yapay zekâ yorumu yalnız üretildiğinde gösterilir."); return; }
    const list = (items) => arr(items).length ? "<ul>" + arr(items).map((x) => "<li>" + esc(x) + "</li>").join("") + "</ul>" : inlineEmpty("—");

    // Portföy yorumu: bölümlere ayrılmışsa (her model portföy için ayrı başlık + metin)
    // düzenli kartlar olarak göster; yoksa ham metni paragraflara bölerek göster.
    let portfolioHtml = "";
    if (sections.length) {
      portfolioHtml = '<div class="commentary__doc">' +
        (has(c.portfolioCommentTitle) ? '<h4 class="commentary__doctitle">' + esc(c.portfolioCommentTitle) + "</h4>" : "") +
        '<div class="commentary__pfgrid">' +
        sections.map((s) =>
          '<div class="commentary__pf">' +
            (has(s.heading) ? '<h5 class="commentary__pfname">' + esc(s.heading) + "</h5>" : "") +
            paragraphsHtml(s.text || "") +
          "</div>").join("") +
        "</div></div>";
    } else if (has(c.portfolioComment)) {
      portfolioHtml = '<div class="commentary__box"><h4>Portföy Yorumu</h4>' + paragraphsHtml(c.portfolioComment) + "</div>";
    }

    host.innerHTML =
      (has(c.marketSummary) ? '<p class="commentary__lead">' + esc(c.marketSummary) + "</p>" : "") +
      portfolioHtml +
      '<div class="commentary__grid">' +
        '<div class="commentary__box"><h4>Riskler</h4>' + list(c.risks) + "</div>" +
        '<div class="commentary__box"><h4>Fırsatlar</h4>' + list(c.opportunities) + "</div>" +
        '<div class="commentary__box"><h4>İzlenecek Seviyeler</h4>' + list(c.levels) + "</div>" +
        '<div class="commentary__box"><h4>Yarın / Hafta İçin</h4><p>' + (has(c.watchNext) ? esc(c.watchNext) : inlineEmpty("—")) + "</p></div>" +
      "</div>";
  }

  /* ---------------- 10) Aksiyon listesi ---------------- */
  function renderActionItems(report) {
    const host = $("#actionItems"); if (!host) return;
    const a = report.actionItems || {};
    const groups = [
      { key: "watch", title: "Takip Edilecekler" },
      { key: "rebalance", title: "Dengeleme İhtiyacı" },
      { key: "riskReduction", title: "Risk Azaltma" },
      { key: "buyWatchlist", title: "Alım İzleme Listesi" }
    ];
    const any = groups.some((g) => arr(a[g.key]).length);
    if (!any && !has(a.note)) { host.innerHTML = emptyHTML("Aksiyon üretilmedi"); return; }
    host.innerHTML = groups.map((g) =>
      '<div class="action__group"><h4>' + esc(g.title) + "</h4>" +
      (arr(a[g.key]).length ? "<ul>" + arr(a[g.key]).map((x) => "<li>" + esc(x) + "</li>").join("") + "</ul>" : inlineEmpty("Bu başlıkta öğe yok.")) +
      "</div>").join("") +
      '<div class="action__note">' + esc(a.note || "Karar destek amaçlıdır, yatırım tavsiyesi değildir.") + "</div>";
  }

  /* ---------------- Orkestrasyon ---------------- */
  function renderAll(report) {
    try { renderHeader(report); } catch (e) { warn("header", e); }
    try { renderKpiCards(report); } catch (e) { warn("kpi", e); }
    try { renderPerformanceChart(report); } catch (e) { warn("perf", e); }
    try { renderPortfolioTable(report); } catch (e) { warn("alloc", e); }
    try { renderAllocationPies(report); } catch (e) { warn("allocPies", e); }
    try { renderPortfolioCompareChart(report); } catch (e) { warn("pfCompare", e); }
    try { renderModelPortfolios(report); } catch (e) { warn("modelPortfolios", e); }
    try { renderInstantEntry(report); } catch (e) { warn("instantEntry", e); }
    try { renderPortfolioStocks(report); } catch (e) { warn("stocks", e); }
    try { renderSectorSankeyChart(report); } catch (e) { warn("sectorSankey", e); }
    try { renderSectorRotation(report); } catch (e) { warn("sector", e); }
    try { renderSmartMoney(report); } catch (e) { warn("smart", e); }
    try { renderTechnicalSignals(report); } catch (e) { warn("tech", e); }
    try { renderLLMCommentary(report); } catch (e) { warn("llm", e); }
    try { renderActionItems(report); } catch (e) { warn("action", e); }
  }
  function warn(where, e) { if (window.console) console.warn("[panel] " + where + " render hatası:", e); }

  /* ---------------- Veri yükleme (fallback zinciri) ---------------- */
  async function tryFetch(path) {
    try {
      const r = await fetch(path, { cache: "no-store" });
      if (!r.ok) return null;
      // BOM-toleranslı: PowerShell (Set-Content -Encoding UTF8) baştaki UTF-8 BOM'unu
      // ekleyebilir; metni okuyup BOM'u soyarak JSON.parse ile güvenle çözeriz.
      let text = await r.text();
      if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
      const j = JSON.parse(text);
      return j && typeof j === "object" ? j : null;
    } catch (e) { return null; }
  }
  async function loadReport() {
    let report = await tryFetch("./data/latest_report.json");
    let src = "latest_report.json";
    if (!report) { report = await tryFetch("./data/sample_report.json"); src = "sample_report.json"; }
    if (!report) { report = EMBEDDED_SAMPLE; src = "gömülü örnek (sunucusuz)"; }
    // Etiket veri-gerçeğine göre: isSample bayrağı varsa "örnek" de (dosya adından bağımsız).
    const sample = report && report.meta && report.meta.isSample;
    const mode = (sample ? "örnek · " : "canlı · ") + src;
    const fm = $("#footMode"); if (fm) fm.textContent = "· kaynak: " + mode;
    return report;
  }

  /* ---------------- UI davranışları ---------------- */
  function initTheme() {
    const saved = localStorage.getItem("bist-panel-theme");
    if (saved) document.documentElement.setAttribute("data-theme", saved);
    const toggle = () => {
      const cur = document.documentElement.getAttribute("data-theme") === "light" ? "dark" : "light";
      document.documentElement.setAttribute("data-theme", cur);
      localStorage.setItem("bist-panel-theme", cur);
      // grafik renkleri temaya bağlı; yeniden çiz
      if (window.__lastReport__) { try { renderPerformanceChart(window.__lastReport__); renderPortfolioTable(window.__lastReport__); renderAllocationPies(window.__lastReport__); renderPortfolioCompareChart(window.__lastReport__); renderSectorSankeyChart(window.__lastReport__); renderSectorRotation(window.__lastReport__); } catch (e) {} }
    };
    const a = $("#themeToggle"), b = $("#themeToggleMobile");
    if (a) a.addEventListener("click", toggle);
    if (b) b.addEventListener("click", toggle);
  }
  function initNav() {
    const sidebar = $("#sidebar"), scrim = $("#scrim"), toggle = $("#navToggle");
    const close = () => { sidebar && sidebar.classList.remove("is-open"); scrim && scrim.classList.remove("is-open"); };
    if (toggle) toggle.addEventListener("click", () => { sidebar.classList.toggle("is-open"); scrim.classList.toggle("is-open"); });
    if (scrim) scrim.addEventListener("click", close);
    document.querySelectorAll(".nav__item").forEach((it) => it.addEventListener("click", close));
    // scroll-spy
    const sections = Array.prototype.slice.call(document.querySelectorAll("section.block, header#ozet"));
    const items = document.querySelectorAll(".nav__item");
    if ("IntersectionObserver" in window && sections.length) {
      const obs = new IntersectionObserver((entries) => {
        entries.forEach((en) => {
          if (en.isIntersecting) {
            const id = en.target.id;
            items.forEach((i) => i.classList.toggle("is-active", i.dataset.section === id));
          }
        });
      }, { rootMargin: "-45% 0px -50% 0px", threshold: 0 });
      sections.forEach((s) => obs.observe(s));
    }
  }
  function initSearch() {
    const s = $("#stockSearch");
    if (s) s.addEventListener("input", () => { stockState.q = s.value || ""; drawStockRows(); });
  }

  /* ---------------- Başlat ---------------- */
  async function boot() {
    initTheme(); initNav(); initSearch();
    const report = await loadReport();
    window.__lastReport__ = report;
    renderAll(report);
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
