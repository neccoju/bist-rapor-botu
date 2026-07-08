#requires -Version 5.1
<#
    Invoke-SignalEvaluation.ps1 — akilli-para/rejim AYARLARININ gercek ongoruculugu.

    PIT arsivinden (pit-archive -> data/pit) as-observed ayar alanlarini (Score,
    SmartMoneyAdjustment, MacroRegimeAdjustment, ForeignChg1wBps) + ~1 ay ileri
    getiriyi eslestirir ve:
      1) AYAR IC'si: her ayarin kesitsel IC'si (Pearson; ayar <-> ileri getiri),
         donemler arasi ortalama + t-istatistigi.
      2) REJIM AYRISMASI: Macro.RegimeLabel'e gore risk-on vs risk-off gunlerinin
         ortalama ileri getirisi (rejim motorunun kendi dogrulamasi).
    Sonuc + ONCEDEN TAAHHUT EDILMIS cikis kurali (Get-SignalVerdict) ile karar
    onerileri data/signal_evaluation.json'a yazilir. CANLI AGIRLIKLARI OTOMATIK
    DEGISTIRMEZ — kullanici karar verir (kasitli: az veride otomatik oynamak riskli).

    VERI KAPISI: yeterli bagimsiz donem (MinPeriods) yoksa exit 0 + "N donem daha".
    Cakismayan donemler (auto-calibrate ile ayni desen) otokorelasyon sismesini onler.
#>
[CmdletBinding()]
param(
    [string]$PitDir = (Join-Path $PSScriptRoot 'data/pit'),
    [string]$OutPath = (Join-Path $PSScriptRoot 'data/signal_evaluation.json'),
    [int]$HorizonDays = 30,
    [int]$HorizonMaxDays = 45,
    [int]$MinPeriods = 6,
    [int]$MinObsPerPeriod = 10
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BistScanner.Core.psm1') -Force

Write-Host ('=' * 64)
Write-Host 'SINYAL DEGERLENDIRME — ayar IC + rejim ayrismasi (karar destek)'
Write-Host ('=' * 64)

if (-not (Test-Path -LiteralPath $PitDir)) { Write-Warning "PIT dizini yok: $PitDir — degerlendirme atlandi."; exit 0 }
$files = @(Get-ChildItem -LiteralPath $PitDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)
Write-Host "PIT snapshot: $($files.Count)"
if ($files.Count -lt ($MinPeriods + 1)) { Write-Warning "Yetersiz snapshot ($($files.Count)); >= $($MinPeriods + 1) gerekli."; exit 0 }

# Snapshotlari yukle: tarih, symbol->constituent, rejim etiketi.
$snaps = New-Object System.Collections.Generic.List[object]
foreach ($f in $files) {
    try { $obj = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
    $dt = $null; try { $dt = [datetime](Get-ObjectPropertyValue -Object $obj -Name 'AsOf') } catch { $dt = $null }
    if ($null -eq $dt) { continue }
    $map = @{}
    foreach ($c in @(Get-ObjectPropertyValue -Object $obj -Name 'Constituents')) {
        $sym = [string](Get-ObjectPropertyValue -Object $c -Name 'Symbol')
        if ($sym) { $map[$sym] = $c }
    }
    $regime = Get-ObjectPropertyValue -Object (Get-ObjectPropertyValue -Object $obj -Name 'Macro') -Name 'RegimeLabel'
    if ($map.Count -gt 0) { [void]$snaps.Add([pscustomobject]@{ Date = $dt; Map = $map; Regime = [string]$regime }) }
}
$snaps = @($snaps | Sort-Object Date)
Write-Host "Gecerli snapshot: $($snaps.Count)"

# Cakismayan walk-forward donemler.
$adjFields = @('SmartMoneyAdjustment', 'MacroRegimeAdjustment', 'ForeignChg1wBps')
$icByField = @{}; foreach ($fn in $adjFields) { $icByField[$fn] = New-Object System.Collections.Generic.List[double] }
$regimeFwd = @{ 'risk-on' = (New-Object System.Collections.Generic.List[double]); 'risk-off' = (New-Object System.Collections.Generic.List[double]); 'neutral' = (New-Object System.Collections.Generic.List[double]) }
$periodsUsed = 0
$nextEligible = [datetime]::MinValue

for ($i = 0; $i -lt $snaps.Count; $i++) {
    $d0 = $snaps[$i].Date
    if ($d0 -lt $nextEligible) { continue }
    $fwd = $null
    for ($j = $i + 1; $j -lt $snaps.Count; $j++) {
        $gap = ($snaps[$j].Date - $d0).TotalDays
        if ($gap -ge ($HorizonDays - 4)) { if ($gap -le $HorizonMaxDays) { $fwd = $snaps[$j] }; break }
    }
    if ($null -eq $fwd) { continue }

    # Kesit: her hisse icin ileri getiri + ayar degerleri.
    $rets = New-Object System.Collections.Generic.List[double]
    $vals = @{}; foreach ($fn in $adjFields) { $vals[$fn] = New-Object System.Collections.Generic.List[double] }
    $retForField = @{}; foreach ($fn in $adjFields) { $retForField[$fn] = New-Object System.Collections.Generic.List[double] }
    foreach ($sym in $snaps[$i].Map.Keys) {
        if (-not $fwd.Map.ContainsKey($sym)) { continue }
        $p0 = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $snaps[$i].Map[$sym] -Name 'Price')
        $p1 = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $fwd.Map[$sym] -Name 'Price')
        if ($null -eq $p0 -or $null -eq $p1 -or $p0 -le 0) { continue }
        $ret = ($p1 / $p0 - 1.0) * 100.0
        [void]$rets.Add($ret)
        foreach ($fn in $adjFields) {
            $v = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $snaps[$i].Map[$sym] -Name $fn)
            if ($null -ne $v) { [void]$vals[$fn].Add($v); [void]$retForField[$fn].Add($ret) }
        }
    }
    if ($rets.Count -lt $MinObsPerPeriod) { continue }
    $periodsUsed++
    $nextEligible = $d0.AddDays($HorizonDays)

    foreach ($fn in $adjFields) {
        if ($vals[$fn].Count -ge $MinObsPerPeriod) {
            $ic = Get-PearsonCorrelation -X $vals[$fn].ToArray() -Y $retForField[$fn].ToArray()
            if ($null -ne $ic) { [void]$icByField[$fn].Add([double]$ic) }
        }
    }
    $reg = [string]$snaps[$i].Regime
    if ($regimeFwd.ContainsKey($reg)) {
        $meanRet = ($rets | Measure-Object -Average).Average
        [void]$regimeFwd[$reg].Add([double]$meanRet)
    }
}

Write-Host "Bagimsiz donem: $periodsUsed (gereken min: $MinPeriods)"
if ($periodsUsed -lt $MinPeriods) {
    Write-Host "Henuz yeterli bagimsiz donem yok ($($MinPeriods - $periodsUsed) donem daha). Degerlendirme atlandi."
    exit 0
}

# Ayar bulgulari + cikis kurali karari.
$findings = @()
foreach ($fn in $adjFields) {
    $ics = @($icByField[$fn].ToArray())
    if ($ics.Count -lt 2) {
        $findings += [pscustomobject]@{ signal = $fn; samples = $ics.Count; meanIC = $null; tStat = $null; verdict = 'YETERSIZ' }
        continue
    }
    $mean = ($ics | Measure-Object -Average).Average
    $var = 0.0; foreach ($x in $ics) { $var += ($x - $mean) * ($x - $mean) }
    $sd = [Math]::Sqrt($var / ($ics.Count - 1))
    $t = if ($sd -gt 1e-12) { $mean / ($sd / [Math]::Sqrt($ics.Count)) } else { [Math]::Sign($mean) * 99.0 }
    $verdict = Get-SignalVerdict -MeanIC $mean -TStat $t -Samples $ics.Count -MinSamples $MinPeriods
    $findings += [pscustomobject]@{
        signal = $fn; samples = $ics.Count
        meanIC = [Math]::Round($mean, 4); tStat = [Math]::Round($t, 2)
        verdict = $verdict.verdict; action = $verdict.action; reason = $verdict.reason
    }
    Write-Host ("  {0,-24} IC={1,7} t={2,6} -> {3} ({4})" -f $fn, [Math]::Round($mean, 4), [Math]::Round($t, 2), $verdict.verdict, $verdict.action)
}

$regimeSummary = @($regimeFwd.Keys | ForEach-Object {
        $arr = @($regimeFwd[$_].ToArray())
        [pscustomobject]@{ regime = $_; days = $arr.Count; meanFwdRetPct = if ($arr.Count) { [Math]::Round(($arr | Measure-Object -Average).Average, 2) } else { $null } }
    })
$onMean = ($regimeSummary | Where-Object { $_.regime -eq 'risk-on' }).meanFwdRetPct
$offMean = ($regimeSummary | Where-Object { $_.regime -eq 'risk-off' }).meanFwdRetPct
$regimeWorks = ($null -ne $onMean -and $null -ne $offMean -and $onMean -gt $offMean)
Write-Host ("Rejim ayrismasi: risk-on {0}% vs risk-off {1}% -> {2}" -f $onMean, $offMean, $(if ($regimeWorks) { 'BEKLENEN YON' } else { 'ZAYIF/TERS' }))

$payload = [pscustomobject][ordered]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    periodsUsed = $periodsUsed
    horizonDays = $HorizonDays
    note = 'Ayar IC + rejim ileri-getiri ayrismasi. CANLI AGIRLIKLARI DEGISTIRMEZ; Get-SignalVerdict cikis kurali onerisidir, karar kullaniciya aittir.'
    adjustments = $findings
    regime = [pscustomobject]@{ summary = $regimeSummary; separationAsExpected = $regimeWorks }
}
$dir = Split-Path -Parent $OutPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutPath -Encoding UTF8
Write-Host "DEGERLENDIRME -> $OutPath ($periodsUsed donem). Oneriler karar destek amaclidir."
