#requires -Version 5.1
<#
    Geriye donuk (walk-forward) backtest — DURUST YAKLASIM.
    ONEMLI: Botun asil secimi o anki TEMEL (bilanco) verisini kullanir; gecmis
    bilanco anlik goruntuleri ucretsiz yok. Bu yuzden tam cok-faktor skoru
    gecmise birebir uygulanamaz (look-ahead olur). Bu script, fiyat gecmisinden
    POINT-IN-TIME kurulabilen MOMENTUM stratejisini (her ay sonu yalniz o ana
    kadarki fiyatlar) simule eder: 12-1 momentum, ust N esit agirlik, aylik
    rebalance, islem maliyeti dahil; BIST100 (XU100) al-tut ile kiyaslar.
    Survivorship: yalniz bugun listede/likit olanlar; gecmiste delist olanlar yok.
    Yatirim tavsiyesi degildir; yaklasik bir analizdir.
#>
param(
    [int]$MaxStocks = 200,
    [int]$TopN = 5,
    [datetime]$StartDate = ([datetime]'2024-09-01'),
    [double]$InitialCapital = 100000,
    [double]$CostBps = 20,
    [double]$MinAvgVol = 250000,
    [int]$MaxElapsedSec = 660
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BistScanner.Core.psm1') -Force

function Get-CloseOnOrBefore {
    param([object[]]$Series, [datetime]$Date)
    $res = $null
    foreach ($pt in $Series) {
        if ($pt.Date.Date -le $Date.Date) { $res = [double]$pt.Close } else { break }
    }
    return $res
}

Write-Host "=== Geriye donuk backtest (momentum 12-1, aylik) baslıyor ==="
$startedAt = Get-Date
$stocks = @(Invoke-BistStockScan)
Write-Host "Taranan hisse: $($stocks.Count)"

$universe = @($stocks | Where-Object {
        $null -ne $_.AverageVolume10D -and $_.AverageVolume10D -ge $MinAvgVol -and
        $null -ne $_.MarketCap -and $_.MarketCap -ge 2000000000 -and
        $null -ne $_.Price -and $_.Price -gt 0
    } | Sort-Object @{ Expression = { [double]$_.MarketCap }; Descending = $true } | Select-Object -First $MaxStocks)
Write-Host "Backtest evreni: $($universe.Count) hisse (piyasa degerine gore, likit)"

# Fiyat gecmisleri (3y gunluk).
$priceMap = @{}
$fetched = 0
foreach ($s in $universe) {
    if (((Get-Date) - $startedAt).TotalSeconds -gt $MaxElapsedSec) { Write-Host "Zaman siniri; $fetched fiyat cekildi."; break }
    $sym = [string]$s.Symbol
    $series = @(Get-YahooDailyCloseSeries -Symbol $sym -Range '3y' -TimeoutSec 8)
    $fetched++
    if ($series.Count -ge 200) { $priceMap[$sym] = $series }
}
Write-Host "Fiyat gecmisi bulunan: $($priceMap.Count)"
$bist = @(Get-YahooDailyCloseSeries -Symbol 'XU100' -Range '3y' -TimeoutSec 8)
if ($bist.Count -lt 200) { Write-Host 'BIST100 gecmisi alinamadi; cikiliyor.'; return }

# Ay sonu rebalance tarihleri: StartDate'ten bugune her ayin son gunu.
$today = (Get-Date).Date
$rebalanceDates = [System.Collections.Generic.List[datetime]]::new()
$cursor = [datetime]::new($StartDate.Year, $StartDate.Month, 1)
while ($cursor -le $today) {
    $monthEnd = $cursor.AddMonths(1).AddDays(-1)
    if ($monthEnd -gt $today) { $monthEnd = $today }
    [void]$rebalanceDates.Add($monthEnd)
    $cursor = $cursor.AddMonths(1)
}
Write-Host "Rebalance ay sayisi: $($rebalanceDates.Count) ($($StartDate.ToString('yyyy-MM')) -> $($today.ToString('yyyy-MM')))"

$costRate = $CostBps / 10000.0
$value = $InitialCapital
$holdings = @{}   # symbol -> quantity
$peak = $InitialCapital
$maxDd = 0.0
$valuePath = [System.Collections.Generic.List[object]]::new()

foreach ($rd in $rebalanceDates) {
    # 1) Mevcut holdingleri rd'de degerle.
    if ($holdings.Count -gt 0) {
        $mv = 0.0
        foreach ($sym in @($holdings.Keys)) {
            $p = Get-CloseOnOrBefore -Series $priceMap[$sym] -Date $rd
            if ($null -ne $p) { $mv += [double]$holdings[$sym] * $p }
        }
        if ($mv -gt 0) { $value = $mv }
    }

    # 2) Momentum 12-1: (P[rd-1ay] / P[rd-13ay]) - 1
    $scores = [System.Collections.Generic.List[object]]::new()
    foreach ($sym in @($priceMap.Keys)) {
        $series = $priceMap[$sym]
        $pNow = Get-CloseOnOrBefore -Series $series -Date $rd
        $pSkip = Get-CloseOnOrBefore -Series $series -Date $rd.AddDays(-21)
        $pBase = Get-CloseOnOrBefore -Series $series -Date $rd.AddMonths(-13)
        if ($null -ne $pNow -and $pNow -gt 0 -and $null -ne $pSkip -and $pSkip -gt 0 -and $null -ne $pBase -and $pBase -gt 0) {
            [void]$scores.Add([pscustomobject]@{ Symbol = $sym; Mom = ($pSkip / $pBase) - 1.0; Price = $pNow })
        }
    }
    if ($scores.Count -lt $TopN) { [void]$valuePath.Add([pscustomobject]@{ Date = $rd; Value = $value; N = 0 }); continue }

    $selected = @($scores | Sort-Object Mom -Descending | Select-Object -First $TopN)

    # 3) Turnover maliyeti: hedef esit agirlik vs mevcut.
    $targetPre = $value / $TopN
    $currentMV = @{}
    foreach ($sym in @($holdings.Keys)) {
        $p = Get-CloseOnOrBefore -Series $priceMap[$sym] -Date $rd
        if ($null -ne $p) { $currentMV[$sym] = [double]$holdings[$sym] * $p }
    }
    $selSet = @{}; foreach ($x in $selected) { $selSet[$x.Symbol] = $true }
    $turnover = 0.0
    $allSyms = @(@($currentMV.Keys) + @($selected | ForEach-Object Symbol) | Select-Object -Unique)
    foreach ($sym in $allSyms) {
        $cur = if ($currentMV.ContainsKey($sym)) { [double]$currentMV[$sym] } else { 0.0 }
        $tgt = if ($selSet.ContainsKey($sym)) { $targetPre } else { 0.0 }
        $turnover += [Math]::Abs($tgt - $cur)
    }
    $cost = $turnover * $costRate
    $value = $value - $cost
    $target = $value / $TopN

    # 4) Yeni holdingler.
    $holdings = @{}
    foreach ($x in $selected) { if ($x.Price -gt 0) { $holdings[$x.Symbol] = $target / $x.Price } }

    # 5) Drawdown.
    if ($value -gt $peak) { $peak = $value }
    $dd = if ($peak -gt 0) { (($value / $peak) - 1.0) * 100.0 } else { 0.0 }
    if ($dd -lt $maxDd) { $maxDd = $dd }
    [void]$valuePath.Add([pscustomobject]@{ Date = $rd; Value = [Math]::Round($value, 0); N = $selected.Count })
}

# Son: bugune mark-to-market.
if ($holdings.Count -gt 0) {
    $mv = 0.0
    foreach ($sym in @($holdings.Keys)) {
        $p = Get-CloseOnOrBefore -Series $priceMap[$sym] -Date $today
        if ($null -ne $p) { $mv += [double]$holdings[$sym] * $p }
    }
    if ($mv -gt 0) { $value = $mv }
}

$stratReturn = (($value / $InitialCapital) - 1.0) * 100.0
$bistStart = Get-CloseOnOrBefore -Series $bist -Date $rebalanceDates[0]
$bistEnd = Get-CloseOnOrBefore -Series $bist -Date $today
$bistReturn = if ($null -ne $bistStart -and $bistStart -gt 0) { (($bistEnd / $bistStart) - 1.0) * 100.0 } else { $null }

Write-Host ""
Write-Host "=== SONUC ($($StartDate.ToString('MMM yyyy')) -> $($today.ToString('MMM yyyy'))) ==="
Write-Host ("Baslangic: {0:N0} TL" -f $InitialCapital)
Write-Host ("Strateji (momentum 12-1, top $TopN, aylik, ~$CostBps bps maliyet): {0:N0} TL  | toplam getiri %{1:N1}  | maks dusus %{2:N1}" -f $value, $stratReturn, $maxDd)
if ($null -ne $bistReturn) {
    $bistFinal = $InitialCapital * ($bistEnd / $bistStart)
    Write-Host ("BIST100 al-tut: {0:N0} TL  | toplam getiri %{1:N1}" -f $bistFinal, $bistReturn)
    Write-Host ("ALFA (strateji - BIST100): %{0:N1}" -f ($stratReturn - $bistReturn))
}
Write-Host ""
Write-Host "=== Aylik deger yolu (TL) ==="
foreach ($v in $valuePath) { Write-Host ("{0}  {1,12:N0}  (N={2})" -f $v.Date.ToString('yyyy-MM-dd'), $v.Value, $v.N) }
Write-Host "=== Backtest tamam ($([int]((Get-Date)-$startedAt).TotalSeconds) sn) ==="
