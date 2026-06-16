#!/usr/bin/env pwsh
<#
    Test-BacktestEngine.ps1 — AGSIZ, deterministik birim testleri.
    Event-driven motoru (BacktestEngine.psm1) elle hesaplanmis "golden" degerlerle
    dogrular: defter korunumu, maliyet muhasebesi, ADV likidite siniri, alim/satim
    gecisi ve metrik akli-basinda kontrolu. Ag gerektirmez; CI'da kapi gorevi gorur.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'BacktestEngine.psm1'
Import-Module $modulePath -Force

$script:Failures = 0
$script:Passed = 0

function Assert-Near {
    param([double]$Actual, [double]$Expected, [double]$Tol = 0.01, [string]$Message)
    if ([Math]::Abs($Actual - $Expected) -le $Tol) {
        $script:Passed++; Write-Host "  [PASS] $Message (=$Actual)" -ForegroundColor Green
    } else {
        $script:Failures++; Write-Host "  [FAIL] $Message : beklenen=$Expected gercek=$Actual" -ForegroundColor Red
    }
}
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { $script:Passed++; Write-Host "  [PASS] $Message" -ForegroundColor Green }
    else { $script:Failures++; Write-Host "  [FAIL] $Message" -ForegroundColor Red }
}

function New-Series {
    param([datetime[]]$Dates, [double[]]$Closes, [double[]]$Adv)
    $out = @()
    for ($i = 0; $i -lt $Dates.Count; $i++) {
        $o = [ordered]@{ Date = $Dates[$i]; Close = $Closes[$i] }
        if ($Adv) { $o.AdvTl = $Adv[$i] }
        $out += [pscustomobject]$o
    }
    return $out
}

$days = @(
    [datetime]'2025-01-02', [datetime]'2025-01-03', [datetime]'2025-01-06',
    [datetime]'2025-01-07', [datetime]'2025-01-08'
)

# ---------------------------------------------------------------------------
Write-Host "`nTest 1: Defter korunumu + getiri (sifir maliyet, A 100->110)" -ForegroundColor Cyan
# A duz 100, son gun 110; B sabit. Her rebalance A secilir. Tek alim, sonra fiyat artar.
$pd = @{
    'A' = New-Series -Dates $days -Closes @(100,100,100,100,110)
    'B' = New-Series -Dates $days -Closes @(50,50,50,50,50)
}
$pickA = { param($AsOf, $PriceData) @('A') }
$r1 = Invoke-EventDrivenBacktest -PriceData $pd -RebalanceDates @($days[0], $days[4]) `
        -SignalCallback $pickA -InitialCapital 100000 `
        -CommissionBps 0 -SlippageBps 0 -ImpactKBps 0 -ImpactCapBps 0
# day0: 100000/100 = 1000 adet A. day4: A=110 -> 1000*110 = 110000. dQty=0 (yeniden hedef ayni).
Assert-Near -Actual $r1.FinalValue -Expected 110000 -Tol 0.5 -Message "FinalValue 110000"
Assert-Near -Actual $r1.TotalReturnPct -Expected 10 -Tol 0.05 -Message "TotalReturn %10"
Assert-Near -Actual $r1.TotalCostsTL -Expected 0 -Tol 0.001 -Message "TotalCosts 0"

# ---------------------------------------------------------------------------
Write-Host "`nTest 2: Maliyet muhasebesi (komisyon 15+kayma 10 = 25bps, tek islem)" -ForegroundColor Cyan
# Duz fiyat. Sadece ilk rebalance'ta A secilir, sonra bos -> ek islem yok.
$pd2 = @{ 'A' = New-Series -Dates $days -Closes @(100,100,100,100,100) }
$pickOnce = { param($AsOf, $PriceData) if ($AsOf -eq $days[0]) { @('A') } else { @() } }
$r2 = Invoke-EventDrivenBacktest -PriceData $pd2 -RebalanceDates @($days[0], $days[4]) `
        -SignalCallback $pickOnce -InitialCapital 100000 `
        -CommissionBps 15 -SlippageBps 10 -ImpactKBps 0 -ImpactCapBps 0
# Alim: 1000 adet, tradeVal=100000, cost=100000*0.0025=250. cash=-250. equity=-250+1000*100=99750.
Assert-Near -Actual $r2.TotalCostsTL -Expected 250 -Tol 0.01 -Message "TotalCosts 250"
Assert-Near -Actual $r2.FinalValue -Expected 99750 -Tol 0.5 -Message "FinalValue 99750"
Assert-True -Condition ($r2.TradeCount -eq 1) -Message "TradeCount 1"

# ---------------------------------------------------------------------------
Write-Host "`nTest 3: ADV likidite siniri (MaxAdvMultiple ile pozisyon kapanir)" -ForegroundColor Cyan
# ADV=100000, MaxAdvMultiple=0.25 -> cap=25000. targetVal=100000 ama alloc=25000.
# Fiyat 100->110: tam yatirim olsa 110000; kapali ise 75000 nakit + 250*110 = 102500.
$pd3 = @{ 'A' = New-Series -Dates $days -Closes @(100,100,100,100,110) -Adv @(100000,100000,100000,100000,100000) }
$r3 = Invoke-EventDrivenBacktest -PriceData $pd3 -RebalanceDates @($days[0], $days[4]) `
        -SignalCallback $pickOnce -InitialCapital 100000 `
        -CommissionBps 0 -SlippageBps 0 -ImpactKBps 0 -ImpactCapBps 0 -MaxAdvMultiple 0.25
Assert-Near -Actual $r3.FinalValue -Expected 102500 -Tol 0.5 -Message "FinalValue 102500 (ADV kapali)"

# ---------------------------------------------------------------------------
Write-Host "`nTest 4: Alim/satim gecisi nakit korunumu (A->B, sifir maliyet)" -ForegroundColor Cyan
# day0 A al; day4'te B'ye gec. Fiyatlar: A 100 sabit, B 50->55.
$pd4 = @{
    'A' = New-Series -Dates $days -Closes @(100,100,100,100,100)
    'B' = New-Series -Dates $days -Closes @(50,50,50,50,55)
}
$switch = { param($AsOf, $PriceData) if ($AsOf -eq $days[0]) { @('A') } else { @('B') } }
$r4 = Invoke-EventDrivenBacktest -PriceData $pd4 -RebalanceDates @($days[0], $days[4]) `
        -SignalCallback $switch -InitialCapital 100000 `
        -CommissionBps 0 -SlippageBps 0 -ImpactKBps 0 -ImpactCapBps 0
# day0: A 1000 adet, cash=0. day4: equity=100000, A sat (->cash 100000), B al 100000/55=1818.18 adet.
# Ayni gun mark-to-market: cash 0 + 1818.18*55 = 100000. Fiyat artisi ayni gun rebalance'ta
# alindigi icin getiri yok -> final 100000.
Assert-Near -Actual $r4.FinalValue -Expected 100000 -Tol 1 -Message "FinalValue 100000 (gecis korunumu)"
Assert-True -Condition ($r4.TradeCount -eq 3) -Message "TradeCount 3 (A al, A sat, B al)"

# ---------------------------------------------------------------------------
Write-Host "`nTest 5: Metrik akli-basinda + benchmark alpha" -ForegroundColor Cyan
$bench = New-Series -Dates $days -Closes @(1000,1000,1000,1000,1040)  # +%4
$r5 = Invoke-EventDrivenBacktest -PriceData $pd -RebalanceDates @($days[0], $days[4]) `
        -SignalCallback $pickA -BenchmarkSeries $bench -InitialCapital 100000 `
        -CommissionBps 0 -SlippageBps 0 -ImpactKBps 0 -ImpactCapBps 0
Assert-Near -Actual $r5.BenchmarkReturnPct -Expected 4 -Tol 0.05 -Message "Benchmark %4"
Assert-Near -Actual $r5.AlphaPct -Expected 6 -Tol 0.1 -Message "Alpha %6 (10-4)"
Assert-True -Condition ($r5.MaxDrawdownPct -le 0) -Message "MaxDrawdown <= 0"
Assert-True -Condition ($r5.Days -eq 5) -Message "Days 5"
Assert-True -Condition ($r5.MonthlyReturns.Count -ge 1) -Message "MonthlyReturns dolu"
Assert-True -Condition ($r5.EquityCurve.Count -eq 5) -Message "EquityCurve 5 nokta"

# ---------------------------------------------------------------------------
Write-Host "`nTest 6: Yardimci fonksiyonlar" -ForegroundColor Cyan
$idx = Get-BtIndexOnOrBefore -Series $bench -Date ([datetime]'2025-01-07')
Assert-True -Condition ($idx -eq 3) -Message "Get-BtIndexOnOrBefore on-or-before dogru"
$sd = Get-BtStdDev -Values @(1.0, 2.0, 3.0, 4.0)
Assert-Near -Actual $sd -Expected 1.2910 -Tol 0.001 -Message "Get-BtStdDev ornek std"

# ---------------------------------------------------------------------------
Write-Host ""
if ($script:Failures -gt 0) {
    Write-Host "SONUC: $($script:Passed) gecti, $($script:Failures) basarisiz." -ForegroundColor Red
    exit 1
} else {
    Write-Host "SONUC: tum testler gecti ($($script:Passed))." -ForegroundColor Green
    exit 0
}
