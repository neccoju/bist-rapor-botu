#requires -Version 5.1
<#
    Simulate-RebalanceSeparation.ps1 — Strateji ayrismasi GERCEK-VERI dogrulamasi.

    30 Haziran (varsayilan) tarihli bir ay-sonu rebalance'i, GUNCEL canli BIST
    taramasiyla simule eder ve 6 model portfoyun holding'lerini + ciftler arasi
    ortusmeyi raporlar. Amac: secim siralamasinin strateji-spesifik alt-skora
    baglanmasi (Get-StrategySelectionScore) sonrasi Dengeli/Momentum ve
    Deger/Kalite portfoylerinin gercekten ayristigini canli veriyle gostermek.

    GERCEK STATE'E DOKUNMAZ: data/model_portfolios.json okunmaz/yazilmaz; yalniz
    bellekte New-ModelPortfolioSet ile kurar ve log'a yazar.

    NOT: "30 Haziran verisi" gelecekte oldugundan tarama BUGUNUN verisiyle yapilir;
    bu, mekanizmanin (ayrisma) dogru calistiginin kanitidir, gercek 30 Haziran
    secimlerinin birebir kopyasi degildir (o gune kadar fiyat/temel veri degisir).
#>
param(
    [datetime]$AsOf = ([datetime]'2026-06-30T18:15:00'),
    [double]$InitialCapital = 100000,
    [double]$CostBps = 20
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BistScanner.Core.psm1') -Force

Write-Host "=== Strateji ayrismasi simulasyonu (AsOf=$($AsOf.ToString('yyyy-MM-dd'))) ==="
$stocks = @(Invoke-BistStockScan)
Write-Host "Taranan hisse: $($stocks.Count)"
if ($stocks.Count -eq 0) { Write-Host 'Tarama bos; cikiliyor.'; return }

# Akilli para verilerini isle ve etkiyi raporla (GunlukRapor ile ayni sira).
$stocks = @(Add-ForeignOwnershipData -Stocks $stocks)
$stocks = @(Add-InsiderSignalData -Stocks $stocks -AsOf $AsOf)
$withForeign = @($stocks | Where-Object { $null -ne (Get-ObjectPropertyValue -Object $_ -Name 'ForeignChg1wBps') })
Write-Host ("Yabanci oran verisi eslesen hisse: {0}/{1}" -f $withForeign.Count, $stocks.Count)
$smSample = @($stocks | ForEach-Object {
        $adj = Get-SmartMoneyAdjustment -Stock $_
        if ($adj -ne 0) { [pscustomobject]@{ Symbol = $_.Symbol; Adj = $adj; Chg1w = (Get-ObjectPropertyValue -Object $_ -Name 'ForeignChg1wBps') } }
    } | Where-Object { $_ })
Write-Host ("Sifir-disi akilli para ayari alan hisse: {0}" -f $smSample.Count)
foreach ($row in @($smSample | Sort-Object Adj -Descending | Select-Object -First 5)) {
    Write-Host ("  + {0,-8} ayar={1,5:N1}  1H={2}" -f $row.Symbol, $row.Adj, $row.Chg1w)
}
foreach ($row in @($smSample | Sort-Object Adj | Select-Object -First 5)) {
    Write-Host ("  - {0,-8} ayar={1,5:N1}  1H={2}" -f $row.Symbol, $row.Adj, $row.Chg1w)
}

$bist100 = 0.0
try {
    $idx = Get-BistIndexBenchmarks -TimeoutSec 20
    $bist100 = [double](Get-ObjectPropertyValue -Object (Get-ObjectPropertyValue -Object $idx -Name 'Bist100') -Name 'Price')
}
catch { Write-Host "BIST100 seviyesi alinamadi (onemsiz): $($_.Exception.Message)" }

# GERCEK STATE'E DOKUNMADAN tum portfoyleri sifirdan kur.
$set = New-ModelPortfolioSet -Stocks $stocks -AsOf $AsOf -InitialCapital $InitialCapital -BenchmarkLevel $bist100 -CostBps $CostBps

Write-Host ""
Write-Host "=== Simule edilen portfoyler (her biri 5 hisse) ==="
$holdingsByName = [ordered]@{}
foreach ($p in $set.Portfolios) {
    $syms = @($p.Holdings | ForEach-Object { [string]$_.Symbol } | Sort-Object)
    $holdingsByName[[string]$p.Name] = $syms
    Write-Host ("{0,-28} [{1,-8}] -> {2}" -f $p.Name, $p.Strategy, ($syms -join ', '))
}

function Get-Overlap {
    param([string[]]$A, [string[]]$B)
    return @($A | Where-Object { $B -contains $_ }).Count
}

# Onceden ayni cikan ciftleri ozellikle kontrol et
$names = @($holdingsByName.Keys)
function Find-Name { param([string]$Needle) ($names | Where-Object { $_ -like "*$Needle*" } | Select-Object -First 1) }
$nDengeli = Find-Name 'Dengeli Model'
$nMomentum = Find-Name 'Momentum'
$nDeger = Find-Name 'Değer'
$nKalite = Find-Name 'Kalite'

Write-Host ""
Write-Host "=== Onceden cakisan ciftlerin ayrismasi ==="
foreach ($pair in @(@($nDengeli, $nMomentum, 'Dengeli vs Momentum'), @($nDeger, $nKalite, 'Değer vs Kalite'))) {
    $a = $pair[0]; $b = $pair[1]; $label = $pair[2]
    if ($a -and $b) {
        $ov = Get-Overlap -A $holdingsByName[$a] -B $holdingsByName[$b]
        $verdict = if ($ov -le 3) { 'AYRISMIS' } else { 'HALA BENZER' }
        Write-Host ("{0,-20}: ortak {1}/5  -> {2}" -f $label, $ov, $verdict)
        Write-Host ("    {0}: {1}" -f $a, ($holdingsByName[$a] -join ', '))
        Write-Host ("    {0}: {1}" -f $b, ($holdingsByName[$b] -join ', '))
    }
}

Write-Host ""
Write-Host "=== Tum ciftler ortusme matrisi (ortak hisse / 5) ==="
for ($i = 0; $i -lt $names.Count; $i++) {
    for ($j = $i + 1; $j -lt $names.Count; $j++) {
        $ov = Get-Overlap -A $holdingsByName[$names[$i]] -B $holdingsByName[$names[$j]]
        Write-Host ("{0,-26} <-> {1,-26} : {2}/5" -f $names[$i], $names[$j], $ov)
    }
}
Write-Host ""
Write-Host "=== Simulasyon tamam (gercek state'e dokunulmadi) ==="
