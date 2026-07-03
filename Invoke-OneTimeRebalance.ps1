#requires -Version 5.1
<#
    Invoke-OneTimeRebalance.ps1 — BIR DEFALIK zorunlu model portfoy rebalance'i.

    Gerekce: akilli para verileri (yabanci saklama degisimi + insider KAP sinyali)
    2026-07-03'te skora katildi; kullanici onayiyla mevcut model portfoyler yeni
    kurguya gore BIR DEFAYA MAHSUS yeniden kurulur. Sonraki rebalance'lar yine
    normal ay-sonu dongusunde calisir.

    Yontem: state'teki her portfoyun LastRebalancePeriodEnd'i geriye cekilir ve
    TEST EDILMIS mevcut motor (Update-ModelPortfolioSet -AllowRebalance) calistirilir
    — satis/alis maliyet muhasebesi, agirlik/sektor tavani ve islem gecmisi
    birebir ayni yoldan gecer. -Apply verilmezse KURU KOSU: state'e yazilmaz.
#>
param(
    [datetime]$AsOf = (Get-Date),
    [double]$CostBps = 50,
    [double]$MaxBookPct = 15,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BistScanner.Core.psm1') -Force

$statePath = Join-Path $PSScriptRoot 'data\model_portfolios.json'
if (-not (Test-Path -LiteralPath $statePath)) { throw "State dosyasi yok: $statePath" }

Write-Host "=== Bir defalik rebalance (AsOf=$($AsOf.ToString('yyyy-MM-dd HH:mm')), Apply=$([bool]$Apply)) ==="
$stocks = @(Invoke-BistStockScan)
Write-Host "Taranan hisse: $($stocks.Count)"
if ($stocks.Count -lt 100) { throw "Tarama supheli derecede kucuk ($($stocks.Count)); rebalance iptal." }

# Akilli para verileri — GunlukRapor ile ayni sira/ayni kaynaklar.
$stocks = @(Add-ForeignOwnershipData -Stocks $stocks)
$stocks = @(Add-InsiderSignalData -Stocks $stocks -AsOf $AsOf)
$withForeign = @($stocks | Where-Object { $null -ne (Get-ObjectPropertyValue -Object $_ -Name 'ForeignChg1wBps') }).Count
Write-Host "Yabanci oran verisi eslesen hisse: $withForeign/$($stocks.Count)"

$bist100Level = 0.0
try {
    $idx = Get-BistIndexBenchmarks -TimeoutSec 20
    $bist100Level = [double](Get-ObjectPropertyValue -Object (Get-ObjectPropertyValue -Object $idx -Name 'Bist100') -Name 'Price')
}
catch { Write-Host "BIST100 seviyesi alinamadi: $($_.Exception.Message)" }

$set = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host ''
Write-Host '--- ONCE (mevcut holdingler) ---'
foreach ($p in @($set.Portfolios)) {
    $syms = @($p.Holdings | ForEach-Object { [string]$_.Symbol } | Sort-Object) -join ', '
    Write-Host ("{0,-28} deger={1,12:N0} TL -> {2}" -f $p.Name, [double]$p.CurrentValueTL, $syms)
    # Rebalance kapisini ac: son rebalance donemini geriye cek.
    $p | Add-Member -NotePropertyName 'LastRebalancePeriodEnd' -NotePropertyValue '2000-01-31T00:00:00' -Force
}

$updated = Update-ModelPortfolioSet -PortfolioSet $set -Stocks $stocks -AsOf $AsOf -AllowRebalance `
    -BenchmarkLevel $bist100Level -CostBps $CostBps -MaxBookPct $MaxBookPct
if ($null -eq $updated) { throw 'Update-ModelPortfolioSet null dondu; state korunuyor.' }

Write-Host ''
Write-Host '--- SONRA (yeni kurgu ile secim) ---'
foreach ($p in @($updated.Portfolios)) {
    $syms = @($p.Holdings | ForEach-Object { [string]$_.Symbol } | Sort-Object) -join ', '
    Write-Host ("{0,-28} deger={1,12:N0} TL -> {2}" -f $p.Name, [double]$p.CurrentValueTL, $syms)
}

if (-not $Apply) {
    Write-Host ''
    Write-Host 'KURU KOSU: -Apply verilmedi; state DEGISTIRILMEDI.'
    return
}

# Atomik yaz (GunlukRapor.Save-JsonFile ile ayni desen, sadelestirilmis).
$json = ConvertTo-Json -InputObject $updated -Depth 10
$tempPath = "$statePath.tmp"
[IO.File]::WriteAllText($tempPath, $json, [Text.UTF8Encoding]::new($true))
Move-Item -LiteralPath $tempPath -Destination $statePath -Force
Write-Host ''
Write-Host "State yazildi: $statePath (bir defalik rebalance tamam; sonraki dongu normal ay-sonu)"
