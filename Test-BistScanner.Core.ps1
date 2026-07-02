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

# --- Strateji-spesifik portföy ayrışması: Momentum vs Değer aynı havuzdan farklı seçmeli ---
# Tam-donanımlı $sample'dan momentum-güçlü ve değer-güçlü sentetik hisseler türet.
function New-StratTestStock {
    param([string]$Symbol, [string]$Sector, [double]$EvEbitda, [double]$PE, [double]$PB,
        [double]$PerfWeek, [double]$PerfMonth, [double]$RSI, [double]$MacdHist)
    $s = $sample | Select-Object *
    $s.Symbol = $Symbol
    $s.Sector = $Sector
    $s.SectorTR = $Sector
    $s.EvEbitda = $EvEbitda
    $s.PE = $PE
    $s.PB = $PB
    $s.PerfWeek = $PerfWeek
    $s.PerfMonth = $PerfMonth
    $s.RSI = $RSI
    $s.MacdHistogram = $MacdHist
    $s.MacdLine = $(if ($MacdHist -ge 0) { 1.2 } else { -0.5 })
    $s.MacdSignal = 0.8
    return $s
}
$stratStocks = @(
    # Momentum-güçlü: yüksek perf/RSI/MACD, zayıf (ama uygun) değer (EvEbitda ~11)
    (New-StratTestStock 'MOM1' 'Sektör A' 11 14 1.4 8 26 63 0.6)
    (New-StratTestStock 'MOM2' 'Sektör B' 11 14 1.4 7 23 62 0.6)
    (New-StratTestStock 'MOM3' 'Sektör C' 11 14 1.4 7 21 61 0.5)
    (New-StratTestStock 'MOM4' 'Sektör D' 11 14 1.4 6 19 60 0.5)
    (New-StratTestStock 'MOM5' 'Sektör E' 11 14 1.4 6 17 59 0.4)
    # Değer-güçlü: güçlü değer (düşük EvEbitda/PE/PB), zayıf momentum (düşük perf/RSI/MACD-)
    (New-StratTestStock 'VAL1' 'Sektör F' 3.0 6 0.8 1 2 45 -0.3)
    (New-StratTestStock 'VAL2' 'Sektör G' 3.2 6 0.8 1 2 45 -0.3)
    (New-StratTestStock 'VAL3' 'Sektör H' 3.5 7 0.9 2 3 46 -0.2)
    (New-StratTestStock 'VAL4' 'Sektör I' 3.8 7 0.9 2 3 47 -0.2)
    (New-StratTestStock 'VAL5' 'Sektör J' 4.0 8 0.9 2 3 48 -0.2)
)
$momTop = @(Get-ModelPortfolioSelection -Stocks $stratStocks -Strategy 'Momentum' -Count 5 | ForEach-Object { [string]$_.Symbol })
$valTop = @(Get-ModelPortfolioSelection -Stocks $stratStocks -Strategy 'Değer' -Count 5 | ForEach-Object { [string]$_.Symbol })
$momHits = @($momTop | Where-Object { $_ -like 'MOM*' }).Count
$valHits = @($valTop | Where-Object { $_ -like 'VAL*' }).Count
$overlap = @($momTop | Where-Object { $valTop -contains $_ }).Count
if ($momHits -lt 4) { throw "Momentum portföyü momentum hisselerini öne çıkarmadı: $($momTop -join ', ')" }
if ($valHits -lt 4) { throw "Değer portföyü değer hisselerini öne çıkarmadı: $($valTop -join ', ')" }
if ($overlap -ge 3) { throw "Momentum ve Değer portföyleri hâlâ büyük ölçüde örtüşüyor (kesişim=$overlap): $($momTop -join ', ') vs $($valTop -join ', ')" }
Write-Host "Strateji ayrışma testi başarılı (Momentum=$($momTop -join ','); Değer=$($valTop -join ','); kesişim=$overlap)."

# --- Sektör yoğunlaşma tavanı (Get-SectorCappedWeights) ---
# 5 isim eşit ağırlık (%20); ikisi aynı sektör (%40). Tavan %35 -> o sektör %35'e
# inmeli, serbest kalan %5 diğer isimlere dağılmalı, toplam %100 korunmalı.
$capW = @{ S1 = 0.2; S2 = 0.2; S3 = 0.2; S4 = 0.2; S5 = 0.2 }
$capM = @{ S1 = 'Banka'; S2 = 'Banka'; S3 = 'Demir-Çelik'; S4 = 'Gıda'; S5 = 'Enerji' }
$capped = & (Get-Module 'BistScanner.Core') {
    param($w, $m) Get-SectorCappedWeights -Weights $w -SectorMap $m -SectorMaxWeight 0.35
} $capW $capM
$bankaTotal = [double]$capped['S1'] + [double]$capped['S2']
$capSum = 0.0; foreach ($k in $capped.Keys) { $capSum += [double]$capped[$k] }
if ($bankaTotal -gt 0.3501) { throw "Sektör tavanı uygulanmadı: Banka ağırlığı %$([Math]::Round($bankaTotal*100,2)) > %35" }
if ([Math]::Abs($capSum - 1.0) -gt 1e-6) { throw "Sektör tavanı sonrası ağırlık toplamı 1 değil: $capSum" }
if ([double]$capped['S3'] -le 0.2 -or [double]$capped['S4'] -le 0.2) { throw "Serbest kalan ağırlık tavan-altı isimlere dağıtılmadı." }
# Tek sektör tavanı aşmıyorsa ağırlıklar değişmemeli (idempotent / no-op).
$noopW = @{ A = 0.34; B = 0.33; C = 0.33 }
$noopM = @{ A = 'X'; B = 'Y'; C = 'Z' }
$noop = & (Get-Module 'BistScanner.Core') {
    param($w, $m) Get-SectorCappedWeights -Weights $w -SectorMap $m -SectorMaxWeight 0.35
} $noopW $noopM
if ([Math]::Abs([double]$noop['A'] - 0.34) -gt 1e-9) { throw "Tavan altı portföy gereksiz yere değişti." }
Write-Host "Sektör yoğunlaşma tavanı testi başarılı (Banka %$([Math]::Round($bankaTotal*100,2)) ≤ %35, toplam=%$([Math]::Round($capSum*100,2)))."

# --- Ay-sonu rebalance saat dilimi (BIST piyasa saati = UTC+3) ---
# CI runner UTC; 18:15 Istanbul = 15:15 UTC. Get-BistMarketNow UTC -> Istanbul cevirir.
$mn = Get-BistMarketNow -ReferenceUtc ([datetime]::new(2026, 6, 30, 15, 15, 0))
if ($mn.Hour -ne 18 -or $mn.Minute -ne 15 -or $mn.Day -ne 30) { throw "Piyasa saati çevrimi yanlış: $($mn.ToString('o')) (beklenen 30.06 18:15)" }
# Son işlem günü (30 Haziran Salı) piyasa saatiyle: 18:15 -> bu ay-sonu (rebalance); 15:15 (UTC, eski hata) -> önceki ay.
$lcMarket = & (Get-Module 'BistScanner.Core') { Get-LatestCompletedModelPortfolioPeriodEnd -AsOf ([datetime]'2026-06-30T18:15:00') }
$lcUtcBug = & (Get-Module 'BistScanner.Core') { Get-LatestCompletedModelPortfolioPeriodEnd -AsOf ([datetime]'2026-06-30T15:15:00') }
if ($lcMarket.ToString('yyyy-MM-dd') -ne '2026-06-30') { throw "Piyasa saatiyle son tamamlanan dönem 2026-06-30 olmalı, çıkan: $($lcMarket.ToString('yyyy-MM-dd'))" }
if ($lcUtcBug.Month -ne 5) { throw "UTC saatiyle (eski hata) önceki ay dönmeliydi (regresyon kontrolü), çıkan: $($lcUtcBug.ToString('yyyy-MM-dd'))" }
# Rebalance tetikleme: 11 Haziran'da kurulan portföy, 30 Haziran piyasa-saati kapanışında rebalance olmalı.
if (-not ([datetime]'2026-06-11' -lt $lcMarket)) { throw "11 Haziran < 30 Haziran ay-sonu olmalı (rebalance tetiklenmeli)." }
Write-Host "Ay-sonu rebalance saat dilimi testi başarılı (15:15 UTC -> 18:15 Istanbul; son işlem günü rebalance tetikleniyor, UTC hatası regresyonu kilitlendi)."

# --- Anlık fırsat portföyü risk çıkışı (Get-InstantEntryExitDecision) ---
$exitRules = [pscustomobject]@{ StopLossPct = -8.0; TakeProfitPct = 18.0; TrailingStopPct = 7.0 }
# 1) Tut: küçük kazanç, tepe yakın -> çıkış yok.
$hHold = [pscustomobject]@{ UnrealizedGainPct = 4.0; CurrentPrice = 104; PeakPrice = 105; PeakGainPct = 5.0 }
if ($null -ne (Get-InstantEntryExitDecision -Holding $hHold -Rules $exitRules)) { throw "Risk çıkışı: tutulması gereken pozisyon satıldı." }
# 2) Zarar kes: -9% <= -8 stop.
$hStop = [pscustomobject]@{ UnrealizedGainPct = -9.0; CurrentPrice = 91; PeakPrice = 100; PeakGainPct = 0.0 }
$dStop = Get-InstantEntryExitDecision -Holding $hStop -Rules $exitRules
if ($null -eq $dStop -or $dStop.Kind -ne 'Stop') { throw "Risk çıkışı: stop-loss tetiklenmedi (Kind=$($dStop.Kind))." }
# 3) Kâr al: +20% >= 18 hedef.
$hTake = [pscustomobject]@{ UnrealizedGainPct = 20.0; CurrentPrice = 120; PeakPrice = 122; PeakGainPct = 22.0 }
$dTake = Get-InstantEntryExitDecision -Holding $hTake -Rules $exitRules
if ($null -eq $dTake -or $dTake.Kind -ne 'TakeProfit') { throw "Risk çıkışı: take-profit tetiklenmedi (Kind=$($dTake.Kind))." }
# 4) İz-süren stop: tepe kazanç %25 (≥7), tepeden %8 geri (≤ -7), genel getiri %10 (<18).
$hTrail = [pscustomobject]@{ UnrealizedGainPct = 10.0; CurrentPrice = 115; PeakPrice = 125; PeakGainPct = 25.0 }
$dTrail = Get-InstantEntryExitDecision -Holding $hTrail -Rules $exitRules
if ($null -eq $dTrail -or $dTrail.Kind -ne 'Trailing') { throw "Risk çıkışı: trailing stop tetiklenmedi (Kind=$($dTrail.Kind))." }
# 5) İz-süren stop devrede değil: tepe kazanç %5 (<7) -> düşüş olsa da satma.
$hNoTrail = [pscustomobject]@{ UnrealizedGainPct = -2.0; CurrentPrice = 95; PeakPrice = 103; PeakGainPct = 5.0 }
if ($null -ne (Get-InstantEntryExitDecision -Holding $hNoTrail -Rules $exitRules)) { throw "Risk çıkışı: armlanmamış trailing yanlışlıkla tetiklendi." }
# 6) Kural yoksa hiçbir çıkış olmaz.
if ($null -ne (Get-InstantEntryExitDecision -Holding $hStop -Rules $null)) { throw "Risk çıkışı: kural yokken çıkış üretildi." }
Write-Host "Anlık fırsat risk çıkışı testi başarılı (stop/kar-al/iz-süren stop ayrışıyor)."

# --- Anlık fırsat KAPALI DÖNGÜ nakit (100k sermaye, kâr recycle) ---
# 2 alım (5000+5000) + 1 satış (6000 hasılat; 5000 maliyet + 1000 kâr). Nakit defterden:
$ieTx = @(
    [pscustomobject]@{ Action = 'AL'; AmountTL = 5000 }
    [pscustomobject]@{ Action = 'AL'; AmountTL = 5000 }
    [pscustomobject]@{ Action = 'SAT'; AmountTL = 6000 }
)
$ieCash = Get-InstantEntryCashTL -InitialCapitalTL 100000 -Transactions $ieTx
# 100000 - 10000 + 6000 = 96000
if ([Math]::Abs([double]$ieCash.CashTL - 96000) -gt 0.01) { throw "Anlık nakit yanlış: $($ieCash.CashTL) (beklenen 96000)" }
if ([Math]::Abs([double]$ieCash.TotalBoughtTL - 10000) -gt 0.01) { throw "Kümülatif alım yanlış: $($ieCash.TotalBoughtTL)" }
if ([Math]::Abs([double]$ieCash.TotalSoldProceedsTL - 6000) -gt 0.01) { throw "Satış hasılatı yanlış: $($ieCash.TotalSoldProceedsTL)" }
# Recycle kanıtı: satıştan gelen 6000 (kâr dahil) nakde döndü -> sırf alımlara baksak 90000 olurdu.
if (-not ([double]$ieCash.CashTL -gt (100000 - 10000))) { throw "Kâr recycle edilmedi: nakit satış hasılatını içermiyor." }
# Sermaye tükenmesi: alımlar = sermaye -> nakit 0 (yeni alım duracak).
$ieCash2 = Get-InstantEntryCashTL -InitialCapitalTL 10000 -Transactions @([pscustomobject]@{ Action = 'AL'; AmountTL = 10000 })
if ([Math]::Abs([double]$ieCash2.CashTL) -gt 0.01) { throw "Sermaye tükenince nakit 0 olmalı: $($ieCash2.CashTL)" }
Write-Host "Anlık fırsat kapalı döngü nakit testi başarılı (nakit=96000; kâr recycle; sermaye bitince nakit=0)."

# --- Panel risk metrikleri (Get-DashRiskMetrics, Export-Dashboard.ps1) ---
. (Join-Path $PSScriptRoot 'Export-Dashboard.ps1')
function New-RiskPts([double[]]$Cum) {
    $d = [datetime]'2026-06-01'; $i = 0
    @($Cum | ForEach-Object { $p = [pscustomobject]@{ t = $d.AddDays($i).ToString('yyyy-MM-dd'); v = $_ }; $i++; $p })
}
# 15 nokta: 10 -> 4.5 dususu maksDD = 1.045/1.10-1 = -%5.0 (sonraki dusseler daha kucuk)
$cum = @(0, 10, 4.5, 15, 20, 18, 25, 24, 30, 29, 35, 34, 40, 39, 45)
$pfPts = New-RiskPts $cum
$rm = Get-DashRiskMetrics -PfPoints $pfPts -BenchPoints $pfPts
if ($rm.insufficient) { throw "Risk metrikleri: 14 getiri yeterli olmalıydı." }
if ([Math]::Abs([double]$rm.maxDrawdownPct - (-5.0)) -gt 0.01) { throw "MaksDD yanlış: $($rm.maxDrawdownPct) (beklenen -5.00)" }
if ([Math]::Abs([double]$rm.beta - 1.0) -gt 0.01) { throw "Benchmark=portföy iken beta 1 olmalı: $($rm.beta)" }
if ([Math]::Abs([double]$rm.correlation - 1.0) -gt 0.01) { throw "Korelasyon 1 olmalı: $($rm.correlation)" }
if ([Math]::Abs([double]$rm.trackingErrorPct) -gt 0.01) { throw "TE 0 olmalı: $($rm.trackingErrorPct)" }
if ($null -eq $rm.sharpe -or [double]$rm.sharpe -le 0) { throw "Pozitif trendde Sharpe > 0 olmalı: $($rm.sharpe)" }
$rmShort = Get-DashRiskMetrics -PfPoints (New-RiskPts @(0, 1, 2, 3, 4)) -BenchPoints (New-RiskPts @(0, 1, 2, 3, 4))
if (-not $rmShort.insufficient) { throw "4 getiri ile insufficient=true dönmeliydi." }
Write-Host "Panel risk metrikleri testi başarılı (MaksDD=-5.00, beta=1, korel=1, TE=0; kısa seri veri-kapılı)."

# --- Panel JSON şema sözleşmesi (boş girdiyle bile anahtarlar mevcut olmalı) ---
$schemaR = ConvertTo-DashboardReport -Stocks @() -AsOf ([datetime]'2026-07-01T12:00:00')
$mustKeys = @('meta','summary','performance','allocation','modelPortfolios','instantEntry','stocks','sectorRotation','sectorFlow','riskMetrics','macro','kapNews','heatmap','smartMoney','technicalSignals','llmCommentary','actionItems')
$missingK = @($mustKeys | Where-Object { $null -eq $schemaR.PSObject.Properties[$_] })
if ($missingK.Count) { throw "Panel şemasında eksik anahtar: $($missingK -join ', ')" }
Write-Host "Panel JSON şema testi başarılı ($($mustKeys.Count) zorunlu anahtar mevcut)."


# --- D/E oran ölçeği (denetim düzeltmesi #1) ---
$coreMod = Get-Module 'BistScanner.Core'
$deLow  = & $coreMod { Get-DebtComponentScore -Value 0.3 -Sector 'Industrial' }
$deMid  = & $coreMod { Get-DebtComponentScore -Value 1.5 -Sector 'Industrial' }
$deHigh = & $coreMod { Get-DebtComponentScore -Value 5.0 -Sector 'Industrial' }
if ($deLow -ne 85) { throw "D/E 0.3 (düşük kaldıraç) 85 olmalı: $deLow" }
if ($deMid -ne 50) { throw "D/E 1.5 50 olmalı: $deMid" }
if ($deHigh -ne 15) { throw "D/E 5.0 (yüksek kaldıraç) 15 olmalı: $deHigh" }
Write-Host "D/E oran ölçeği testi başarılı (0.3→85, 1.5→50, 5.0→15; yüksek kaldıraç artık cezalı)."

# --- Hacim yön duyarlılığı (denetim düzeltmesi #4) ---
$vUp   = & $coreMod { Get-VolumeConfirmationComponentScore -Value 2.0 -ChangePct (2.5) }
$vDown = & $coreMod { Get-VolumeConfirmationComponentScore -Value 2.0 -ChangePct (-2.5) }
$vNull = & $coreMod { Get-VolumeConfirmationComponentScore -Value 2.0 }
if ($vUp -ne 92) { throw "Yüksek hacimli yükseliş 92 olmalı: $vUp" }
if ($vDown -ne 25) { throw "Yüksek hacimli DÜŞÜŞ (dağıtım) 25 olmalı: $vDown" }
if ($vNull -ne 92) { throw "Yön bilinmiyorsa eski davranış korunmalı: $vNull" }
Write-Host "Hacim yön duyarlılığı testi başarılı (2x hacim: yükselişte 92, düşüşte 25 — dağıtım cezalı)."

# --- Eksik temel veri CEZALI olmalı (nötr 45 değil) ---
$peGood = & (Get-Module 'BistScanner.Core') { Get-PEComponentScore -Value 10 }
$peNull = & (Get-Module 'BistScanner.Core') { Get-PEComponentScore -Value $null }
$roeNull = & (Get-Module 'BistScanner.Core') { Get-ROEComponentScore -Value $null }
if ($peNull -ge 45) { throw "Eksik F/K hâlâ nötr/yüksek puanlanıyor: $peNull" }
if ($peNull -ge $peGood) { throw "Eksik F/K, iyi F/K'dan düşük olmalı ($peNull vs $peGood)." }
if ($roeNull -ge 45) { throw "Eksik ROE hâlâ nötr puanlanıyor: $roeNull" }
Write-Host "Eksik temel veri ceza testi başarılı (eksik F/K=$peNull, ROE=$roeNull < 45)."

# --- Portföyler-arası yoğunlaşma (Get-CrossPortfolioConcentration) ---
$ccSet = [pscustomobject]@{ Portfolios = @(
        [pscustomobject]@{ Holdings = @(
                [pscustomobject]@{ Symbol = 'AAA'; Company = 'A Co'; CurrentValueTL = 30000 }
                [pscustomobject]@{ Symbol = 'BBB'; Company = 'B Co'; CurrentValueTL = 10000 }
            ) }
        [pscustomobject]@{ Holdings = @(
                [pscustomobject]@{ Symbol = 'AAA'; Company = 'A Co'; CurrentValueTL = 20000 }
                [pscustomobject]@{ Symbol = 'CCC'; Company = 'C Co'; CurrentValueTL = 40000 }
            ) }
    ) }
$cc = @(Get-CrossPortfolioConcentration -PortfolioSet $ccSet -WarnPct 12)
$aaa = $cc | Where-Object { $_.Symbol -eq 'AAA' }
# AAA toplam 50000 / defter 100000 = %50, 2 portföyde, eşiği aşmalı
if ([Math]::Abs([double]$aaa.BookPct - 50.0) -gt 0.01) { throw "Çapraz yoğunlaşma %: $($aaa.BookPct) (beklenen 50)" }
if ([int]$aaa.PortfolioCount -ne 2) { throw "AAA portföy sayısı yanlış: $($aaa.PortfolioCount)" }
if (-not $aaa.Warn) { throw "AAA eşiği aşmasına rağmen işaretlenmedi." }
if ($cc[0].Symbol -ne 'AAA' -and $cc[0].Symbol -ne 'CCC') { throw "Sıralama BookPct azalan değil." }
Write-Host "Portföyler-arası yoğunlaşma testi başarılı (AAA defterin %$($aaa.BookPct)'i, 2 portföy, uyarı=$($aaa.Warn))."

# --- Veri kalitesi özeti (Get-DataQualitySummary) ---
$dqOk = Get-DataQualitySummary -Inputs ([ordered]@{ 'USD/TRY' = 34.2; 'BIST100' = 11000; 'TR10Y' = 30.5 }) -StocksMissingFundamentals 5 -TotalStocks 100
if ($dqOk.Degraded) { throw "Tam veri + düşük eksik oranı 'bozuk' işaretlendi." }
$dqBad = Get-DataQualitySummary -Inputs ([ordered]@{ 'USD/TRY' = 34.2; 'BIST100' = $null; 'TR10Y' = 'Veri Yok' }) -StocksMissingFundamentals 40 -TotalStocks 100
if (-not $dqBad.Degraded) { throw "Eksik kaynak olmasına rağmen 'bozuk' değil." }
if (@($dqBad.MissingInputs) -notcontains 'BIST100') { throw "Eksik BIST100 raporlanmadı: $($dqBad.MissingInputs -join ',')" }
if (@($dqBad.MissingInputs) -notcontains 'TR10Y') { throw "Sayısal olmayan TR10Y eksik sayılmadı." }
# Negatif/sıfır değer GEÇERLİ olmalı (eksik sayılmamalı)
$dqNeg = Get-DataQualitySummary -Inputs ([ordered]@{ 'CDS değişim' = -3.5; 'Banka RS' = 0 }) -StocksMissingFundamentals 0 -TotalStocks 100
if ($dqNeg.Degraded) { throw "Negatif/sıfır geçerli değerler eksik sayıldı." }
Write-Host "Veri kalitesi özeti testi başarılı (eksik kaynak yakalandı, negatif/sıfır geçerli)."

# --- Tam lot yuvarlama (Optimize-ModelPortfolioSetRisk) ---
$lotPorts = @(
    [pscustomobject]@{
        InitialCapitalTL = 40000
        CurrentValueTL = 40000
        Holdings = @(
            [pscustomobject]@{ Symbol = 'AAA'; CurrentPrice = 333.0; CurrentValueTL = 20000; CostBasisTL = 20000; Quantity = 60.06006; WeightPct = 50 }
            [pscustomobject]@{ Symbol = 'BBB'; CurrentPrice = 100.0; CurrentValueTL = 20000; CostBasisTL = 20000; Quantity = 200.0; WeightPct = 50 }
        )
    }
)
$lotOpt = @(Optimize-ModelPortfolioSetRisk -Portfolios $lotPorts -MaxBookPct 15)
$aaaH = $lotOpt[0].Holdings | Where-Object { $_.Symbol -eq 'AAA' }
if ([double]$aaaH.Quantity -ne [Math]::Floor([double]$aaaH.Quantity)) { throw "AAA adedi tam sayı değil: $($aaaH.Quantity)" }
if ([int]$aaaH.Quantity -ne 60) { throw "AAA tam lot yanlış: $($aaaH.Quantity) (beklenen 60)" }
if ([Math]::Abs([double]$aaaH.CurrentValueTL - 19980) -gt 0.5) { throw "AAA değer = adet*fiyat değil: $($aaaH.CurrentValueTL)" }
if ([Math]::Abs([double]$lotOpt[0].CurrentValueTL - 39980) -gt 0.5) { throw "Portföy değeri tam-lot sonrası yanlış: $($lotOpt[0].CurrentValueTL)" }
# MaxBookPct=0 -> hiç dokunma (no-op)
$noopPorts = @([pscustomobject]@{ InitialCapitalTL = 40000; CurrentValueTL = 40000; Holdings = @([pscustomobject]@{ Symbol = 'AAA'; CurrentPrice = 333.0; CurrentValueTL = 20000; Quantity = 60.06; WeightPct = 50 }) })
$noopOpt = @(Optimize-ModelPortfolioSetRisk -Portfolios $noopPorts -MaxBookPct 0)
if ([double]($noopOpt[0].Holdings[0].Quantity) -ne 60.06) { throw "MaxBookPct=0 iken adet değişti (no-op bozuk)." }
Write-Host "Tam lot yuvarlama testi başarılı (AAA 60.06 -> 60 adet, değer 19980; MaxBookPct=0 no-op)."

# --- Kendi kendine öğrenme: walk-forward IC faktör ağırlığı (Get-WalkForwardFactorWeights) ---
$rng = [Random]::new(7)
$lrnPeriods = @()
for ($p = 0; $p -lt 10; $p++) {
    $obs = @()
    for ($k = 0; $k -lt 15; $k++) {
        $f1 = $rng.NextDouble() * 10
        $ret = $f1 * 2 + ($rng.NextDouble() - 0.5)   # ileri getiri ~ F1 (öngörücü)
        $f2 = $rng.NextDouble() * 10                 # alakasız (gürültü)
        $obs += [pscustomobject]@{ Factors = @{ F1 = $f1; F2 = $f2 }; FwdRet = $ret }
    }
    $lrnPeriods += , $obs
}
$lrnPrior = @{ F1 = 0.1; F2 = 0.1 }
$lrn = Get-WalkForwardFactorWeights -Periods $lrnPeriods -PriorWeights $lrnPrior -MinPeriods 8 -MinObsPerPeriod 10 -Lambda 0.5
if (-not $lrn.Diagnostics.Applied) { throw "Yeterli dönemde öğrenme uygulanmadı." }
if ([double]$lrn.Weights.F1 -le [double]$lrn.Weights.F2) { throw "Öngörücü F1 ağırlığı F2'den büyük olmalı (F1=$($lrn.Weights.F1), F2=$($lrn.Weights.F2))." }
# Yetersiz dönem -> prior aynen korunur (overfit/erken öğrenme yok)
$lrnFew = Get-WalkForwardFactorWeights -Periods @($lrnPeriods[0], $lrnPeriods[1]) -PriorWeights $lrnPrior -MinPeriods 8
if ($lrnFew.Diagnostics.Applied) { throw "Yetersiz dönemde öğrenme uygulanmamalı." }
if ([double]$lrnFew.Weights.F1 -ne 0.1) { throw "Yetersiz veride prior korunmadı." }
Write-Host "Walk-forward öğrenme testi başarılı (öngörücü faktör yükseldi; yetersiz veride prior korundu)."

# --- Öğrenilmiş ağırlık dosyası okuma (Get-LearnedFactorWeights) ---
$tmpW = Join-Path ([System.IO.Path]::GetTempPath()) ("lw_" + [guid]::NewGuid().ToString('N') + ".json")
([pscustomobject]@{ Weights = [pscustomobject]@{ RSI = -1.2; dSMA200 = 1.7 } }) | ConvertTo-Json | Set-Content -LiteralPath $tmpW -Encoding UTF8
$lw = Get-LearnedFactorWeights -Path $tmpW
if ($null -eq $lw -or [Math]::Abs([double]$lw['RSI'] - (-1.2)) -gt 1e-9 -or [Math]::Abs([double]$lw['dSMA200'] - 1.7) -gt 1e-9) { throw "Öğrenilmiş ağırlık dosyası doğru okunmadı." }
if ($null -ne (Get-LearnedFactorWeights -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'yok_olmayan.json'))) { throw "Dosya yokken null dönmeli." }
Remove-Item -LiteralPath $tmpW -Force -ErrorAction SilentlyContinue
Write-Host "Öğrenilmiş ağırlık okuma testi başarılı (dosya var -> kullan; yok -> null/varsayılan)."

# --- Veri-kapılı 'Öğrenen Algoritma' model portföyü ---
# Öğrenilmiş ağırlık dosyası YOKKEN tanımlarda OgrenenAlgoritma OLMAMALI; dosya
# olusturulunca EKLENMELI ve seçim öğrenilmiş ağırlıklara göre yapılmalı.
$defaultLearnPath = Join-Path $PSScriptRoot 'data/learned_factor_weights.json'
if (Test-Path -LiteralPath $defaultLearnPath) { throw "Test ön koşulu: $defaultLearnPath zaten var; test güvenli değil." }
$idsBefore = @((Get-ModelPortfolioDefinitions).Id)
if ($idsBefore -contains 'OgrenenAlgoritma') { throw "Öğrenilmiş ağırlık yokken OgrenenAlgoritma portföyü görünmemeli." }
try {
    $dataDir = Split-Path -Parent $defaultLearnPath
    if (-not (Test-Path -LiteralPath $dataDir)) { New-Item -ItemType Directory -Force -Path $dataDir | Out-Null }
    # Yalniz Perf1M'e (pozitif) agirlik -> en yuksek aylik getiri en uste cikmali.
    ([pscustomobject]@{ Weights = [pscustomobject]@{
        RSI = 0; MACDh = 0; WMACDh = 0; dSMA20 = 0; dSMA50 = 0; dSMA200 = 0
        Perf1M = 10; Perf3M = 0; RelVol = 0; RVol = 0
    } }) | ConvertTo-Json | Set-Content -LiteralPath $defaultLearnPath -Encoding UTF8

    $defsAfter = @(Get-ModelPortfolioDefinitions)
    $learnDef = $defsAfter | Where-Object { $_.Id -eq 'OgrenenAlgoritma' }
    if ($null -eq $learnDef) { throw "Öğrenilmiş ağırlık varken OgrenenAlgoritma portföyü tanımlara eklenmedi." }
    if ([string]$learnDef.RankBy -ne 'LearnedFactorScore100') { throw "OgrenenAlgoritma RankBy yanlış: $($learnDef.RankBy)" }

    $learnSel = @(Get-ModelPortfolioSelection -Stocks $stratStocks -Strategy 'Dengeli' -RankBy 'LearnedFactorScore100' -Count 5)
    if ($learnSel.Count -ne 5) { throw "Öğrenen portföy 5 hisse seçmeli, $($learnSel.Count) seçti." }
    foreach ($h in $learnSel) {
        if ($null -eq (Get-ObjectPropertyValue -Object $h -Name 'LearnedFactorScore100')) { throw "Seçilen hissede LearnedFactorScore100 yok: $($h.Symbol)" }
    }
    $learnTop = [string](@($learnSel | Sort-Object @{ Expression = { [double]$_.LearnedFactorScore100 }; Descending = $true } | Select-Object -First 1).Symbol)
    if ($learnTop -ne 'MOM1') { throw "Perf1M-ağırlıklı öğrenmede en yüksek aylık getiri (MOM1) öne çıkmalıydı, çıkan: $learnTop" }
}
finally {
    Remove-Item -LiteralPath $defaultLearnPath -Force -ErrorAction SilentlyContinue
}
$idsAfterCleanup = @((Get-ModelPortfolioDefinitions).Id)
if ($idsAfterCleanup -contains 'OgrenenAlgoritma') { throw "Dosya silindikten sonra OgrenenAlgoritma yine görünmemeli (veri-kapısı)." }
Write-Host "Öğrenen Algoritma portföyü testi başarılı (veri-kapılı: dosya yok->yok, var->5 hisse öğrenilmiş ağırlıkla; MOM1 öne çıktı)."

# --- Faz A gözlem modu: Piyasa genişliği (Get-MarketBreadth) ---
$breadthStocks = @(
    [pscustomobject]@{ Symbol = 'A'; Price = 110; SMA50 = 100; SMA200 = 90; PerfMonth = 5 }
    [pscustomobject]@{ Symbol = 'B'; Price = 80; SMA50 = 90; SMA200 = 100; PerfMonth = -3 }
    [pscustomobject]@{ Symbol = 'C'; Price = 105; SMA50 = 100; SMA200 = 95; PerfMonth = 2 }
    [pscustomobject]@{ Symbol = 'D'; Price = 70; SMA50 = 85; SMA200 = 95; PerfMonth = -1 }
)
$breadth = Get-MarketBreadth -Stocks $breadthStocks
if ([Math]::Abs([double]$breadth.AboveSMA200Pct - 50) -gt 0.01) { throw "Piyasa genişliği SMA200 üstü oranı yanlış: $($breadth.AboveSMA200Pct)" }
if ([Math]::Abs([double]$breadth.PositiveMonthPct - 50) -gt 0.01) { throw "Piyasa genişliği pozitif ay oranı yanlış: $($breadth.PositiveMonthPct)" }
Write-Host "Piyasa genişliği testi başarılı (SMA200 üstü %$($breadth.AboveSMA200Pct), etiket=$($breadth.Label))."

# --- Faz A gözlem modu: Hisse-bazlı RS rank (Add-RelativeStrengthRank) ---
$rsStocks = @(
    [pscustomobject]@{ Symbol = 'STRONG'; PerfMonth = 20; Perf3Month = 40; PerfYear = 60; Bist100PerfMonth = 5; Bist100Perf3Month = 10; Bist100PerfYear = 25 }
    [pscustomobject]@{ Symbol = 'MID1'; PerfMonth = 8; Perf3Month = 12; PerfYear = 28; Bist100PerfMonth = 5; Bist100Perf3Month = 10; Bist100PerfYear = 25 }
    [pscustomobject]@{ Symbol = 'MID2'; PerfMonth = 5; Perf3Month = 9; PerfYear = 22; Bist100PerfMonth = 5; Bist100Perf3Month = 10; Bist100PerfYear = 25 }
    [pscustomobject]@{ Symbol = 'WEAK'; PerfMonth = -10; Perf3Month = -20; PerfYear = -5; Bist100PerfMonth = 5; Bist100Perf3Month = 10; Bist100PerfYear = 25 }
)
$rsRanked = @(Add-RelativeStrengthRank -Stocks $rsStocks)
$rsMap = @{}; foreach ($r in $rsRanked) { $rsMap[[string]$r.Symbol] = $r.RelativeStrengthRank }
if ([double]$rsMap['STRONG'] -ne 100) { throw "RS rank: en güçlü hisse 100 olmalı, $($rsMap['STRONG'])" }
if ([double]$rsMap['WEAK'] -ne 0) { throw "RS rank: en zayıf hisse 0 olmalı, $($rsMap['WEAK'])" }
if (-not ([double]$rsMap['STRONG'] -gt [double]$rsMap['MID1'] -and [double]$rsMap['MID1'] -gt [double]$rsMap['MID2'] -and [double]$rsMap['MID2'] -gt [double]$rsMap['WEAK'])) {
    throw "RS rank sıralaması monoton değil: $($rsMap['STRONG']),$($rsMap['MID1']),$($rsMap['MID2']),$($rsMap['WEAK'])"
}
Write-Host "RS rank testi başarılı (STRONG=$($rsMap['STRONG']), WEAK=$($rsMap['WEAK']))."

# --- Depolanmış KAP okuyucu (Get-StoredKapDisclosures) ---
$kapTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("kap_test_" + [guid]::NewGuid().ToString('N') + ".json")
# borsapy 'dd.MM.yyyy HH:mm:ss' formati verir; tarihleri buna gore kur ki
# dd.MM ayristirmasi (TryParseExact typed string[]) ve MaxAgeDays filtresi
# regresyona karsi test edilsin. Tarihler bugune gore goreli uretilir.
$today = Get-Date
$dRecent = $today.AddDays(-1).ToString('dd.MM.yyyy HH:mm:ss')   # son 7 gun ICINDE
$dOld = $today.AddDays(-40).ToString('dd.MM.yyyy HH:mm:ss')     # 40 gun ONCE
$kapSample = [ordered]@{
    generatedAt = '2026-06-18T12:00:00Z'
    source      = 'test'
    stocks      = [ordered]@{
        AAA = @(
            [ordered]@{ date = $dRecent; title = 'İhale Süreci'; category = 'Ihale/Sozlesme'; importance = 'high'; direction = '+'; disclosureId = '111'; url = 'https://x/Bildirim/111' }
            [ordered]@{ date = $dOld; title = 'Devre Kesici'; category = 'Piyasa/Teknik'; importance = 'noise'; direction = '0'; disclosureId = '112'; url = 'https://x/Bildirim/112' }
        )
        BBB = @(
            [ordered]@{ date = $today.ToString('dd.MM.yyyy HH:mm:ss'); title = 'Kar Payı Dağıtımı'; category = 'Temettu'; importance = 'high'; direction = '+'; disclosureId = '113'; url = 'https://x/Bildirim/113' }
        )
    }
}
($kapSample | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $kapTmp -Encoding UTF8
try {
    $kapAll = @(Get-StoredKapDisclosures -Path $kapTmp)
    if ($kapAll.Count -ne 3) { throw "KAP okuyucu: 3 kayıt beklenirken $($kapAll.Count) döndü." }
    # En yeni kayit (BBB, bugun) basta olmali; dd.MM.yyyy ayristirmasi calismali.
    if ([string]$kapAll[0].Symbol -ne 'BBB') {
        throw "KAP okuyucu: tarihe göre azalan sıralama hatalı (ilk=$($kapAll[0].Symbol))."
    }
    if (@($kapAll | Where-Object { -not $_.DateParsed }).Count -ne 0) {
        throw 'KAP okuyucu: dd.MM.yyyy tarihleri ayrıştırılamadı (DateParsed boş).'
    }
    # MaxAgeDays 7: 40 gün önceki AAA/Devre Kesici elenmeli -> 2 kayıt kalmalı.
    $kapRecent = @(Get-StoredKapDisclosures -Path $kapTmp -MaxAgeDays 7)
    if ($kapRecent.Count -ne 2) { throw "KAP okuyucu: MaxAgeDays 7 ile 2 kayıt beklenirken $($kapRecent.Count) döndü (tarih filtresi/ayrıştırma bozuk)." }
    if (@($kapRecent | Where-Object { $_.Title -eq 'Devre Kesici' }).Count -ne 0) {
        throw 'KAP okuyucu: MaxAgeDays 40 günlük eski kaydı elememiş.'
    }
    $kapImp = @(Get-StoredKapDisclosures -Path $kapTmp -OnlyImportant)
    if ($kapImp.Count -ne 2) { throw "KAP okuyucu: gürültü hariç 2 önemli kayıt beklenirken $($kapImp.Count) döndü." }
    if (@($kapImp | Where-Object { $_.Importance -eq 'noise' }).Count -ne 0) {
        throw 'KAP okuyucu: OnlyImportant gürültüyü (noise) elememiş.'
    }
    $kapSym = @(Get-StoredKapDisclosures -Path $kapTmp -Symbols 'BBB')
    if ($kapSym.Count -ne 1 -or [string]$kapSym[0].Symbol -ne 'BBB') {
        throw "KAP okuyucu: sembol filtresi hatalı ($($kapSym.Count) kayıt)."
    }
    if (@(Get-StoredKapDisclosures -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'yok_olmayan.json')).Count -ne 0) {
        throw 'KAP okuyucu: olmayan dosyada boş dizi dönmedi.'
    }
    Write-Host "Depolanmış KAP okuyucu testi başarılı (toplam=$($kapAll.Count), son7gün=$($kapRecent.Count), önemli=$($kapImp.Count), sembol=$($kapSym.Count))."
}
finally {
    Remove-Item -LiteralPath $kapTmp -ErrorAction SilentlyContinue
}

# --- Point-in-time (PIT) anlik goruntu deposu: kaydet/oku, exact + on-or-before ---
$pitDir = Join-Path ([System.IO.Path]::GetTempPath()) ("pit_test_" + [guid]::NewGuid())
try {
    $pitStocks = @(
        ($sample | Select-Object *),
        ([pscustomobject]@{ Symbol = 'TEST2'; Price = 50.0; MarketCap = 5e9; PE = 7.0; PB = 1.0; ROE = 18.0; DebtToEquity = 30.0; DividendYield = 1.0; Sector = 'Finance'; VolatilityD = 3.0; AverageVolume10D = 1e6; LatestReportDate = $null; NextEarningsDate = $null; FiscalPeriodEnd = $null })
    )
    $savedPath = Save-PitSnapshot -Stocks $pitStocks -Directory $pitDir -AsOf ([datetime]'2026-06-16')
    if (-not (Test-Path -LiteralPath $savedPath)) { throw 'PIT anlik goruntu dosyasi yazilmadi.' }
    $pitRead = Get-PitSnapshot -Date ([datetime]'2026-06-16') -Directory $pitDir
    if ($pitRead.UniverseCount -ne 2) { throw "PIT evren sayisi yanlis: $($pitRead.UniverseCount)" }
    if (@($pitRead.Constituents | Where-Object { $_.Symbol -eq 'TEST' }).Count -ne 1) { throw 'PIT bilesen kaybi.' }
    $pitMissing = Get-PitSnapshot -Date ([datetime]'2026-06-10') -Directory $pitDir
    if ($null -ne $pitMissing) { throw 'PIT exact-eslesme yoksa null donmeliydi.' }
    $pitBefore = Get-PitSnapshot -Date ([datetime]'2026-06-20') -Directory $pitDir -OnOrBefore
    if ($null -eq $pitBefore) { throw 'PIT on-or-before en yakin onceki kaydi dondurmedi.' }
    Write-Host "PIT anlik goruntu deposu testi başarılı (evren $($pitRead.UniverseCount), on-or-before OK)."
}
finally {
    if (Test-Path -LiteralPath $pitDir) { Remove-Item -LiteralPath $pitDir -Recurse -Force -ErrorAction SilentlyContinue }
}

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
