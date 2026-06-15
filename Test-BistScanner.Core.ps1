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

# --- Momentum 12-1 (Jegadeesh-Titman) ---
$mom = Get-Momentum12_1Pct -Stock ([pscustomobject]@{ PerfYear = 50.0; PerfMonth = 10.0 })
if ([Math]::Abs($mom - 36.3636) -gt 0.05) { throw "Momentum 12-1 yanlis hesaplandi: $mom" }
if ($null -ne (Get-Momentum12_1Pct -Stock ([pscustomobject]@{ PerfYear = $null; PerfMonth = 5.0 }))) {
    throw 'Momentum 12-1, yillik getiri yoksa null donmeli.'
}
Write-Host "Momentum 12-1 testi başarılı ($([Math]::Round($mom, 2))%)."

# --- Akademik cok-faktor skoru (AFS) ---
function New-AfsTestStock {
    param($Symbol, $Ev, $Pb, $Pe, $Roe, $De, $EbTrend, $PerfYear, $PerfMonth, $Vol, $MarketCap)
    [pscustomobject]@{
        Symbol = $Symbol; EvEbitda = $Ev; PB = $Pb; PE = $Pe; ROE = $Roe; DebtToEquity = $De
        EbitdaSequentialIncreaseCount = $EbTrend; PerfYear = $PerfYear; PerfMonth = $PerfMonth
        VolatilityD = $Vol; MarketCap = $MarketCap
    }
}
$afsStocks = @(
    New-AfsTestStock 'GOOD' 4 0.8 6 35 20 4 80 5 1.5 1e9
    New-AfsTestStock 'BAD' 20 5 40 5 200 0 -20 5 5.0 1e11
    New-AfsTestStock 'MID1' 8 1.5 12 18 60 2 25 4 2.5 1e10
    New-AfsTestStock 'MID2' 10 2.0 15 15 80 1 15 3 3.0 2e10
    New-AfsTestStock 'MID3' 6 1.2 9 22 40 3 40 6 2.0 5e9
)
$afsRes = Add-AcademicFactorScore -Stocks $afsStocks
foreach ($r in $afsRes) {
    if ($r.AcademicFactorScore100 -lt 0 -or $r.AcademicFactorScore100 -gt 100) {
        throw "AFS100 aralik disinda: $($r.Symbol) $($r.AcademicFactorScore100)"
    }
}
$afsGood = $afsRes | Where-Object Symbol -eq 'GOOD'
$afsBad = $afsRes | Where-Object Symbol -eq 'BAD'
if ($afsGood.AcademicFactorScore100 -le $afsBad.AcademicFactorScore100) {
    throw "AFS: güçlü faktör profili zayıfı geçmeliydi (GOOD=$($afsGood.AcademicFactorScore100), BAD=$($afsBad.AcademicFactorScore100))."
}
if ($null -eq $afsGood.AnnualizedVolatilityPct -or $null -eq $afsGood.RiskAdjustedMomentum) {
    throw 'AFS yardimci metrikleri (yillik vol / getiri-risk) uretilmedi.'
}
[void](Add-AcademicFactorScore -Stocks @())
Write-Host "Add-AcademicFactorScore testi başarılı (GOOD=$($afsGood.AcademicFactorScore100), BAD=$($afsBad.AcademicFactorScore100))."

# --- Dinamik enflasyon (EVDS TUFE endeksi -> 1Y/3Y/5Y birikimli) ---
# Aylik endeks noktalari (eskiden yeniye). 61 nokta: t-60 ... t.
$cpiPoints = @(0..60 | ForEach-Object { [pscustomobject]@{ Date = "m$_"; Value = 100.0 * [Math]::Pow(1.02, $_) } })
$infl = Get-CumulativeInflationFromIndexPoints -Points $cpiPoints -AsOfText 'test'
# 12 ayda %2 aylik bilesik -> (1.02^12 -1)*100 ~ %26.82
if ([Math]::Abs($infl.Inflation1YPct - 26.82) -gt 0.1) { throw "1Y enflasyon yanlis: $($infl.Inflation1YPct)" }
# 36 ay -> (1.02^36 -1)*100 ~ %103.9 ; 60 ay -> (1.02^60 -1)*100 ~ %228.0
if ([Math]::Abs($infl.Inflation3YPct - 103.9) -gt 0.5) { throw "3Y enflasyon yanlis: $($infl.Inflation3YPct)" }
if ([Math]::Abs($infl.Inflation5YPct - 228.0) -gt 0.5) { throw "5Y enflasyon yanlis: $($infl.Inflation5YPct)" }
# Yetersiz veri -> null
if ($null -ne (Get-CumulativeInflationFromIndexPoints -Points @([pscustomobject]@{ Date = 'a'; Value = 100 }))) {
    throw 'Yetersiz noktada null donmeliydi.'
}
# Fallback: EVDS anahtari yoksa statik benchmark'a dusmeli (1Y = 32.37)
$savedKey = $env:BIST_EVDS_API_KEY
$env:BIST_EVDS_API_KEY = ''
$fallback = Resolve-InflationBenchmark -AsOf ([datetime]'2026-06-15')
if ($null -eq $fallback -or [Math]::Abs([double]$fallback.Inflation1YPct - 32.37) -gt 0.001) {
    throw "Enflasyon fallback statik degere dusmedi: $($fallback.Inflation1YPct)"
}
if ($null -ne $savedKey) { $env:BIST_EVDS_API_KEY = $savedKey } else { Remove-Item Env:\BIST_EVDS_API_KEY -ErrorAction SilentlyContinue }
Write-Host "Dinamik enflasyon testi başarılı (1Y=$($infl.Inflation1YPct)% 3Y=$($infl.Inflation3YPct)% 5Y=$($infl.Inflation5YPct)%; fallback OK)."

# --- Bilanço sürprizi proxy'si ---
$surpriseStrong = Get-EarningsSurpriseScore -Stock ([pscustomobject]@{ NetIncomeUsdYoYPct = 80; EbitdaUsdYoYPct = 60; EbitdaSequentialIncreaseCount = 4; PositiveQuarterCount = 5 })
$surpriseWeak = Get-EarningsSurpriseScore -Stock ([pscustomobject]@{ NetIncomeUsdYoYPct = -50; EbitdaUsdYoYPct = -40; EbitdaSequentialIncreaseCount = 0; PositiveQuarterCount = 1 })
if ($surpriseStrong -le 55 -or $surpriseWeak -ge 45) { throw "Bilanço sürprizi skoru yanlis: strong=$surpriseStrong weak=$surpriseWeak" }
if ($null -ne (Get-EarningsSurpriseScore -Stock ([pscustomobject]@{ NetIncomeUsdYoYPct = $null; EbitdaUsdYoYPct = $null; EbitdaSequentialIncreaseCount = $null; PositiveQuarterCount = $null }))) {
    throw 'Bilanço sürprizi verisi yoksa null donmeli.'
}
Write-Host "Bilanço sürprizi testi başarılı (güçlü=$surpriseStrong, zayıf=$surpriseWeak)."

# --- Add-EarningsTiming ---
$etStocks = @(
    [pscustomobject]@{ Symbol = 'AAA'; Price = 100; NextEarningsDate = [datetime]'2026-06-18'; LatestReportDate = [datetime]'2026-06-13'; NetIncomeUsdYoYPct = 80; EbitdaUsdYoYPct = 60; EbitdaSequentialIncreaseCount = 4; PositiveQuarterCount = 5 }
)
[void](Add-EarningsTiming -Stocks $etStocks -AsOf ([datetime]'2026-06-15'))
$etA = $etStocks | Where-Object Symbol -eq 'AAA'
if ($etA.DaysToNextEarnings -ne 3 -or $etA.DaysSinceLastReport -ne 2 -or $null -eq $etA.EarningsSurpriseScore) {
    throw "Add-EarningsTiming yanlis: dNext=$($etA.DaysToNextEarnings) dLast=$($etA.DaysSinceLastReport)"
}
Write-Host "Add-EarningsTiming testi başarılı."

# --- Bilanço öncesi run-up + sell-the-news bayrakları ve skor ayarı ---
$preRunStock = [pscustomobject]@{ Symbol = 'PRE'; Price = 120; SMA20 = 110; SMA50 = 100; RelativeVolume = 1.4; PerfMonth = 8; MacdHistogram = 0.5; RSI = 60
    NextEarningsDate = [datetime]'2026-06-30'; LatestReportDate = [datetime]'2026-03-31'; NetIncomeUsdYoYPct = 40; EbitdaUsdYoYPct = 30; EbitdaSequentialIncreaseCount = 3; PositiveQuarterCount = 5 }
$sellNewsStock = [pscustomobject]@{ Symbol = 'SLL'; Price = 130; SMA20 = 110; SMA50 = 100; RelativeVolume = 1.2; PerfMonth = 20; MacdHistogram = 0.5; RSI = 72
    NextEarningsDate = [datetime]'2026-09-30'; LatestReportDate = [datetime]'2026-06-12'; NetIncomeUsdYoYPct = 90; EbitdaUsdYoYPct = 70; EbitdaSequentialIncreaseCount = 4; PositiveQuarterCount = 5 }
[void](Add-EarningsTiming -Stocks @($preRunStock, $sellNewsStock) -AsOf ([datetime]'2026-06-15'))
if (-not $preRunStock.PreEarningsRunupActive) { throw 'PRE: bilanço öncesi run-up bayrağı bekleniyordu.' }
if ($sellNewsStock.PreEarningsRunupActive) { throw 'SLL: run-up bayrağı beklenmiyordu (bilanço uzak).' }
if (-not $sellNewsStock.SellTheNewsRisk) { throw 'SLL: sell-the-news riski bekleniyordu.' }
if ($preRunStock.SellTheNewsRisk) { throw 'PRE: sell-the-news beklenmiyordu (yeni açıklama yok).' }
if ((Get-EarningsTimingAdjustment -Stock $preRunStock) -ne 3) { throw "PRE skor ayarı +3 olmaliydi: $(Get-EarningsTimingAdjustment -Stock $preRunStock)" }
if ((Get-EarningsTimingAdjustment -Stock $sellNewsStock) -ne -3) { throw "SLL skor ayarı -3 olmaliydi: $(Get-EarningsTimingAdjustment -Stock $sellNewsStock)" }
# Skora yansima: run-up bonusu skoru yukseltmeli
$baseTiming = (Get-BistScore -Stock $sample -Strategy 'Dengeli').Score
$runupSample = $sample.PSObject.Copy()
$runupSample | Add-Member -NotePropertyName PreEarningsRunupActive -NotePropertyValue $true -Force
$runupScore = (Get-BistScore -Stock $runupSample -Strategy 'Dengeli').Score
if (-not ($runupScore -gt $baseTiming)) { throw "Run-up bonusu skora yansimadi: base=$baseTiming runup=$runupScore" }
Write-Host "Bilanço öncesi ivme / sell-the-news testi başarılı (bonus base=$baseTiming -> $runupScore)."

# --- Bilanço yakınlığı skora (Get-BistScore üzerinden risk cezası) ---
$baseScore = (Get-BistScore -Stock $sample -Strategy 'Dengeli').Score
$nearSample = $sample.PSObject.Copy()
$nearSample | Add-Member -NotePropertyName DaysToNextEarnings -NotePropertyValue 3 -Force
$nearScore = (Get-BistScore -Stock $nearSample -Strategy 'Dengeli').Score
if (-not ($nearScore -lt $baseScore)) {
    throw "Bilanço yakınlığı cezası skora yansimadi: base=$baseScore near=$nearScore"
}
Write-Host "Bilanço yakınlığı ceza testi başarılı (base=$baseScore -> near=$nearScore)."

# --- Add-DataQualityAssessment ---
$dqStocks = @(
    [pscustomobject]@{ Symbol = 'OK'; Price = 100; PE = 10; PB = 1; ROE = 20; DaysSinceLastReport = 40; AverageVolume10D = 1000000 }
    [pscustomobject]@{ Symbol = 'BADP'; Price = 0; PE = 10; PB = 1; ROE = 20; DaysSinceLastReport = 40; AverageVolume10D = 1000000 }
    [pscustomobject]@{ Symbol = 'ILQ'; Price = 100; PE = $null; PB = $null; ROE = $null; DaysSinceLastReport = 200; AverageVolume10D = 10000 }
)
[void](Add-DataQualityAssessment -Stocks $dqStocks -AsOf ([datetime]'2026-06-15'))
if (-not ($dqStocks | Where-Object Symbol -eq 'OK').DataQualityOk) { throw 'Veri kalitesi: OK temiz olmaliydi.' }
if (($dqStocks | Where-Object Symbol -eq 'BADP').DataQualityOk) { throw 'Veri kalitesi: sıfır fiyat kritik olmaliydi.' }
if (($dqStocks | Where-Object Symbol -eq 'ILQ').DataQualityOk) { throw 'Veri kalitesi: illikit kritik olmaliydi.' }
Write-Host "Add-DataQualityAssessment testi başarılı."

# --- PEAD (Update-EarningsReactions) iki kosu ---
function New-PeadStock { param($Sym, $Price, $Since, $ReportDate, $Yoy)
    [pscustomobject]@{ Symbol = $Sym; Price = $Price; DaysSinceLastReport = $Since; LatestReportDate = $ReportDate; NetIncomeUsdYoYPct = $Yoy; EbitdaUsdYoYPct = $Yoy; EbitdaSequentialIncreaseCount = 4; PositiveQuarterCount = 5 } }
$peadR1 = @(New-PeadStock 'AAA' 100 1 ([datetime]'2026-06-14') 90; New-PeadStock 'GGG' 200 1 ([datetime]'2026-06-14') -60)
[void](Add-EarningsTiming -Stocks $peadR1 -AsOf ([datetime]'2026-06-15'))
$peadS1 = Update-EarningsReactions -Previous $null -Stocks $peadR1 -AsOf ([datetime]'2026-06-15')
if ($peadS1.Summary.TrackedCount -ne 2) { throw "PEAD ilk kosu izleme: $($peadS1.Summary.TrackedCount)" }
$peadS1Ro = ($peadS1 | ConvertTo-Json -Depth 10) | ConvertFrom-Json
$peadR2 = @(New-PeadStock 'AAA' 115 35 ([datetime]'2026-06-14') 90; New-PeadStock 'GGG' 220 35 ([datetime]'2026-06-14') -60)
[void](Add-EarningsTiming -Stocks $peadR2 -AsOf ([datetime]'2026-07-15'))
$peadS2 = Update-EarningsReactions -Previous $peadS1Ro -Stocks $peadR2 -AsOf ([datetime]'2026-07-15')
if ($peadS2.Summary.CompletedCount -ne 2 -or $peadS2.Summary.PeadHitRatePct -ne 50) {
    throw "PEAD ikinci kosu: completed=$($peadS2.Summary.CompletedCount) hit=$($peadS2.Summary.PeadHitRatePct)"
}
Write-Host "PEAD (Update-EarningsReactions) testi başarılı (isabet %$($peadS2.Summary.PeadHitRatePct))."

# --- KAP best-effort: ag yoksa/erisilmezse bos doner, hata firlatmaz ---
$kapList = @(Get-KapDisclosures -TimeoutSec 3)
Write-Host "Get-KapDisclosures testi başarılı (best-effort, $($kapList.Count) kayıt, hata yok)."

# --- Kendini ogrenen sinyal kalibrasyonu ---
# Yetersiz ornek -> varsayilan (-5).
$calInsufficient = Update-SignalCalibration -Reactions ([pscustomobject]@{ Completed = @() }) -AsOf ([datetime]'2026-06-15')
if ($calInsufficient.Calibrated -or $calInsufficient.PostEarningsAdjustment -ne -3.0) {
    throw "Yetersiz örnekte varsayılan kalibrasyon bekleniyordu: $($calInsufficient.PostEarningsAdjustment)"
}
# Yeterli ornek, pozitif surprizliler geri vermis (sell-the-news) -> negatif ayar.
$completedNeg = @(1..35 | ForEach-Object {
        $sp = if ($_ % 2 -eq 0) { 70 } else { 30 }
        $drift = if ($_ % 2 -eq 0) { -6 } else { 2 }
        [pscustomobject]@{ SurpriseScore = $sp; DriftPct = $drift; Directional = $true }
    })
$calNeg = Update-SignalCalibration -Reactions ([pscustomobject]@{ Completed = $completedNeg }) -AsOf ([datetime]'2026-06-15')
if (-not $calNeg.Calibrated) { throw 'Yeterli örnekte kalibrasyon bekleniyordu.' }
if ($calNeg.PostEarningsAdjustment -ge 0) { throw "Sell-the-news verisinde negatif ayar bekleniyordu: $($calNeg.PostEarningsAdjustment)" }
# Yeterli ornek, pozitif surprizliler yukselmis (PEAD) -> pozitif ayar.
$completedPos = @(1..35 | ForEach-Object {
        $sp = if ($_ % 2 -eq 0) { 70 } else { 30 }
        $drift = if ($_ % 2 -eq 0) { 8 } else { -2 }
        [pscustomobject]@{ SurpriseScore = $sp; DriftPct = $drift; Directional = $true }
    })
$calPos = Update-SignalCalibration -Reactions ([pscustomobject]@{ Completed = $completedPos }) -AsOf ([datetime]'2026-06-15')
if ($calPos.PostEarningsAdjustment -le 0) { throw "PEAD verisinde pozitif ayar bekleniyordu: $($calPos.PostEarningsAdjustment)" }
# Set/Get + skora yansima: kalibre edilmis pozitif ayar sell-the-news bayrakli hisseyi yukseltir.
Set-SignalCalibration -Calibration $calPos
$adjStock = [pscustomobject]@{ SellTheNewsRisk = $true; PreEarningsRunupActive = $false }
if ((Get-EarningsTimingAdjustment -Stock $adjStock) -le 0) { throw 'Kalibre pozitif ayar skor ayarina yansimadi.' }
Set-SignalCalibration -Calibration $null  # varsayilana don (digerlerini etkilemesin)
Write-Host "Sinyal kalibrasyonu testi başarılı (sell-the-news=$($calNeg.PostEarningsAdjustment), PEAD=$($calPos.PostEarningsAdjustment))."

# --- Model portfoy BIST100 alfa takibi ---
$pfAlpha = [pscustomobject]@{
    Id = 'ALPHATEST'; Name = 'Alpha Test'; Strategy = 'Dengeli'; RankBy = 'Score'
    InitialCapitalTL = 100000; CurrentValueTL = 100000; TotalGainTL = 0; TotalReturnPct = 0
    StartDate = '2026-06-01T00:00:00'; LastRebalancePeriodEnd = '2026-05-26'
    BenchmarkStartLevel = 10000
    Holdings = @([pscustomobject]@{ Symbol = 'ALP'; Company = 'Alp'; SectorTR = 'Test'; Quantity = 1000; CostBasisTL = 100000; CurrentPrice = 100; RebalancePrice = 100; StrategyScore = 90; MacroSectorScore = 50; EvEbitda = 5; SelectionReason = 't' })
    Transactions = @()
}
$pfSet = [pscustomobject]@{ Version = 1; InitialCapitalPerPortfolioTL = 100000; Portfolios = @($pfAlpha) }
$alphaStocks = @([pscustomobject]@{ Symbol = 'ALP'; Price = 110 })   # +%10
$alphaOut = Update-ModelPortfolioSet -PortfolioSet $pfSet -Stocks $alphaStocks -AsOf ([datetime]'2026-06-15T18:15:00') -BenchmarkLevel 10500  # BIST +%5
$p0 = $alphaOut.Portfolios[0]
if ([Math]::Abs([double]$p0.TotalReturnPct - 10) -gt 0.05) { throw "Portföy getirisi yanlis: $($p0.TotalReturnPct)" }
if ([Math]::Abs([double]$p0.BenchmarkReturnPct - 5) -gt 0.05) { throw "BIST100 getirisi yanlis: $($p0.BenchmarkReturnPct)" }
if ([Math]::Abs([double]$p0.AlphaPct - 5) -gt 0.05) { throw "Alfa yanlis: $($p0.AlphaPct)" }
# Backfill: BenchmarkStartLevel yoksa guncel seviyeden baslar -> alfa = portfoy getirisi
$pfNoBench = $pfAlpha.PSObject.Copy()
$pfNoBench.PSObject.Properties.Remove('BenchmarkStartLevel')
$pfSet2 = [pscustomobject]@{ Version = 1; InitialCapitalPerPortfolioTL = 100000; Portfolios = @($pfNoBench) }
$alphaOut2 = Update-ModelPortfolioSet -PortfolioSet $pfSet2 -Stocks $alphaStocks -AsOf ([datetime]'2026-06-15T18:15:00') -BenchmarkLevel 10500
$p0b = $alphaOut2.Portfolios[0]
if ([Math]::Abs([double]$p0b.BenchmarkReturnPct - 0) -gt 0.05) { throw "Backfill BIST100 getirisi 0 olmaliydi: $($p0b.BenchmarkReturnPct)" }
Write-Host "Model portföy alfa testi başarılı (getiri %$($p0.TotalReturnPct), BIST100 %$($p0.BenchmarkReturnPct), alfa %$($p0.AlphaPct))."

# --- Drawdown: deger duserse maks dusus negatif olur ---
$pfDD = [pscustomobject]@{
    Id = 'DD'; Name = 'DD'; Strategy = 'Dengeli'; RankBy = 'Score'
    InitialCapitalTL = 100000; CurrentValueTL = 100000; TotalReturnPct = 0; PeakValueTL = 120000; LastRebalancePeriodEnd = '2026-05-26'
    Holdings = @([pscustomobject]@{ Symbol = 'DDX'; Company = 'D'; SectorTR = 'T'; Quantity = 1000; CostBasisTL = 100000; CurrentPrice = 100; RebalancePrice = 100; StrategyScore = 80; MacroSectorScore = 50; EvEbitda = 5; SelectionReason = 't' })
    Transactions = @()
}
$ddSet = [pscustomobject]@{ Version = 1; InitialCapitalPerPortfolioTL = 100000; Portfolios = @($pfDD) }
$ddStocks = @([pscustomobject]@{ Symbol = 'DDX'; Price = 90 })   # zirve 120k, deger 90k -> dusus -%25
$ddOut = Update-ModelPortfolioSet -PortfolioSet $ddSet -Stocks $ddStocks -AsOf ([datetime]'2026-06-15T18:15:00')
$pdd = $ddOut.Portfolios[0]
if ([Math]::Abs([double]$pdd.CurrentDrawdownPct - (-25)) -gt 0.05) { throw "Guncel drawdown yanlis: $($pdd.CurrentDrawdownPct)" }
if ([double]$pdd.MaxDrawdownPct -gt -25 + 0.05) { throw "Maks drawdown <= -25 olmaliydi: $($pdd.MaxDrawdownPct)" }
Write-Host "Drawdown testi başarılı (guncel %$($pdd.CurrentDrawdownPct), maks %$($pdd.MaxDrawdownPct))."

# --- Islem maliyeti: giris ve rebalance maliyeti dusulur ($sample klonlariyla) ---
$costStocks = @(0..6 | ForEach-Object {
        $c = $sample.PSObject.Copy()
        $c.Symbol = "CST$_"
        $c.Company = "Cost $_"
        $c.Price = 100.0 + $_
        $c.VolatilityD = 1.0 + $_
        $c
    })
$costSet0 = New-ModelPortfolioSet -Stocks $costStocks -AsOf ([datetime]'2026-05-26T18:30:00') -InitialCapital 100000 -BenchmarkLevel 10000 -CostBps 50
$cp0 = $costSet0.Portfolios[0]
if (-not ([double]$cp0.CurrentValueTL -lt 100000)) { throw "Giris maliyeti uygulanmadi: $($cp0.CurrentValueTL)" }
if (-not ([double]$cp0.CumulativeModelCostsTL -gt 0)) { throw "Kumulatif maliyet 0 (giris): $($cp0.CumulativeModelCostsTL)" }
$riskBalanced = @($costSet0.Portfolios | Where-Object Id -eq 'RiskDengeli')[0]
if ($null -eq $riskBalanced) { throw 'RiskDengeli portföy oluşturulamadı.' }
$normalWeightIssues = @(
    $costSet0.Portfolios |
        Where-Object { $_.Id -ne 'RiskDengeli' } |
        ForEach-Object { $_.Holdings } |
        Where-Object { [Math]::Abs([double]$_.WeightPct - 20.0) -gt 0.01 }
)
if ($normalWeightIssues.Count -gt 0) { throw 'Normal model portföylerde eşit ağırlık bozuldu.' }
$riskWeightSum = ($riskBalanced.Holdings | Measure-Object -Property WeightPct -Sum).Sum
if ([Math]::Abs([double]$riskWeightSum - 100.0) -gt 0.05) { throw "RiskDengeli ağırlık toplamı 100 değil: $riskWeightSum" }
$riskNonEqual = @($riskBalanced.Holdings | Where-Object { [Math]::Abs([double]$_.WeightPct - 20.0) -gt 0.01 }).Count
if ($riskNonEqual -eq 0) { throw 'RiskDengeli portföy eşit ağırlıktan ayrışmadı.' }
$costSet1 = Update-ModelPortfolioSet -PortfolioSet $costSet0 -Stocks $costStocks -AsOf ([datetime]'2026-06-30T18:30:00') -AllowRebalance -BenchmarkLevel 10500 -CostBps 50
$cp1 = $costSet1.Portfolios[0]
if (-not ([double]$cp1.CumulativeModelCostsTL -ge [double]$cp0.CumulativeModelCostsTL)) { throw "Rebalance maliyeti birikmedi: $($cp1.CumulativeModelCostsTL)" }
Write-Host "İşlem maliyeti ve RiskDengeli portföy testi başarılı (giriş maliyeti $($cp0.CumulativeModelCostsTL) TL, rebalance sonrası $($cp1.CumulativeModelCostsTL) TL)."

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
    if ($portfolioSet.Portfolios.Count -ne 6) {
        throw "Altı model portföy oluşturulamadı: $($portfolioSet.Portfolios.Count)"
    }

    foreach ($portfolio in $portfolioSet.Portfolios) {
        if ($portfolio.Holdings.Count -ne 5) {
            throw "$($portfolio.Name) için 5 hisse oluşturulamadı."
        }
        if ($portfolio.Id -ne 'RiskDengeli' -and @($portfolio.Holdings | Where-Object { [Math]::Abs($_.WeightPct - 20) -gt 0.001 }).Count -gt 0) {
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
