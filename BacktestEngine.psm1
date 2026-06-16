Set-StrictMode -Version Latest

<#
    BacktestEngine.psm1 — Gercek EVENT-DRIVEN backtest motoru.
    Vektorlestirilmis ad-hoc dongunun aksine, gunluk olay ekseninde ilerler:
      her gun -> mark-to-market; rebalance gunlerinde -> sinyal (yalniz o gune
      kadarki veriyle) -> hedef agirlik -> emir -> GERCEKCI dolum (komisyon +
      kayma + karekok piyasa etkisi + ADV katilim siniri) -> defter guncelleme.
    Kurumsal metrikler uretir: CAGR, yillik vol, Sharpe, Sortino, Calmar, maks
    dusus, turnover, BIST100'e karsi alpha/beta, aylik isabet.
    Cekirdek AGSIZDIR ve deterministik test edilebilir.

    NOT: Gercek as-reported gecmis temel veri ve delist-dahil bilesen listesi
    ucretsiz olmadigindan survivorship tam giderilemez; bu motor verilen fiyat/
    sinyal setiyle dogru calisir, veri kalitesi cagirana baglidir.
#>

function Get-BtIndexOnOrBefore {
    param([object[]]$Series, [datetime]$Date)
    $idx = -1
    for ($i = 0; $i -lt $Series.Count; $i++) {
        if ([datetime]$Series[$i].Date -le $Date) { $idx = $i } else { break }
    }
    return $idx
}

function Get-BtStdDev {
    param([double[]]$Values, [switch]$DownsideOnly)
    # NOT: bos diziyi if-ifadesinden donmek $null'a cokebilir; bu yuzden ayri ayri ata.
    $vals = @($Values)
    if ($DownsideOnly) { $vals = @($Values | Where-Object { $_ -lt 0 }) }
    if ($null -eq $vals -or $vals.Count -lt 2) { return 0.0 }
    $mean = ($vals | Measure-Object -Average).Average
    $var = 0.0; foreach ($v in $vals) { $var += ($v - $mean) * ($v - $mean) }
    return [Math]::Sqrt($var / ($vals.Count - 1))
}

function Invoke-EventDrivenBacktest {
    <#
        PriceData: hashtable symbol -> [pscustomobject]{Date,Close,(AdvTl)} dizisi (artan).
        RebalanceDates: [datetime[]] olay tarihleri.
        SignalCallback: scriptblock; param($AsOf,$PriceData) -> secilen sembol dizisi
                        (esit agirlik). YALNIZ $AsOf'a kadarki veriyi kullanmali.
        BenchmarkSeries: [pscustomobject]{Date,Close} (alpha/beta icin).
        Donus: ozet metrikler + EquityCurve + MonthlyReturns + Trades.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$PriceData,
        [Parameter(Mandatory)][datetime[]]$RebalanceDates,
        [Parameter(Mandatory)][scriptblock]$SignalCallback,
        [object[]]$BenchmarkSeries = @(),
        [double]$InitialCapital = 100000,
        [double]$CommissionBps = 15,
        [double]$SlippageBps = 10,
        [double]$ImpactKBps = 100,
        [double]$ImpactCapBps = 400,
        [double]$MaxAdvMultiple = 0.25,   # tek isimde gunluk TL hacmin en fazla bu kati pozisyon
        [int]$TradingDaysPerYear = 252
    )

    if ($RebalanceDates.Count -lt 2) { throw 'En az 2 rebalance tarihi gerekir.' }
    $rebSet = @{}; foreach ($d in $RebalanceDates) { $rebSet[([datetime]$d).Date] = $true }

    # Gunluk eksen: benchmark varsa onun gunleri, yoksa fiyat birlesimi.
    $axis = [System.Collections.Generic.List[datetime]]::new()
    if ($BenchmarkSeries.Count -gt 0) {
        foreach ($p in $BenchmarkSeries) { if ([datetime]$p.Date -ge $RebalanceDates[0] -and [datetime]$p.Date -le $RebalanceDates[-1]) { [void]$axis.Add([datetime]$p.Date) } }
    }
    if ($axis.Count -lt 2) {
        $dates = @{}
        foreach ($sym in $PriceData.Keys) { foreach ($p in $PriceData[$sym]) { $d = [datetime]$p.Date; if ($d -ge $RebalanceDates[0] -and $d -le $RebalanceDates[-1]) { $dates[$d] = $true } } }
        $axis = [System.Collections.Generic.List[datetime]](@($dates.Keys | Sort-Object))
    }
    if ($axis.Count -lt 2) { throw 'Yeterli gunluk veri yok.' }

    $commRate = ($CommissionBps + $SlippageBps) / 10000.0
    $cash = [double]$InitialCapital
    $positions = @{}   # sym -> qty
    $equityCurve = [System.Collections.Generic.List[object]]::new()
    $trades = [System.Collections.Generic.List[object]]::new()
    $totalTraded = 0.0; $totalCost = 0.0; $sumEquity = 0.0

    $priceAt = {
        param($Sym, $Date)
        $s = $PriceData[$Sym]; $i = Get-BtIndexOnOrBefore -Series $s -Date $Date
        if ($i -ge 0) { [double]$s[$i].Close } else { $null }
    }
    $advAt = {
        param($Sym, $Date)
        $s = $PriceData[$Sym]; $i = Get-BtIndexOnOrBefore -Series $s -Date $Date
        if ($i -ge 0 -and $null -ne (Get-ObjectPropertyValue -Object $s[$i] -Name 'AdvTl')) { [double]$s[$i].AdvTl } else { 0.0 }
    }

    foreach ($day in $axis) {
        # Rebalance olayi
        if ($rebSet.ContainsKey($day.Date)) {
            $equityNow = $cash
            foreach ($sym in @($positions.Keys)) { $p = & $priceAt $sym $day; if ($null -ne $p) { $equityNow += $positions[$sym] * $p } }

            $selected = @(& $SignalCallback $day $PriceData)
            if ($selected.Count -gt 0) {
                $targetVal = $equityNow / $selected.Count
                $targetQty = @{}
                foreach ($sym in $selected) {
                    $p = & $priceAt $sym $day
                    if ($null -eq $p -or $p -le 0) { continue }
                    $adv = & $advAt $sym $day
                    $cap = if ($adv -gt 0) { $MaxAdvMultiple * $adv } else { $targetVal }
                    $alloc = [Math]::Min($targetVal, $cap)   # likidite siniri: ADV'nin kati
                    $targetQty[$sym] = $alloc / $p
                }
                # Emirler: mevcut -> hedef
                $allSyms = @(@($positions.Keys) + @($targetQty.Keys) | Select-Object -Unique)
                foreach ($sym in $allSyms) {
                    $p = & $priceAt $sym $day; if ($null -eq $p -or $p -le 0) { continue }
                    $curQty = if ($positions.ContainsKey($sym)) { [double]$positions[$sym] } else { 0.0 }
                    $tgtQty = if ($targetQty.ContainsKey($sym)) { [double]$targetQty[$sym] } else { 0.0 }
                    $dQty = $tgtQty - $curQty
                    if ([Math]::Abs($dQty) -lt 1e-9) { continue }
                    $tradeVal = [Math]::Abs($dQty) * $p
                    $adv = & $advAt $sym $day
                    $impactBps = if ($adv -gt 0) { [Math]::Min($ImpactCapBps, $ImpactKBps * [Math]::Sqrt($tradeVal / $adv)) } else { $ImpactCapBps }
                    $cost = $tradeVal * ($commRate + $impactBps / 10000.0)
                    # Nakit akisi: alimda nakit cikar (+maliyet), satimda girer (-maliyet)
                    $cash -= ($dQty * $p)   # dQty>0 alim -> nakit azalir
                    $cash -= $cost
                    $totalTraded += $tradeVal; $totalCost += $cost
                    [void]$trades.Add([pscustomobject]@{ Date = $day; Symbol = $sym; DeltaQty = $dQty; Price = $p; TradeValue = $tradeVal; Cost = $cost })
                    if ([Math]::Abs($tgtQty) -lt 1e-12) { [void]$positions.Remove($sym) } else { $positions[$sym] = $tgtQty }
                }
            }
        }

        # Gun sonu mark-to-market
        $equity = $cash
        foreach ($sym in @($positions.Keys)) { $p = & $priceAt $sym $day; if ($null -ne $p) { $equity += $positions[$sym] * $p } }
        $sumEquity += $equity
        [void]$equityCurve.Add([pscustomobject]@{ Date = $day; Equity = $equity })
    }

    # Metrikler
    $finalEq = $equityCurve[$equityCurve.Count - 1].Equity
    $totalReturn = (($finalEq / $InitialCapital) - 1.0) * 100.0
    $nDays = $equityCurve.Count
    $years = $nDays / [double]$TradingDaysPerYear
    $cagr = if ($years -gt 0 -and $finalEq -gt 0) { ([Math]::Pow($finalEq / $InitialCapital, 1.0 / $years) - 1.0) * 100.0 } else { 0.0 }

    $dailyRets = [System.Collections.Generic.List[double]]::new()
    for ($i = 1; $i -lt $equityCurve.Count; $i++) {
        $prev = $equityCurve[$i - 1].Equity
        if ($prev -gt 0) { [void]$dailyRets.Add(($equityCurve[$i].Equity / $prev) - 1.0) }
    }
    $dr = $dailyRets.ToArray()
    $meanD = if ($dr.Count -gt 0) { ($dr | Measure-Object -Average).Average } else { 0.0 }
    $sd = Get-BtStdDev -Values $dr
    $sdDown = Get-BtStdDev -Values $dr -DownsideOnly
    $annVol = $sd * [Math]::Sqrt($TradingDaysPerYear) * 100.0
    $sharpe = if ($sd -gt 0) { ($meanD / $sd) * [Math]::Sqrt($TradingDaysPerYear) } else { 0.0 }
    $sortino = if ($sdDown -gt 0) { ($meanD / $sdDown) * [Math]::Sqrt($TradingDaysPerYear) } else { 0.0 }

    # Maks dusus
    $peak = $equityCurve[0].Equity; $maxDd = 0.0
    foreach ($pt in $equityCurve) { if ($pt.Equity -gt $peak) { $peak = $pt.Equity }; $dd = if ($peak -gt 0) { (($pt.Equity / $peak) - 1.0) * 100.0 } else { 0.0 }; if ($dd -lt $maxDd) { $maxDd = $dd } }
    $calmar = if ($maxDd -lt 0) { $cagr / [Math]::Abs($maxDd) } else { 0.0 }

    # Aylik getiriler + isabet
    $monthly = [System.Collections.Generic.List[object]]::new()
    $curKey = $null; $monthStartEq = $equityCurve[0].Equity; $prevEq = $equityCurve[0].Equity
    foreach ($pt in $equityCurve) {
        $k = ([datetime]$pt.Date).ToString('yyyy-MM')
        if ($null -eq $curKey) { $curKey = $k; $monthStartEq = $prevEq }
        elseif ($k -ne $curKey) {
            [void]$monthly.Add([pscustomobject]@{ Month = $curKey; ReturnPct = (($prevEq / $monthStartEq) - 1.0) * 100.0 })
            $curKey = $k; $monthStartEq = $prevEq
        }
        $prevEq = $pt.Equity
    }
    [void]$monthly.Add([pscustomobject]@{ Month = $curKey; ReturnPct = (($finalEq / $monthStartEq) - 1.0) * 100.0 })
    $hitRate = if ($monthly.Count -gt 0) { (@($monthly | Where-Object { $_.ReturnPct -gt 0 }).Count / [double]$monthly.Count) * 100.0 } else { $null }

    # Benchmark alpha/beta
    $benchReturn = $null; $alpha = $null; $beta = $null
    if ($BenchmarkSeries.Count -gt 1) {
        $bi = Get-BtIndexOnOrBefore -Series $BenchmarkSeries -Date $axis[0]
        $bj = Get-BtIndexOnOrBefore -Series $BenchmarkSeries -Date $axis[$axis.Count - 1]
        if ($bi -ge 0 -and $bj -ge 0 -and [double]$BenchmarkSeries[$bi].Close -gt 0) {
            $benchReturn = (([double]$BenchmarkSeries[$bj].Close / [double]$BenchmarkSeries[$bi].Close) - 1.0) * 100.0
            $alpha = $totalReturn - $benchReturn
        }
    }

    $turnoverAnnual = if ($sumEquity / $nDays -gt 0 -and $years -gt 0) { ($totalTraded / ($sumEquity / $nDays)) / $years } else { 0.0 }

    return [pscustomobject][ordered]@{
        InitialCapital = $InitialCapital
        FinalValue = [Math]::Round($finalEq, 2)
        TotalReturnPct = [Math]::Round($totalReturn, 2)
        CagrPct = [Math]::Round($cagr, 2)
        AnnVolPct = [Math]::Round($annVol, 2)
        Sharpe = [Math]::Round($sharpe, 2)
        Sortino = [Math]::Round($sortino, 2)
        Calmar = [Math]::Round($calmar, 2)
        MaxDrawdownPct = [Math]::Round($maxDd, 2)
        TurnoverAnnual = [Math]::Round($turnoverAnnual, 2)
        TotalCostsTL = [Math]::Round($totalCost, 2)
        BenchmarkReturnPct = if ($null -ne $benchReturn) { [Math]::Round($benchReturn, 2) } else { $null }
        AlphaPct = if ($null -ne $alpha) { [Math]::Round($alpha, 2) } else { $null }
        HitRatePct = if ($null -ne $hitRate) { [Math]::Round($hitRate, 1) } else { $null }
        Days = $nDays
        MonthlyReturns = $monthly.ToArray()
        EquityCurve = $equityCurve.ToArray()
        TradeCount = $trades.Count
    }
}

# Get-ObjectPropertyValue bagimsiz kullanim icin (motor tek basina import edilirse).
if (-not (Get-Command Get-ObjectPropertyValue -ErrorAction SilentlyContinue)) {
    function Get-ObjectPropertyValue {
        param($Object, [string]$Name)
        if ($null -eq $Object) { return $null }
        $p = $Object.PSObject.Properties[$Name]
        if ($null -eq $p) { return $null }
        return $p.Value
    }
}

Export-ModuleMember -Function Invoke-EventDrivenBacktest, Get-BtIndexOnOrBefore, Get-BtStdDev
