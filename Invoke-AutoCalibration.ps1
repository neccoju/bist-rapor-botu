#requires -Version 5.1
<#
    Invoke-AutoCalibration.ps1 — KENDI KENDINE OGRENME (kendi icinde suren dongu).

    Her ay otomatik calisir; yeterli BAGIMSIZ donem birikene kadar prior'u korur
    (commit/main degisikligi YOK) ve bir sonraki ay tekrar dener — hazir oldugu an
    ogrenir ve yeni model uretir.

    PIT (point-in-time) anlik goruntu arsivinden (pit-archive branch -> -PitDir)
    survivorship/look-ahead'siz bir WALK-FORWARD degerlendirme yapar ve RFS100
    portfoyunun faktor agirliklarini (RawFactorScore) yeniden ogrenir. Sonuc
    data/learned_factor_weights.json'a yazilir; GunlukRapor/BistScanner bu dosyayi
    varsa kullanir (yoksa statik varsayilana duser).

    DURUSTLUK & ASIRI-UYUM KORUMASI:
    - Yontem: faktor basina kesitsel IC (Pearson; faktor <-> ileri getiri), donemler
      arasi ortalama. Cok-degiskenli regresyonun overfit/multikolinearite riski yok.
    - Prior'a dogru BUZULME (shrinkage, lambda) -> agirliklar yavas degisir.
    - VERI KAPISI: yeterli donem (MinPeriods) birikene kadar HICBIR SEY degismez
      (PIT arsivi yeni basladigindan ilk ~3 ay boyunca prior korunur — dogal/dürüst).
    - Yalniz RFS100 "ogrenme kanadini" etkiler; diger 5 portfoyun el-ayarli skoru
      degismez (tum botu overfit etme riski alinmaz).

    Cikti yoksa/yetersizse exit 0 (akis bozulmaz).
#>
[CmdletBinding()]
param(
    [string]$PitDir = (Join-Path $PSScriptRoot 'data/pit'),
    [string]$OutPath = (Join-Path $PSScriptRoot 'data/learned_factor_weights.json'),
    [int]$HorizonDays = 30,        # ileri getiri ufku (takvim gunu; ~1 ay)
    [int]$HorizonMaxDays = 45,     # eslesme penceresi ust siniri
    [int]$MinPeriods = 8,          # bu kadar gecerli donem olmadan ogrenme YOK
    [int]$MinObsPerPeriod = 10,
    [double]$Lambda = 0.30
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BistScanner.Core.psm1') -Force

Write-Host ('=' * 64)
Write-Host 'KENDI KENDINE OGRENME — RFS faktor agirligi oto-kalibrasyon'
Write-Host ('=' * 64)

# Prior (mevcut) agirliklar: ogrenilmis varsa onu, yoksa STATIK temel cizgi
# (Get-StaticFactorWeights — RFS100 ile tek kaynak).
$prior = Get-LearnedFactorWeights
if (-not $prior) { $prior = Get-StaticFactorWeights }

if (-not (Test-Path -LiteralPath $PitDir)) {
    Write-Warning "PIT dizini yok: $PitDir — ogrenme atlandi (prior korunur)."
    exit 0
}
$files = @(Get-ChildItem -LiteralPath $PitDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)
Write-Host "PIT snapshot dosyasi: $($files.Count)"
if ($files.Count -lt ($MinPeriods + 1)) {
    Write-Warning "Yetersiz snapshot ($($files.Count)); en az $($MinPeriods + 1) gerekli. Ogrenme atlandi."
    exit 0
}

# Snapshotlari yukle: tarih + symbol->constituent haritasi.
$snaps = New-Object System.Collections.Generic.List[object]
foreach ($f in $files) {
    try {
        $obj = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch { continue }
    $asof = Get-ObjectPropertyValue -Object $obj -Name 'AsOf'
    $dt = $null; try { $dt = [datetime]$asof } catch { $dt = $null }
    if ($null -eq $dt) { continue }
    $map = @{}
    foreach ($c in @(Get-ObjectPropertyValue -Object $obj -Name 'Constituents')) {
        $sym = [string](Get-ObjectPropertyValue -Object $c -Name 'Symbol')
        if (-not [string]::IsNullOrWhiteSpace($sym)) { $map[$sym] = $c }
    }
    if ($map.Count -gt 0) { [void]$snaps.Add([pscustomobject]@{ Date = $dt; Map = $map }) }
}
$snaps = @($snaps | Sort-Object Date)
Write-Host "Gecerli snapshot: $($snaps.Count)"

# Walk-forward donemler: her snapshot D icin ~Horizon gun sonraki snapshot ile ileri getiri.
# CAKISMAYAN (bagimsiz) donemler: bir donem kullanildiktan sonra bir sonraki donem
# en az 1 ufuk (HorizonDays) sonra baslar — boylece IC ortalamasi otokorelasyonla
# sismez (yalanci-tekrar yok); MinPeriods gercek/bagimsiz aylik gozlem sayar.
$periods = New-Object System.Collections.Generic.List[object]
$nextEligible = [datetime]::MinValue
for ($i = 0; $i -lt $snaps.Count; $i++) {
    $d0 = $snaps[$i].Date
    if ($d0 -lt $nextEligible) { continue }   # cakismayan donem kapisi (bagimsizlik)
    $fwd = $null
    for ($j = $i + 1; $j -lt $snaps.Count; $j++) {
        $gap = ($snaps[$j].Date - $d0).TotalDays
        if ($gap -ge ($HorizonDays - 4)) {
            if ($gap -le $HorizonMaxDays) { $fwd = $snaps[$j] }
            break
        }
    }
    if ($null -eq $fwd) { continue }
    $obs = New-Object System.Collections.Generic.List[object]
    foreach ($sym in $snaps[$i].Map.Keys) {
        $c0 = $snaps[$i].Map[$sym]
        if (-not $fwd.Map.ContainsKey($sym)) { continue }   # delist/evren disi -> haric (dürüst kisit: hafif survivorship)
        $p0 = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $c0 -Name 'Price')
        $p1 = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $fwd.Map[$sym] -Name 'Price')
        if ($null -eq $p0 -or $null -eq $p1 -or $p0 -le 0) { continue }
        $ret = ($p1 / $p0 - 1.0) * 100.0
        $fac = Get-RawFactorVector -Stock $c0   # arsivlenen RSI/SMA/MACD/Perf alanlarindan
        # ordered-dict -> hashtable (Get-WalkForwardFactorWeights ContainsKey bekliyor)
        $fh = @{}; foreach ($k in $fac.Keys) { $fh[$k] = $fac[$k] }
        [void]$obs.Add([pscustomobject]@{ Factors = $fh; FwdRet = $ret })
    }
    if ($obs.Count -ge $MinObsPerPeriod) {
        [void]$periods.Add($obs.ToArray())
        $nextEligible = $d0.AddDays($HorizonDays)   # sonraki donem >= 1 ufuk sonra (cakisma yok)
    }
}
Write-Host "Bagimsiz walk-forward donem: $($periods.Count) (gereken min: $MinPeriods)"
if ($periods.Count -lt $MinPeriods) {
    $need = $MinPeriods - $periods.Count
    Write-Host "Henuz yeterli bagimsiz donem yok ($need donem daha gerekli)."
    Write-Host 'Ogrenme atlandi; prior korunur — bu kosu hicbir seyi degistirmez (main dokunulmaz).'
    Write-Host 'DONGU SURUYOR: arsiv biriktikce bir SONRAKI AY otomatik tekrar denenecek.'
    exit 0
}

$result = Get-WalkForwardFactorWeights -Periods $periods.ToArray() -PriorWeights $prior `
    -MinPeriods $MinPeriods -MinObsPerPeriod $MinObsPerPeriod -Lambda $Lambda
$diag = $result.Diagnostics

if (-not $diag.Applied) {
    Write-Host "SONUC: $($diag.Reason)"
    Write-Host 'Ogrenme uygulanmadi; mevcut/statik agirliklar korunuyor. (Arsiv biriktikce otomatik devreye girer.)'
    exit 0
}

$payload = [pscustomobject][ordered]@{
    GeneratedAt   = (Get-Date).ToUniversalTime().ToString('o')
    Method        = 'walk-forward cross-sectional IC + shrinkage'
    HorizonDays   = $HorizonDays
    Lambda        = $Lambda
    PeriodsUsed   = $diag.PeriodsUsed
    MeanIC        = $diag.MeanIC
    PriorWeights  = $prior
    Weights       = $result.Weights
    Note          = 'RFS100 faktor agirliklari; survivorship/look-ahead siniri: delist olanlar haric. Diger portfoyleri etkilemez.'
}
$dir = Split-Path -Parent $OutPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutPath -Encoding UTF8
Write-Host "OGRENILDI -> $OutPath ($($diag.PeriodsUsed) donem). Yeni agirliklar bir sonraki raporda RFS100'e uygulanir."
