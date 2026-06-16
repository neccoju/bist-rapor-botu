#requires -Version 5.1
<#
    Backtest-EventDriven.ps1 — GERCEK event-driven backtest kosucusu.

    Onceki "aylik dongu" backtest'inden farki: simulasyon GUNLUK olay ekseninde
    ilerler (BacktestEngine.psm1 / Invoke-EventDrivenBacktest). Her gun mark-to-
    market yapilir; ayin son islem gunlerinde sinyal (yalniz O GUNE kadarki fiyat/
    hacimle) yeniden hesaplanir, hedef esit agirlik kurulur ve emirler GERCEKCI
    dolumla islenir: komisyon + kayma + karekok piyasa-etkisi + ADV katilim siniri.

    Sinyal: botun RFS teknik cok-faktoru (RSI/MACD/SMA/perf/hacim/vol) point-in-time
    yeniden kurulup modulun gercek Add-RawFactorScore z-blend'iyle siralanir.

    Kurumsal metrikler: CAGR, yillik vol, Sharpe, Sortino, Calmar, maks dusus,
    yillik turnover, BIST100 alpha, aylik isabet.

    KISIT (durust): gecmis as-reported temel veri ve delist-dahil bilesen listesi
    ucretsiz olmadigindan survivorship tam giderilemez; rakamlar iyimser ust sinirdir.
    Yanlilik-suz olcum icin canli ileriye-donuk alfa (model portfoyler) izlenir.
#>
param(
    [int]$MaxStocks = 300,
    [int]$TopN = 5,
    [datetime]$StartDate = ([datetime]'2024-09-01'),
    [double]$InitialCapital = 100000,
    [double]$CommissionBps = 15,
    [double]$SlippageBps = 10,
    [double]$MinAdvTl = 3000000,      # o anki min gunluk TL hacim (likidite kapisi)
    [double]$ImpactKBps = 100,
    [double]$ImpactCapBps = 400,
    [double]$MaxAdvMultiple = 0.25,   # tek isimde gunluk TL hacmin en fazla bu kati
    [int]$MaxElapsedSec = 660
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BistScanner.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'BacktestEngine.psm1') -Force

function Get-IndexOnOrBefore {
    param([object[]]$Series, [datetime]$Date)
    $idx = -1
    for ($i = 0; $i -lt $Series.Count; $i++) { if ($Series[$i].Date.Date -le $Date.Date) { $idx = $i } else { break } }
    return $idx
}

# Gosterge dizilerini bir kez hesapla (EMA/RSI/SMA tabani + ADV), tarih indeksiyle hizali.
function Build-Indicators {
    param([object[]]$Series)
    $n = $Series.Count
    $close = New-Object double[] $n
    $vol = New-Object double[] $n
    for ($i = 0; $i -lt $n; $i++) { $close[$i] = [double]$Series[$i].Close; $vol[$i] = [double]$Series[$i].Volume }

    $ema12 = New-Object double[] $n; $ema26 = New-Object double[] $n
    $macd = New-Object double[] $n; $signal = New-Object double[] $n; $hist = New-Object double[] $n
    $k12 = 2.0 / 13; $k26 = 2.0 / 27; $k9 = 2.0 / 10
    for ($i = 0; $i -lt $n; $i++) {
        if ($i -eq 0) { $ema12[$i] = $close[$i]; $ema26[$i] = $close[$i] }
        else {
            $ema12[$i] = $close[$i] * $k12 + $ema12[$i - 1] * (1 - $k12)
            $ema26[$i] = $close[$i] * $k26 + $ema26[$i - 1] * (1 - $k26)
        }
        $macd[$i] = $ema12[$i] - $ema26[$i]
        if ($i -eq 0) { $signal[$i] = $macd[$i] } else { $signal[$i] = $macd[$i] * $k9 + $signal[$i - 1] * (1 - $k9) }
        $hist[$i] = $macd[$i] - $signal[$i]
    }

    $rsi = New-Object double[] $n
    $avgGain = 0.0; $avgLoss = 0.0; $period = 14
    for ($i = 1; $i -lt $n; $i++) {
        $chg = $close[$i] - $close[$i - 1]
        $gain = [Math]::Max(0, $chg); $loss = [Math]::Max(0, - $chg)
        if ($i -le $period) { $avgGain += $gain / $period; $avgLoss += $loss / $period; $rsi[$i] = 50 }
        else {
            $avgGain = ($avgGain * ($period - 1) + $gain) / $period
            $avgLoss = ($avgLoss * ($period - 1) + $loss) / $period
            $rs = if ($avgLoss -eq 0) { 100 } else { $avgGain / $avgLoss }
            $rsi[$i] = 100 - (100 / (1 + $rs))
        }
    }
    $rsi[0] = 50

    $advTl = New-Object double[] $n
    $win = 21; $sum = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $tl = $close[$i] * $vol[$i]; $sum += $tl
        if ($i -ge $win) { $sum -= $close[$i - $win] * $vol[$i - $win] }
        $cnt = [Math]::Min($i + 1, $win)
        $advTl[$i] = $sum / $cnt
    }

    return [pscustomobject]@{ Close = $close; Vol = $vol; Hist = $hist; Rsi = $rsi; AdvTl = $advTl; N = $n; Series = $Series }
}

function Get-SMA { param($Close, [int]$Idx, [int]$P) if ($Idx -lt $P - 1) { return $null } $s = 0.0; for ($j = $Idx - $P + 1; $j -le $Idx; $j++) { $s += $Close[$j] } return $s / $P }
function Get-MeanRange { param($Arr, [int]$A, [int]$B) if ($A -lt 0) { $A = 0 } if ($B -lt $A) { return 0 } $s = 0.0; for ($j = $A; $j -le $B; $j++) { $s += $Arr[$j] } return $s / ($B - $A + 1) }

Write-Host "=== EVENT-DRIVEN backtest (gunluk olay ekseni + gercekci dolum) ==="
$startedAt = Get-Date
$stocks = @(Invoke-BistStockScan)
Write-Host "Taranan hisse: $($stocks.Count)"
$symbols = @($stocks | Sort-Object @{ Expression = { [double]$_.MarketCap }; Descending = $true } | Select-Object -First $MaxStocks | ForEach-Object { [string]$_.Symbol })

$ind = @{}
$fetched = 0
foreach ($sym in $symbols) {
    if (((Get-Date) - $startedAt).TotalSeconds -gt $MaxElapsedSec) { Write-Host "Zaman siniri; $fetched cekildi."; break }
    $series = @(Get-YahooDailyOhlcSeries -Symbol $sym -Range '3y' -TimeoutSec 8)
    $fetched++
    if ($series.Count -ge 260) { $ind[$sym] = Build-Indicators -Series $series }
}
Write-Host "Gosterge kurulan hisse: $($ind.Count)"
if ($ind.Count -lt $TopN) { Write-Host 'Yeterli hisse yok; cikiliyor.'; return }

$bist = @(Get-YahooDailyCloseSeries -Symbol 'XU100' -Range '3y' -TimeoutSec 8)
if ($bist.Count -lt 200) { Write-Host 'BIST100 alinamadi; cikiliyor.'; return }

# Motorun bekledigi fiyat verisi: sym -> {Date, Close, AdvTl}
$priceData = @{}
foreach ($sym in @($ind.Keys)) {
    $o = $ind[$sym]
    $rows = New-Object 'System.Collections.Generic.List[object]'
    for ($i = 0; $i -lt $o.N; $i++) {
        [void]$rows.Add([pscustomobject]@{ Date = [datetime]$o.Series[$i].Date; Close = $o.Close[$i]; AdvTl = $o.AdvTl[$i] })
    }
    $priceData[$sym] = $rows.ToArray()
}
# Benchmark serisi {Date, Close}
$benchSeries = @($bist | ForEach-Object { [pscustomobject]@{ Date = [datetime]$_.Date; Close = [double]$_.Close } })

# Ay-sonu rebalance tarihleri
$today = (Get-Date).Date
$rebalanceDates = [System.Collections.Generic.List[datetime]]::new()
$cursor = [datetime]::new($StartDate.Year, $StartDate.Month, 1)
while ($cursor -le $today) {
    $me = $cursor.AddMonths(1).AddDays(-1); if ($me -gt $today) { $me = $today }
    [void]$rebalanceDates.Add($me); $cursor = $cursor.AddMonths(1)
}
Write-Host "Rebalance ay sayisi: $($rebalanceDates.Count)"

# Sinyal: point-in-time RFS siralamasi. $ind ve parametreleri closure ile yakalar.
$signalCallback = {
    param($AsOf, $PriceData)
    $pseudo = [System.Collections.Generic.List[object]]::new()
    foreach ($sym in @($ind.Keys)) {
        $o = $ind[$sym]
        $i = Get-IndexOnOrBefore -Series $o.Series -Date $AsOf
        if ($i -lt 200) { continue }
        $advTl = $o.AdvTl[$i]
        if ($advTl -lt $MinAdvTl) { continue }
        $price = $o.Close[$i]
        $sma20 = Get-SMA $o.Close $i 20; $sma50 = Get-SMA $o.Close $i 50; $sma200 = Get-SMA $o.Close $i 200
        $perfM = if ($i -ge 21 -and $o.Close[$i - 21] -gt 0) { (($price / $o.Close[$i - 21]) - 1) * 100 } else { $null }
        $perf3 = if ($i -ge 63 -and $o.Close[$i - 63] -gt 0) { (($price / $o.Close[$i - 63]) - 1) * 100 } else { $null }
        $relVol = $null
        if ($i -ge 10) { $avgV = Get-MeanRange -Arr $o.Vol -A ($i - 9) -B $i; if ($avgV -gt 0) { $relVol = $o.Vol[$i] / $avgV } }
        $dvol = $null
        if ($i -ge 20) {
            $rets = for ($j = $i - 19; $j -le $i; $j++) { if ($o.Close[$j - 1] -gt 0) { ($o.Close[$j] / $o.Close[$j - 1]) - 1 } }
            $m = ($rets | Measure-Object -Average).Average; $var = 0.0; foreach ($r in $rets) { $var += ($r - $m) * ($r - $m) }
            $dvol = [Math]::Sqrt($var / $rets.Count) * 100
        }
        [void]$pseudo.Add([pscustomobject]@{
                Symbol = $sym; Price = $price; RSI = $o.Rsi[$i]; MacdHistogram = $o.Hist[$i]; MacdHistogramWeekly = $null
                SMA20 = $sma20; SMA50 = $sma50; SMA200 = $sma200; PerfMonth = $perfM; Perf3Month = $perf3
                RelativeVolume = $relVol; VolatilityD = $dvol
            })
    }
    if ($pseudo.Count -lt $TopN) { return @() }
    $ranked = @(Add-RawFactorScore -Stocks $pseudo.ToArray())
    $selected = @($ranked | Sort-Object @{ Expression = { [double]$_.RawFactorScore100 }; Descending = $true } | Select-Object -First $TopN | ForEach-Object { [string]$_.Symbol })
    return $selected
}.GetNewClosure()

$result = Invoke-EventDrivenBacktest -PriceData $priceData -RebalanceDates @($rebalanceDates.ToArray()) `
    -SignalCallback $signalCallback -BenchmarkSeries $benchSeries -InitialCapital $InitialCapital `
    -CommissionBps $CommissionBps -SlippageBps $SlippageBps -ImpactKBps $ImpactKBps `
    -ImpactCapBps $ImpactCapBps -MaxAdvMultiple $MaxAdvMultiple

Write-Host ""
Write-Host "=== SONUC ($($StartDate.ToString('yyyy-MM')) -> $($today.ToString('yyyy-MM'))) ==="
Write-Host ("Baslangic: {0:N0} TL | Evren(gosterge): $($ind.Count) | TopN: $TopN | min ADV: {1:N0} TL" -f $InitialCapital, $MinAdvTl)
Write-Host ("Son deger      : {0:N0} TL" -f $result.FinalValue)
Write-Host ("Toplam getiri  : %{0:N2}" -f $result.TotalReturnPct)
Write-Host ("CAGR           : %{0:N2}" -f $result.CagrPct)
Write-Host ("Yillik vol     : %{0:N2}" -f $result.AnnVolPct)
Write-Host ("Sharpe         : {0:N2}" -f $result.Sharpe)
Write-Host ("Sortino        : {0:N2}" -f $result.Sortino)
Write-Host ("Calmar         : {0:N2}" -f $result.Calmar)
Write-Host ("Maks dusus     : %{0:N2}" -f $result.MaxDrawdownPct)
Write-Host ("Yillik turnover: {0:N2}x" -f $result.TurnoverAnnual)
Write-Host ("Toplam maliyet : {0:N0} TL" -f $result.TotalCostsTL)
Write-Host ("Aylik isabet   : %{0:N1}" -f $result.HitRatePct)
Write-Host ("Islem sayisi   : {0}" -f $result.TradeCount)
if ($null -ne $result.BenchmarkReturnPct) {
    Write-Host ("BIST100 getiri : %{0:N2}" -f $result.BenchmarkReturnPct)
    Write-Host ("ALFA           : %{0:N2}" -f $result.AlphaPct)
}
Write-Host ""
Write-Host "=== Aylik getiriler ==="
foreach ($m in $result.MonthlyReturns) { Write-Host ("{0}  %{1,7:N2}" -f $m.Month, $m.ReturnPct) }
Write-Host "=== Backtest tamam ($([int]((Get-Date)-$startedAt).TotalSeconds) sn) ==="
