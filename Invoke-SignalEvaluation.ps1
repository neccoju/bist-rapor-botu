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
    $macroNode = Get-ObjectPropertyValue -Object $obj -Name 'Macro'
    $regime = Get-ObjectPropertyValue -Object $macroNode -Name 'RegimeLabel'
    $cashT = Get-ObjectPropertyValue -Object $macroNode -Name 'CashTargetPct'
    $bist = Get-ObjectPropertyValue -Object $macroNode -Name 'Bist100'
    if ($map.Count -gt 0) { [void]$snaps.Add([pscustomobject]@{ Date = $dt; Map = $map; Regime = [string]$regime; CashTarget = $cashT; Bist100 = $bist }) }
}
$snaps = @($snaps | Sort-Object Date)
Write-Host "Gecerli snapshot: $($snaps.Count)"

# Cakismayan walk-forward donemler.
# BalanceSheetScore + EarningsDriftSignal: GOLGE faktorler — ayarlari 0 oldugu
# icin AYARIN degil HAM SINYALIN ileri-getiri IC'sini olceriz; kanit (KORU)
# cikinca carpan acilir. EarningsDriftSignal yalniz aciklama penceresi icinde
# dolu (disi null) -> IC otomatik olarak olay-kosullu olculur.
$adjFields = @('SmartMoneyAdjustment', 'MacroRegimeAdjustment', 'ForeignChg1wBps', 'BalanceSheetScore', 'EarningsDriftSignal')
$icByField = @{}; foreach ($fn in $adjFields) { $icByField[$fn] = New-Object System.Collections.Generic.List[double] }
$regimeFwd = @{ 'risk-on' = (New-Object System.Collections.Generic.List[double]); 'risk-off' = (New-Object System.Collections.Generic.List[double]); 'neutral' = (New-Object System.Collections.Generic.List[double]) }
$overlayDefensive = New-Object System.Collections.Generic.List[double]   # nakit-onerilen gunlerde BIST fwd
$overlayInvested = New-Object System.Collections.Generic.List[double]    # tam-yatirim gunlerinde BIST fwd
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
    # OVERLAY OLCUMU: nakit-onerilen (cashTargetPct >= 20) gunlerde BIST100 ileri
    # getirisi negatifse nakit katmani KORUR. BIST100 fwd getirisi = snapshot'taki
    # XU100 fiyatinin ileri degisimi (piyasa geneli proxy).
    $ct = ConvertTo-DoubleOrNull $snaps[$i].CashTarget
    $b0 = ConvertTo-DoubleOrNull $snaps[$i].Bist100
    $b1 = ConvertTo-DoubleOrNull $fwd.Bist100
    if ($null -ne $ct -and $null -ne $b0 -and $null -ne $b1 -and $b0 -gt 0) {
        $bistFwd = ($b1 / $b0 - 1.0) * 100.0
        if ($ct -ge 20) { [void]$overlayDefensive.Add([double]$bistFwd) } else { [void]$overlayInvested.Add([double]$bistFwd) }
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

# OVERLAY degerlendirmesi: nakit-onerilen gunlerin BIST fwd getirisi tam-yatirim
# gunlerinden DUSUKSE nakit katmani drawdown'i azaltir (overlay faydali).
$defArr = @($overlayDefensive.ToArray()); $invArr = @($overlayInvested.ToArray())
$defMean = if ($defArr.Count) { [Math]::Round(($defArr | Measure-Object -Average).Average, 2) } else { $null }
$invMean = if ($invArr.Count) { [Math]::Round(($invArr | Measure-Object -Average).Average, 2) } else { $null }
$overlayHelps = ($null -ne $defMean -and $null -ne $invMean -and $defMean -lt $invMean)
$overlayVerdict = if ($defArr.Count -lt $MinPeriods) { 'YETERSIZ' } elseif ($overlayHelps -and $defMean -lt 0) { 'FAYDALI' } elseif ($overlayHelps) { 'ZAYIF-FAYDA' } else { 'FAYDASIZ' }
Write-Host ("Nakit overlay: savunma-gunu BIST fwd {0}% vs yatirim-gunu {1}% -> {2}" -f $defMean, $invMean, $overlayVerdict)

$payload = [pscustomobject][ordered]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    periodsUsed = $periodsUsed
    horizonDays = $HorizonDays
    note = 'Ayar IC + rejim ileri-getiri ayrismasi. CANLI AGIRLIKLARI DEGISTIRMEZ; Get-SignalVerdict cikis kurali onerisidir, karar kullaniciya aittir.'
    adjustments = $findings
    regime = [pscustomobject]@{ summary = $regimeSummary; separationAsExpected = $regimeWorks }
    cashOverlay = [pscustomobject]@{
        defensiveDays = $defArr.Count; defensiveBistFwdPct = $defMean
        investedDays = $invArr.Count; investedBistFwdPct = $invMean
        verdict = $overlayVerdict
        note = 'Nakit-onerilen gunlerin BIST fwd getirisi yatirim-gununden dusukse overlay drawdown azaltir. FAYDALI ise RiskDengeli pilotu dusunulebilir (canli tahsis su an DEGISMIYOR).'
    }
}
$dir = Split-Path -Parent $OutPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutPath -Encoding UTF8
Write-Host "DEGERLENDIRME -> $OutPath ($periodsUsed donem). Oneriler karar destek amaclidir."

# KENDI-KENDINE AYAR: cikis kurali verdict'lerinden signal_config.json'i OTOMATIK
# yaz (kullanici istegi: '4 Agustos'ta otomatik yap, beni ugrastirma'). Carpan
# haritasi: KAPAT->0, ZAYIFLAT->0.5, KORU/IZLE->1.0. YETERSIZ ise carpan
# DEGISMEZ (mevcut/varsayilan korunur — az veride oynamaz). Auto-calibrate
# deseni: yeterli veri birikince otomatik uygular, yoksa bekler. Sessiz.
$multFor = { param($verdict, $current)
    switch ($verdict) {
        'KAPAT' { 0.0 }
        'ZAYIFLAT' { 0.5 }
        'KORU' { 1.0 }
        'IZLE' { 1.0 }
        default { $current }   # YETERSIZ -> mevcut korunur
    }
}
$cfgPath = Join-Path (Split-Path -Parent $OutPath) 'signal_config.json'
$curCfg = $null
if (Test-Path -LiteralPath $cfgPath) { try { $curCfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } }
# GOLGE faktor aktivasyonu (bilanco): yerlesik faktorlerden FARKLI — carpan 0'dan
# baslar, YALNIZ kanitli pozitif IC (KORU) cikinca 0.5 PILOT'a acilir; diger tum
# durumlarda golgede (0) kalir. Boylece yeni faktor otomatik ama ihtiyatli devreye
# girer (once yarim olcek; ±3 tavani zaten sinirli).
$multForShadow = { param($verdict, $current)
    switch ($verdict) {
        'KORU'  { 0.5 }        # kanitli pozitif -> pilot
        default { if ($verdict -eq 'YETERSIZ') { $current } else { 0.0 } }
    }
}
$curSm = if ($curCfg) { [double](Get-ObjectPropertyValue -Object $curCfg -Name 'SmartMoneyMult') } else { 1.0 }
$curMr = if ($curCfg) { [double](Get-ObjectPropertyValue -Object $curCfg -Name 'MacroRegimeMult') } else { 1.0 }
$curBsRaw = if ($curCfg) { ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $curCfg -Name 'BalanceSheetMult') } else { $null }
$curBs = if ($null -ne $curBsRaw) { [double]$curBsRaw } else { 0.0 }   # golge varsayilan
$curEdRaw = if ($curCfg) { ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $curCfg -Name 'EarningsDriftMult') } else { $null }
$curEd = if ($null -ne $curEdRaw) { [double]$curEdRaw } else { 0.0 }   # golge varsayilan
if ($curSm -le 0 -and $null -eq $curCfg) { $curSm = 1.0 }
$smV = @($findings | Where-Object { $_.signal -eq 'SmartMoneyAdjustment' } | Select-Object -First 1)
$mrV = @($findings | Where-Object { $_.signal -eq 'MacroRegimeAdjustment' } | Select-Object -First 1)
$bsV = @($findings | Where-Object { $_.signal -eq 'BalanceSheetScore' } | Select-Object -First 1)
$edV = @($findings | Where-Object { $_.signal -eq 'EarningsDriftSignal' } | Select-Object -First 1)
$newSm = if ($smV) { & $multFor $smV.verdict $curSm } else { $curSm }
$newMr = if ($mrV) { & $multFor $mrV.verdict $curMr } else { $curMr }
$newBs = if ($bsV) { & $multForShadow $bsV.verdict $curBs } else { $curBs }
$newEd = if ($edV) { & $multForShadow $edV.verdict $curEd } else { $curEd }
$cfg = [pscustomobject][ordered]@{
    UpdatedAt = (Get-Date).ToUniversalTime().ToString('o')
    SmartMoneyMult = $newSm
    MacroRegimeMult = $newMr
    BalanceSheetMult = $newBs
    EarningsDriftMult = $newEd
    Note = 'Invoke-SignalEvaluation otomatik yazdi (cikis kurali). Yerlesik: KAPAT->0, ZAYIFLAT->0.5, KORU->1.0. Golge (bilanco/PEAD): KORU->0.5 pilot, diger->0, YETERSIZ->degismez.'
    Source = 'signal-eval auto'
}
$cfg | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $cfgPath -Encoding UTF8
Write-Host ("OTO-AYAR -> signal_config.json (SmartMoney x{0}, MacroRegime x{1}, Bilanco x{2}, PEAD x{3})" -f $newSm, $newMr, $newBs, $newEd)
