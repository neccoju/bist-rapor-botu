#requires -Version 5.1
<#
    Invoke-CreateMissingPortfolios.ps1 - tanimda olup state'te OLMAYAN model
    portfoyleri olusturur; MEVCUT portfoylere HIC dokunmaz (rebalance yok,
    valuation yok - yalniz eksikleri ekler).

    Kullanim amaci: yeni portfoy tanimi (or. Kesif) eklendiginde ay-sonunu
    beklemeden manuel baslatma (kullanici istegi: 'su an manuel baslatabilirsin').
    Ayni is otomatik olarak bir sonraki gunluk kosuda da olur (migration yolu);
    bu script yalniz 'bugun baslat' icindir. -Apply verilmezse KURU KOSU.
#>
param(
    [datetime]$AsOf = (Get-Date),
    [double]$CostBps = 50,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BistScanner.Core.psm1') -Force

$statePath = Join-Path $PSScriptRoot 'data\model_portfolios.json'
if (-not (Test-Path -LiteralPath $statePath)) { throw "State dosyasi yok: $statePath" }
$set = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
$existingIds = @(@($set.Portfolios) | ForEach-Object { [string]$_.Id })
$missing = @(Get-ModelPortfolioDefinitions | Where-Object { [string]$_.Id -notin $existingIds })
if ($missing.Count -eq 0) { Write-Host 'Eksik portfoy yok; yapilacak is yok.'; exit 0 }
Write-Host ("Eksik portfoyler: " + (@($missing | ForEach-Object { $_.Id }) -join ', '))

# Evren + zenginlestirme - GunlukRapor ile AYNI sira/kaynaklar (Kesif skoru
# bilanco kalitesi, yabanci oran, insider ve AdvTL alanlarini kullanir).
$stocks = @(Invoke-BistStockScan)
Write-Host "Taranan hisse: $($stocks.Count)"
if ($stocks.Count -lt 100) { throw "Tarama supheli derecede kucuk ($($stocks.Count)); iptal." }
try { $stocks = @(Add-HoldingFlag -Stocks $stocks) } catch { Write-Warning $_.Exception.Message }
try { $stocks = @(Add-ForeignOwnershipData -Stocks $stocks) } catch { Write-Warning $_.Exception.Message }
try { $stocks = @(Add-InsiderSignalData -Stocks $stocks -AsOf $AsOf) } catch { Write-Warning $_.Exception.Message }
try { $stocks = @(Add-BalanceSheetQuality -Stocks $stocks) } catch { Write-Warning $_.Exception.Message }
try { $stocks = @(Add-FundamentalCrossCheck -Stocks $stocks) } catch { Write-Warning $_.Exception.Message }

$bist100Level = 0.0
try {
    $idx = Get-BistIndexBenchmarks -TimeoutSec 20
    $bist100Level = [double](Get-ObjectPropertyValue -Object (Get-ObjectPropertyValue -Object $idx -Name 'Bist100') -Name 'Price')
}
catch { Write-Host "BIST100 seviyesi alinamadi: $($_.Exception.Message)" }

$created = [System.Collections.Generic.List[object]]::new()
foreach ($definition in $missing) {
    try {
        $p = New-SingleModelPortfolio -Definition $definition -Stocks $stocks -AsOf $AsOf -BenchmarkLevel $bist100Level -CostBps $CostBps
        [void]$created.Add($p)
        $syms = @($p.Holdings | ForEach-Object { ('{0} (%{1})' -f $_.Symbol, [Math]::Round([double]$_.TargetWeightPct, 0)) }) -join ', '
        Write-Host ("OLUSTU: {0} - sermaye {1:N0} TL -> {2}" -f $p.Name, [double]$p.InitialCapitalTL, $syms)
    }
    catch {
        Write-Warning ("{0} kurulamadi: {1}" -f $definition.Id, $_.Exception.Message)
    }
}
if ($created.Count -eq 0) { Write-Host 'Hicbir eksik portfoy kurulamadi (aday havuzu yetersiz olabilir); state degismedi.'; exit 0 }

if (-not $Apply) { Write-Host 'KURU KOSU: -Apply verilmedi; state yazilmadi.'; exit 0 }

# Yalniz EKLE - mevcut portfoy objeleri birebir korunur.
$set.Portfolios = @(@($set.Portfolios) + @($created.ToArray()))
$set.UpdatedAt = $AsOf.ToString('o')
$json = ConvertTo-Json -InputObject $set -Depth 12
[IO.File]::WriteAllText($statePath, $json, [Text.UTF8Encoding]::new($true))
Write-Host ("State guncellendi: {0} yeni portfoy eklendi -> {1}" -f $created.Count, $statePath)
