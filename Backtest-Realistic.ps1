#requires -Version 5.1
<#
    GERCEKCI geriye-donuk backtest. Onceki momentum backtest'inin yanliliklarini azaltir:
    - Evren yanliligi: her ay sonu O ANKI likidite (gecmis ~21g ortalama TL hacim)
      filtresi; bugunun kazananlarini ON-secmez. (Kalan survivorship: bugun listede
      olmayan/delist olmus hisseler ucretsiz veride yok -> dipnotta belirtilir.)
    - Sinyal: bot'un EN IYI sinyali olan RFS (teknik cok-faktor: RSI/MACD/SMA/perf/
      hacim/vol) fiyat+hacimden POINT-IN-TIME yeniden kurulur ve modulun gercek
      Add-RawFactorScore z-blend'iyle siralanir. (Temel/bilanco faktoru gecmis anlik
      goruntu ucretsiz olmadigi icin DAHIL DEGIL; bu, RFS100 portfoyunun sadık replayidir.)
    - Likidite etkisi: karekok piyasa-etkisi maliyeti (islem TL / gunluk TL hacim).
    Yatirim tavsiyesi degildir; yaklasik analizdir.
#>
param(
    [int]$MaxStocks = 300,
    [int]$TopN = 5,
    [datetime]$StartDate = ([datetime]'2024-09-01'),
    [double]$InitialCapital = 100000,
    [double]$CostBps = 20,
    [double]$MinAdvTl = 3000000,      # o anki min gunluk TL hacim (likidite kapisi)
    [double]$ImpactKBps = 100,        # etki: islemTL = gunlukTL iken ~100 bps
    [double]$ImpactCapBps = 400,
    [int]$MaxElapsedSec = 660
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BistScanner.Core.psm1') -Force

function Get-IndexOnOrBefore {
    param([object[]]$Series, [datetime]$Date)
    $idx = -1
    for ($i = 0; $i -lt $Series.Count; $i++) { if ($Series[$i].Date.Date -le $Date.Date) { $idx = $i } else { break } }
    return $idx
}

# Gosterge dizilerini bir kez hesapla (EMA/RSI/SMA/ADV), tarih indeksiyle hizali.
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

    # RSI(14) Wilder
    $rsi = New-Object double[] $n
    $avgGain = 0.0; $avgLoss = 0.0; $period = 14
    for ($i = 1; $i -lt $n; $i++) {
        $chg = $close[$i] - $close[$i - 1]
        $gain = [Math]::Max(0, $chg); $loss = [Math]::Max(0, - $chg)
        if ($i -le $period) {
            $avgGain += $gain / $period; $avgLoss += $loss / $period
            $rsi[$i] = 50
        }
        else {
            $avgGain = ($avgGain * ($period - 1) + $gain) / $period
            $avgLoss = ($avgLoss * ($period - 1) + $loss) / $period
            $rs = if ($avgLoss -eq 0) { 100 } else { $avgGain / $avgLoss }
            $rsi[$i] = 100 - (100 / (1 + $rs))
        }
    }
    $rsi[0] = 50

    # Rolling 21-gun ortalama TL hacim (close*volume)
    $advTl = New-Object double[] $n
    $win = 21; $sum = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $tl = $close[$i] * $vol[$i]
        $sum += $tl
        if ($i -ge $win) { $sum -= $close[$i - $win] * $vol[$i - $win] }
        $cnt = [Math]::Min($i + 1, $win)
        $advTl[$i] = $sum / $cnt
    }

    return [pscustomobject]@{ Close = $close; Vol = $vol; Hist = $hist; Rsi = $rsi; AdvTl = $advTl; N = $n; Series = $Series }
}

function Get-SMA { param($Close, [int]$Idx, [int]$P) if ($Idx -lt $P - 1) { return $null } $s = 0.0; for ($j = $Idx - $P + 1; $j -le $Idx; $j++) { $s += $Close[$j] } return $s / $P }
function Get-MeanRange { param($Arr, [int]$A, [int]$B) if ($A -lt 0) { $A = 0 } if ($B -lt $A) { return 0 } $s = 0.0; for ($j = $A; $j -le $B; $j++) { $s += $Arr[$j] } return $s / ($B - $A + 1) }

Write-Host "=== GERCEKCI backtest (RFS teknik + point-in-time likidite + piyasa etkisi) ==="
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
$bist = @(Get-YahooDailyCloseSeries -Symbol 'XU100' -Range '3y' -TimeoutSec 8)
if ($bist.Count -lt 200) { Write-Host 'BIST100 alinamadi; cikiliyor.'; return }

$today = (Get-Date).Date
$rebalanceDates = [System.Collections.Generic.List[datetime]]::new()
$cursor = [datetime]::new($StartDate.Year, $StartDate.Month, 1)
while ($cursor -le $today) {
    $me = $cursor.AddMonths(1).AddDays(-1); if ($me -gt $today) { $me = $today }
    [void]$rebalanceDates.Add($me); $cursor = $cursor.AddMonths(1)
}
Write-Host "Rebalance ay sayisi: $($rebalanceDates.Count)"

$fixedRate = $CostBps / 10000.0
$value = $InitialCapital
$holdings = @{}        # sym -> qty
$peak = $InitialCapital; $maxDd = 0.0; $totalCost = 0.0
$valuePath = [System.Collections.Generic.List[object]]::new()

foreach ($rd in $rebalanceDates) {
    # mevcut degerleme
    if ($holdings.Count -gt 0) {
        $mv = 0.0
        foreach ($sym in @($holdings.Keys)) {
            $o = $ind[$sym]; $i = Get-IndexOnOrBefore -Series $o.Series -Date $rd
            if ($i -ge 0) { $mv += [double]$holdings[$sym] * $o.Close[$i] }
        }
        if ($mv -gt 0) { $value = $mv }
    }

    # point-in-time aday + RFS pseudo-stock
    $pseudo = [System.Collections.Generic.List[object]]::new()
    $advMap = @{}
    foreach ($sym in @($ind.Keys)) {
        $o = $ind[$sym]; $i = Get-IndexOnOrBefore -Series $o.Series -Date $rd
        if ($i -lt 200) { continue }   # 200g SMA ve yeterli gecmis
        $advTl = $o.AdvTl[$i]
        if ($advTl -lt $MinAdvTl) { continue }   # O ANKI likidite kapisi
        $advMap[$sym] = $advTl
        $price = $o.Close[$i]
        $sma20 = Get-SMA $o.Close $i 20; $sma50 = Get-SMA $o.Close $i 50; $sma200 = Get-SMA $o.Close $i 200
        $perfM = if ($i -ge 21 -and $o.Close[$i - 21] -gt 0) { (($price / $o.Close[$i - 21]) - 1) * 100 } else { $null }
        $perf3 = if ($i -ge 63 -and $o.Close[$i - 63] -gt 0) { (($price / $o.Close[$i - 63]) - 1) * 100 } else { $null }
        $relVol = $null
        if ($i -ge 10) { $avgV = Get-MeanRange -Arr $o.Vol -A ($i - 9) -B $i; if ($avgV -gt 0) { $relVol = $o.Vol[$i] / $avgV } }
        $dvol = $null
        if ($i -ge 20) { $rets = for ($j = $i - 19; $j -le $i; $j++) { if ($o.Close[$j - 1] -gt 0) { ($o.Close[$j] / $o.Close[$j - 1]) - 1 } }; $m = ($rets | Measure-Object -Average).Average; $var = 0.0; foreach ($r in $rets) { $var += ($r - $m) * ($r - $m) }; $dvol = [Math]::Sqrt($var / $rets.Count) * 100 }
        [void]$pseudo.Add([pscustomobject]@{
                Symbol = $sym; Price = $price; RSI = $o.Rsi[$i]; MacdHistogram = $o.Hist[$i]; MacdHistogramWeekly = $null
                SMA20 = $sma20; SMA50 = $sma50; SMA200 = $sma200; PerfMonth = $perfM; Perf3Month = $perf3
                RelativeVolume = $relVol; VolatilityD = $dvol
            })
    }
    if ($pseudo.Count -lt $TopN) { [void]$valuePath.Add([pscustomobject]@{ Date = $rd; Value = $value; N = 0 }); continue }

    $ranked = @(Add-RawFactorScore -Stocks $pseudo.ToArray())
    $selected = @($ranked | Sort-Object @{ Expression = { [double]$_.RawFactorScore100 }; Descending = $true } | Select-Object -First $TopN)

    # turnover + sabit + etki maliyeti
    $targetPre = $value / $TopN
    $currentMV = @{}
    foreach ($sym in @($holdings.Keys)) { $o = $ind[$sym]; $i = Get-IndexOnOrBefore -Series $o.Series -Date $rd; if ($i -ge 0) { $currentMV[$sym] = [double]$holdings[$sym] * $o.Close[$i] } }
    $selSet = @{}; foreach ($x in $selected) { $selSet[$x.Symbol] = $true }
    $cost = 0.0
    $allSyms = @(@($currentMV.Keys) + @($selected | ForEach-Object Symbol) | Select-Object -Unique)
    foreach ($sym in $allSyms) {
        $cur = if ($currentMV.ContainsKey($sym)) { [double]$currentMV[$sym] } else { 0.0 }
        $tgt = if ($selSet.ContainsKey($sym)) { $targetPre } else { 0.0 }
        $trade = [Math]::Abs($tgt - $cur)
        if ($trade -le 0) { continue }
        $adv = if ($advMap.ContainsKey($sym)) { [double]$advMap[$sym] } else { $MinAdvTl }
        $impactBps = [Math]::Min($ImpactCapBps, $ImpactKBps * [Math]::Sqrt($trade / [Math]::Max($adv, 1)))
        $cost += $trade * ($fixedRate + $impactBps / 10000.0)
    }
    $cost = [Math]::Round($cost, 2)
    $totalCost += $cost
    $value = $value - $cost
    $target = $value / $TopN

    $holdings = @{}
    foreach ($x in $selected) { if ([double]$x.Price -gt 0) { $holdings[$x.Symbol] = $target / [double]$x.Price } }

    if ($value -gt $peak) { $peak = $value }
    $dd = if ($peak -gt 0) { (($value / $peak) - 1) * 100 } else { 0 }
    if ($dd -lt $maxDd) { $maxDd = $dd }
    [void]$valuePath.Add([pscustomobject]@{ Date = $rd; Value = [Math]::Round($value, 0); N = $selected.Count })
}

if ($holdings.Count -gt 0) {
    $mv = 0.0
    foreach ($sym in @($holdings.Keys)) { $o = $ind[$sym]; $i = Get-IndexOnOrBefore -Series $o.Series -Date $today; if ($i -ge 0) { $mv += [double]$holdings[$sym] * $o.Close[$i] } }
    if ($mv -gt 0) { $value = $mv }
}

$stratReturn = (($value / $InitialCapital) - 1) * 100
$bi = Get-IndexOnOrBefore -Series $bist -Date $rebalanceDates[0]; $bj = Get-IndexOnOrBefore -Series $bist -Date $today
$bistStart = if ($bi -ge 0) { [double]$bist[$bi].Close } else { $null }
$bistEnd = if ($bj -ge 0) { [double]$bist[$bj].Close } else { $null }
$bistReturn = if ($null -ne $bistStart -and $bistStart -gt 0) { (($bistEnd / $bistStart) - 1) * 100 } else { $null }

Write-Host ""
Write-Host "=== SONUC ($($StartDate.ToString('yyyy-MM')) -> $($today.ToString('yyyy-MM'))) ==="
Write-Host ("Baslangic: {0:N0} TL | Evren(gosterge): $($ind.Count) | TopN: $TopN | min ADV: {1:N0} TL" -f $InitialCapital, $MinAdvTl)
Write-Host ("Strateji (RFS teknik, point-in-time, sabit $CostBps bps + piyasa etkisi): {0:N0} TL | getiri %{1:N1} | maks dusus %{2:N1} | toplam maliyet {3:N0} TL" -f $value, $stratReturn, $maxDd, $totalCost)
if ($null -ne $bistReturn) {
    Write-Host ("BIST100 al-tut: {0:N0} TL | getiri %{1:N1}" -f ($InitialCapital * ($bistEnd / $bistStart)), $bistReturn)
    Write-Host ("ALFA: %{0:N1}" -f ($stratReturn - $bistReturn))
}
Write-Host ""
Write-Host "=== Aylik deger yolu ==="
foreach ($v in $valuePath) { Write-Host ("{0}  {1,12:N0}  (N={2})" -f $v.Date.ToString('yyyy-MM-dd'), $v.Value, $v.N) }
Write-Host "=== Backtest tamam ($([int]((Get-Date)-$startedAt).TotalSeconds) sn) ==="
