param(
    [switch]$Live
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'BistScanner.Core.psm1'
Import-Module $modulePath -Force

$sample = [pscustomobject]@{
    Symbol = 'TEST'
    Company = 'Test Şirketi'
    TradingViewSymbol = 'BIST:TEST'
    Price = 120.0
    ChangePct = 1.5
    Volume = 2000000.0
    MarketCap = 10000000000.0
    MarketCapBn = 10.0
    PE = 10.0
    PB = 1.2
    ROE = 22.0
    DebtToEquity = 45.0
    DividendYield = 2.0
    Recommendation = 0.5
    RSI = 58.0
    SMA20 = 115.0
    SMA50 = 110.0
    SMA200 = 95.0
    RelativeVolume = 1.4
    VolatilityD = 2.0
    Sector = 'Producer Manufacturing'
    SectorTR = 'Üretici İmalat'
    Industry = 'Test'
    PerfWeek = 2.0
    PerfMonth = 6.0
    Perf3Month = 10.0
    Perf6Month = 15.0
    PerfYear = 30.0
    Perf3Year = 220.0
    Perf5Year = 700.0
    MacdLine = 1.2
    MacdSignal = 0.8
    MacdHistogram = 0.4
    EvEbitda = 5.5
    AverageVolume10D = 1500000.0
    FinancialCurrency = 'TRY'
    FiscalPeriodEnd = [datetime]'2026-03-31'
    LatestReportDate = [datetime]'2026-04-30'
    NextEarningsDate = [datetime]'2026-08-10'
    NetIncomeHistory = @(1200000000, 900000000, 800000000, 700000000, 600000000)
    RevenueHistory = @(10000000000, 9000000000, 8500000000, 8000000000, 7500000000)
    TotalAssetsHistory = @(30000000000, 28000000000, 26000000000, 24000000000, 22000000000)
    TotalDebtHistory = @(5000000000, 4800000000, 4600000000, 4400000000, 4200000000)
    FreeCashFlowHistory = @(1000000000, 800000000, 700000000, 600000000, 500000000)
    EbitdaHistory = @(1800000000, 1500000000, 1400000000, 1300000000, 1000000000)
    EbitdaTRY = 1800000000.0
    EbitdaTRYBn = 1.8
    EbitdaTtmTRY = 6000000000.0
    EbitdaTtmTRYBn = 6.0
    OperatingIncomeTRY = 1000000000.0
    QuarterlyFinancials = @(
        [pscustomobject]@{ Period = '2026/Q1'; NetIncomeTRYBn = 1.2; NetIncomeUSDMn = 27.0; NetIncomeUSD = 27000000.0; RevenueUSD = 225000000.0; EbitdaTRYBn = 1.8; EbitdaUSDMn = 40.0; EbitdaUSD = 40000000.0; FreeCashFlowTRY = 1000000000.0 },
        [pscustomobject]@{ Period = '2025/Q4'; NetIncomeTRYBn = 0.9; NetIncomeUSDMn = 21.0; NetIncomeUSD = 21000000.0; RevenueUSD = 210000000.0; EbitdaTRYBn = 1.5; EbitdaUSDMn = 35.0; EbitdaUSD = 35000000.0; FreeCashFlowTRY = 800000000.0 },
        [pscustomobject]@{ Period = '2025/Q3'; NetIncomeTRYBn = 0.8; NetIncomeUSDMn = 19.0; NetIncomeUSD = 19000000.0; RevenueUSD = 200000000.0; EbitdaTRYBn = 1.4; EbitdaUSDMn = 33.0; EbitdaUSD = 33000000.0; FreeCashFlowTRY = 700000000.0 },
        [pscustomobject]@{ Period = '2025/Q2'; NetIncomeTRYBn = 0.7; NetIncomeUSDMn = 18.0; NetIncomeUSD = 18000000.0; RevenueUSD = 190000000.0; EbitdaTRYBn = 1.3; EbitdaUSDMn = 31.0; EbitdaUSD = 31000000.0; FreeCashFlowTRY = 600000000.0 },
        [pscustomobject]@{ Period = '2025/Q1'; NetIncomeTRYBn = 0.6; NetIncomeUSDMn = 15.0; NetIncomeUSD = 15000000.0; RevenueUSD = 180000000.0; EbitdaTRYBn = 1.0; EbitdaUSDMn = 25.0; EbitdaUSD = 25000000.0; FreeCashFlowTRY = 500000000.0 }
    )
    LatestQuarter = '2026/Q1'
    LatestNetIncomeTRYBn = 1.2
    LatestNetIncomeUSDMn = 27.0
    NetIncomeUsdYoYPct = 80.0
    RevenueUsdYoYPct = 25.0
    LatestEbitdaTRYBn = 1.8
    LatestEbitdaUSDMn = 40.0
    EbitdaUsdYoYPct = 60.0
    PositiveQuarterCount = 5
    PositiveEbitdaQuarterCount = 5
    EbitdaSequentialIncreaseCount = 4
    EbitdaTrendLabel = 'Güçlü'
    StrongUsdEarnings = $true
    StrongUsdEarningsLabel = 'Güçlü'
    UsdEarningsReason = 'örnek güçlü bilanço'
    OperatingIncomeTRYBn = 1.0
    OtherProfitContributionTRY = 200000000.0
    OtherProfitContributionTRYBn = 0.2
    ProfitSourceComponents = @(
        [pscustomobject]@{ Name = 'Faaliyet kârı'; ValueTRY = 1000000000.0; ValueTRYBn = 1.0; SharePct = 83.3; IsNegativeAdjustment = $false },
        [pscustomobject]@{ Name = 'Faaliyet dışı / vergi / değerleme ve diğer'; ValueTRY = 200000000.0; ValueTRYBn = 0.2; SharePct = 16.7; IsNegativeAdjustment = $false }
    )
    ProfitSourceNote = 'örnek mutabakat'
    InflationBenchmarkAsOf = 'Nisan 2026'
    Inflation1YPct = 32.37
    Inflation3YPct = 209.9
    Inflation5YPct = 656.7
    Bist100Perf3Month = 5.0
    Bist100PerfYear = 25.0
    Bist100Perf3Year = 150.0
    Bist100Perf5Year = 600.0
    StockVsInflation1YPct = -2.4
    StockVsInflation3YPct = 10.1
    StockVsInflation5YPct = 43.3
    StockVsBist1YPct = 5.0
    StockVsBist3YPct = 70.0
    StockVsBist5YPct = 100.0
    SectorWatchIndex = 'XUSIN'
    SectorBenchmarkSource = 'Sektör hisse ortalaması proxy'
    SectorStockCount = 20
    SectorIndexPerf3Month = 12.0
    SectorVsBist3Month = 7.0
    SectorRotationLabel = 'BIST Üstü'
    RevenueVsSectorPct = 5.0
    NetIncomeVsSectorPct = 20.0
    EbitdaVsSectorPct = 15.0
    MacroDataNote = 'örnek makro notu'
}

$score = Get-BistScore -Stock $sample -Strategy 'Dengeli'

if ($score.Score -lt 0 -or $score.Score -gt 100) {
    throw "Puan aralık dışında: $($score.Score)"
}

if ([string]::IsNullOrWhiteSpace($score.Explanation)) {
    throw 'Açıklama üretilmedi.'
}

if ($null -eq $score.MacroSectorScore) {
    throw 'Makro/sektör puanı üretilmedi.'
}

if ($score.Explanation -notmatch 'FD/FAVÖK' -or $score.Explanation -notmatch 'Makro/Sektör' -or $score.Explanation -notmatch 'MACD') {
    throw 'Yeni kriterler açıklama metnine girmedi.'
}

if ($score.Symbol -ne 'TEST') {
    throw 'Hisse alanları puanlama sırasında korunmadı.'
}

Write-Host "Çekirdek puanlama testi başarılı. Örnek puan: $($score.Score)"

$may2026LastTradingDay = Get-LastModelPortfolioTradingDay -Month ([datetime]'2026-05-01')
if ($may2026LastTradingDay.Date -ne ([datetime]'2026-05-26').Date) {
    throw "2026 Mayıs son BIST işlem günü yanlış hesaplandı: $may2026LastTradingDay"
}

# --- Invoke-WithRetry: gecici hatadan sonra basarili olmali ---
$script:retryAttempts = 0
$retryResult = Invoke-WithRetry -MaxAttempts 3 -BaseDelaySec 0.01 -OperationName 'birim test' -ScriptBlock {
    $script:retryAttempts++
    if ($script:retryAttempts -lt 3) { throw "gecici $script:retryAttempts" }
    return 'tamam'
}
if ($retryResult -ne 'tamam' -or $script:retryAttempts -ne 3) {
    throw "Invoke-WithRetry tekrar deneme mantigi calismadi: sonuc=$retryResult deneme=$($script:retryAttempts)"
}
$retryThrew = $false
try { Invoke-WithRetry -MaxAttempts 2 -BaseDelaySec 0.01 -ScriptBlock { throw 'her zaman' } | Out-Null }
catch { $retryThrew = $true }
if (-not $retryThrew) { throw 'Invoke-WithRetry tum denemeler bitince istisnayi yeniden firlatmali.' }
Write-Host 'Invoke-WithRetry testi başarılı.'

# --- Update-SignalPerformance: oz-degerlendirme geri-besleme dongusu ---
function New-SignalTestStock { param($Symbol, $Score, $Price) [pscustomobject]@{ Symbol = $Symbol; Score = $Score; Price = $Price } }
$spRun1 = @(
    New-SignalTestStock 'AAA' 95 100
    New-SignalTestStock 'BBB' 90 50
    New-SignalTestStock 'CCC' 60 200
    New-SignalTestStock 'DDD' 30 10
)
$spState1 = Update-SignalPerformance -Previous $null -ScoredStocks $spRun1 -AsOf ([datetime]'2026-06-10T18:15:00') -TopCount 2
if ($spState1.Summary.SampleCount -ne 0) { throw 'Sinyal performansi ilk kosuda 0 ornek vermeliydi.' }
if ($spState1.PendingPicks.Picks.Count -ne 2) { throw "Sinyal performansi 2 ust seçimi kaydetmeliydi: $($spState1.PendingPicks.Picks.Count)" }
# Cache JSON tur-uzeri gidip geldigi icin round-trip ile dogrula.
$spState1Ro = ($spState1 | ConvertTo-Json -Depth 10) | ConvertFrom-Json
$spRun2 = @(
    New-SignalTestStock 'AAA' 92 120
    New-SignalTestStock 'BBB' 88 60
    New-SignalTestStock 'CCC' 55 205
    New-SignalTestStock 'DDD' 25 9
)
$spState2 = Update-SignalPerformance -Previous $spState1Ro -ScoredStocks $spRun2 -AsOf ([datetime]'2026-06-11T18:15:00') -TopCount 2
if ($spState2.Summary.SampleCount -ne 1) { throw "Sinyal performansi 1 degerlendirme uretmeliydi: $($spState2.Summary.SampleCount)" }
if ($spState2.Summary.HitRatePct -ne 100) { throw "Beklenen isabet orani %100, gelen: $($spState2.Summary.HitRatePct)" }
if ($null -eq $spState2.Summary.LastEdgePct -or [double]$spState2.Summary.LastEdgePct -le 0) { throw "Beklenen pozitif getiri avantaji, gelen: $($spState2.Summary.LastEdgePct)" }
$spEmpty = Update-SignalPerformance -Previous $null -ScoredStocks @() -AsOf (Get-Date)
if ($spEmpty.Summary.SampleCount -ne 0) { throw 'Bos evrende sinyal performansi guvenli calismaliydi.' }
Write-Host "Update-SignalPerformance testi başarılı (isabet %$($spState2.Summary.HitRatePct), fark %$($spState2.Summary.LastEdgePct))."

if ($Live) {
    $stocks = @(Invoke-BistStockScan)
    if ($stocks.Count -lt 400) {
        throw "Canlı BIST taraması beklenenden az hisse döndürdü: $($stocks.Count)"
    }

    if (-not ($stocks | Where-Object Symbol -eq 'THYAO')) {
        throw 'Canlı taramada THYAO bulunamadı.'
    }

    $thy = $stocks | Where-Object Symbol -eq 'THYAO' | Select-Object -First 1
    if ($thy.QuarterlyFinancials.Count -lt 5) {
        throw "THYAO için son 5 çeyrek üretilmedi: $($thy.QuarterlyFinancials.Count)"
    }

    if ($null -eq $thy.QuarterlyFinancials[0].NetIncomeUSD) {
        throw 'THYAO için USD kâr dönüşümü üretilemedi.'
    }

    if ([string]::IsNullOrWhiteSpace([string]$thy.SectorTR)) {
        throw 'THYAO için Türkçe sektör adı üretilemedi.'
    }

    if ($null -eq $thy.OperatingIncomeTRY) {
        throw 'THYAO için faaliyet kârı alınamadı.'
    }

    if ($thy.ProfitSourceComponents.Count -lt 2) {
        throw 'THYAO için kâr kaynağı mutabakatı üretilemedi.'
    }

    if ($null -eq $thy.MacdHistogram) {
        throw 'THYAO için MACD histogramı alınamadı.'
    }

    if ($null -eq $thy.EvEbitda) {
        throw 'THYAO için FD/FAVÖK alınamadı.'
    }

    if ($thy.QuarterlyFinancials.Count -ge 1 -and $null -eq $thy.QuarterlyFinancials[0].EbitdaUSD) {
        throw 'THYAO için USD FAVÖK dönüşümü üretilemedi.'
    }

    if ($null -eq $thy.Bist100PerfYear) {
        throw 'BIST100 benchmarkı hisseye iliştirilemedi.'
    }

    $withFiveQuarters = @(
        $stocks | Where-Object {
            $_.QuarterlyFinancials.Count -ge 5 -and
            $null -ne $_.QuarterlyFinancials[4].NetIncomeUSD
        }
    ).Count

    if ($withFiveQuarters -lt 300) {
        throw "Son 5 çeyrek USD kârı bulunan hisse sayısı beklenenden az: $withFiveQuarters"
    }

    $ranked = @(Get-BistScores -Stocks $stocks -Strategy 'Dengeli')
    if ($ranked.Count -ne $stocks.Count) {
        throw 'Puanlanan hisse sayısı canlı hisse sayısıyla eşleşmiyor.'
    }

    $strongUsdCount = @($stocks | Where-Object StrongUsdEarnings).Count
    $portfolioSet = New-ModelPortfolioSet -Stocks $stocks -AsOf ([datetime]'2026-06-04T18:30:00') -InitialCapital 100000
    if ($portfolioSet.Portfolios.Count -ne 4) {
        throw "Dört model portföy oluşturulamadı: $($portfolioSet.Portfolios.Count)"
    }

    foreach ($portfolio in $portfolioSet.Portfolios) {
        if ($portfolio.Holdings.Count -ne 5) {
            throw "$($portfolio.Name) için 5 hisse oluşturulamadı."
        }
        if (@($portfolio.Holdings | Where-Object { [Math]::Abs($_.WeightPct - 20) -gt 0.001 }).Count -gt 0) {
            throw "$($portfolio.Name) başlangıçta eşit ağırlıklı değil."
        }
        if ([Math]::Abs($portfolio.CurrentValueTL - 100000) -gt 0.01) {
            throw "$($portfolio.Name) başlangıç değeri yanlış: $($portfolio.CurrentValueTL)"
        }
        if ($portfolio.Transactions.Count -ne 6) {
            throw "$($portfolio.Name) ilk işlem geçmişi beklenen 6 satırı içermiyor."
        }
        if (@($portfolio.Holdings | Where-Object { $null -eq $_.MacroSectorScore }).Count -gt 0) {
            throw "$($portfolio.Name) makro/sektör skorunu holdinglere taşımadı."
        }
    }

    Write-Host "Canlı BIST testi başarılı. Hisse sayısı: $($stocks.Count), 5 çeyrek USD kârı bulunan: $withFiveQuarters, USD güçlü bilanço: $strongUsdCount, model portföy: $($portfolioSet.Portfolios.Count)"
}
