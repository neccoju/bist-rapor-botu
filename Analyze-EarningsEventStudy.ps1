#requires -Version 5.1
<#
    Bilanço açıklama tarihi olay çalışması (event study).
    Sorular:
      1) Açıklama ÖNCESİ fiyat hareketi (run-up) gelecek bilançoyu önceden
         haber veriyor mu? (korelasyon: ön run-up vs bilanço sürprizi)
      2) Açıklama GÜNÜ piyasa sürpriz yönünde mi tepki veriyor? (tepki)
      3) Açıklama SONRASI sürüklenme var mı? (PEAD: sürpriz vs sonraki drift)
    Veri: TradingView (son bilanço tarihi + sürpriz proxy) + Yahoo günlük kapanış.
    Not: Tek kesit = her hissenin EN SON bilanço açıklaması. Ücretsiz/gecikmeli
    veriyle yaklaşık bir analizdir; yatırım tavsiyesi değildir.
#>
param(
    [int]$MaxStocks = 500,
    [int]$WindowDays = 20,          # islem gunu penceresi (~1 ay)
    [double]$WinsorPct = 60.0,      # uc degerleri sinirlama
    [double]$MinAvgVol = 75000,     # likidite tabani (dusurmek ornegi buyutur)
    [int]$MaxElapsedSec = 720
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BistScanner.Core.psm1') -Force

function Get-Pearson {
    param([double[]]$X, [double[]]$Y)
    $n = [Math]::Min($X.Count, $Y.Count)
    if ($n -lt 5) { return $null }
    $mx = ($X | Measure-Object -Average).Average
    $my = ($Y | Measure-Object -Average).Average
    $sxy = 0.0; $sxx = 0.0; $syy = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $dx = $X[$i] - $mx; $dy = $Y[$i] - $my
        $sxy += $dx * $dy; $sxx += $dx * $dx; $syy += $dy * $dy
    }
    if ($sxx -le 0 -or $syy -le 0) { return $null }
    return [Math]::Round($sxy / [Math]::Sqrt($sxx * $syy), 3)
}

function Limit-Pct { param([double]$V, [double]$Cap) if ($V -gt $Cap) { $Cap } elseif ($V -lt - $Cap) { - $Cap } else { $V } }
function D { param($V) $n = $V -as [double]; if ($null -ne $n) { [double]$n } else { $null } }

# Ceyrek-bazli surpriz proxy'si (cok-ceyrekli mod icin): ceyrek i'yi onceki
# ceyrege (i+1) gore net kar QoQ + pozitiflik + FAVOK QoQ ile 0-100 (50 notr).
function Get-QuarterSurprise {
    param([object[]]$NiHist, [object[]]$EbHist, [int]$Index)
    if ($null -eq $NiHist -or ($Index + 1) -ge $NiHist.Count) { return $null }
    $ni = D $NiHist[$Index]; $niPrev = D $NiHist[$Index + 1]
    if ($null -eq $ni -or $null -eq $niPrev) { return $null }
    $score = 50.0
    if ($niPrev -ne 0) {
        $qoq = (($ni - $niPrev) / [Math]::Abs($niPrev)) * 100.0
        $score += [Math]::Max(-35, [Math]::Min(35, $qoq * 0.3))
    }
    if ($ni -gt 0) { $score += 8 } else { $score -= 10 }
    if ($null -ne $EbHist -and ($Index + 1) -lt $EbHist.Count) {
        $eb = D $EbHist[$Index]; $ebPrev = D $EbHist[$Index + 1]
        if ($null -ne $eb -and $null -ne $ebPrev -and $ebPrev -ne 0) {
            $eq = (($eb - $ebPrev) / [Math]::Abs($ebPrev)) * 100.0
            $score += [Math]::Max(-15, [Math]::Min(15, $eq * 0.2))
        }
    }
    return [Math]::Round([Math]::Max(0, [Math]::Min(100, $score)), 1)
}

Write-Host "=== Bilanço Olay Çalışması başlıyor (çok-çeyrekli) ==="
$startedAt = Get-Date
$stocks = @(Invoke-BistStockScan)
Write-Host "Taranan hisse: $($stocks.Count)"

$today = (Get-Date).Date
$minAgo = $WindowDays + 8
# Likit + gecerli, ceyreklik gecmisi ve donem sonu olan hisseler.
$candidates = @($stocks | Where-Object {
        $avgVol = $_.AverageVolume10D
        $_.FiscalPeriodEnd -is [datetime] -and
        $null -ne $_.NetIncomeHistory -and @($_.NetIncomeHistory).Count -ge 2 -and
        $null -ne $avgVol -and $avgVol -ge $MinAvgVol
    } | Sort-Object @{ Expression = { [double]$_.MarketCap }; Descending = $true } | Select-Object -First $MaxStocks)

Write-Host "Uygun hisse: $($candidates.Count) (en fazla $MaxStocks). Her hissenin son ~4 çeyreği yaklaşık açıklama tarihiyle (dönem sonu + 50 gün) incelenir."

$rows = [System.Collections.Generic.List[object]]::new()
$fetched = 0
$eventTried = 0
foreach ($s in $candidates) {
    if (((Get-Date) - $startedAt).TotalSeconds -gt $MaxElapsedSec) {
        Write-Host "Zaman sınırı; $fetched hisse işlendikten sonra durduruldu."
        break
    }
    $sym = [string]$s.Symbol
    $niHist = @($s.NetIncomeHistory)
    $ebHist = @(if ($null -ne $s.EbitdaHistory) { $s.EbitdaHistory } else { @() })
    $periodEnd0 = ([datetime]$s.FiscalPeriodEnd).Date
    $series = @(Get-YahooDailyCloseSeries -Symbol $sym -Range '2y' -TimeoutSec 8)
    $fetched++
    if ($series.Count -lt ($WindowDays * 2 + 5)) { continue }

    $maxQuarter = [Math]::Min(4, $niHist.Count - 2)   # i+1 gerektigi icin -2
    for ($q = 0; $q -le $maxQuarter; $q++) {
        $surprise = Get-QuarterSurprise -NiHist $niHist -EbHist $ebHist -Index $q
        if ($null -eq $surprise) { continue }
        $announce = $periodEnd0.AddMonths(-3 * $q).AddDays(50)
        $daysAgo = ($today - $announce.Date).TotalDays
        if ($daysAgo -lt $minAgo -or $daysAgo -gt 600) { continue }
        $eventTried++

        $idx0 = -1
        for ($i = 0; $i -lt $series.Count; $i++) {
            if ($series[$i].Date.Date -ge $announce.Date) { $idx0 = $i; break }
        }
        if ($idx0 -lt ($WindowDays + 2) -or $idx0 -gt ($series.Count - ($WindowDays + 2))) { continue }

        $preBase = [double]$series[$idx0 - ($WindowDays + 1)].Close
        $dayBefore = [double]$series[$idx0 - 1].Close
        $dayAfter = [double]$series[$idx0 + 1].Close
        $post = [double]$series[$idx0 + $WindowDays].Close
        if ($preBase -le 0 -or $dayBefore -le 0 -or $dayAfter -le 0 -or $post -le 0) { continue }

        $preRunup = Limit-Pct ((($dayBefore / $preBase) - 1.0) * 100.0) $WinsorPct
        $reaction = Limit-Pct ((($dayAfter / $dayBefore) - 1.0) * 100.0) $WinsorPct
        $drift = Limit-Pct ((($post / $dayAfter) - 1.0) * 100.0) $WinsorPct

        [void]$rows.Add([pscustomobject]@{ Symbol = $sym; Quarter = $q; Surprise = $surprise; PreRunup = $preRunup; Reaction = $reaction; Drift = $drift })
    }
}

Write-Host "İşlenen hisse: $fetched, denenen çeyrek-olayı: $eventTried"

Write-Host "Geçerli olay örneği: $($rows.Count)"
if ($rows.Count -lt 10) {
    Write-Host "Yetersiz örnek; analiz güvenilir değil."
    return
}

$surpriseArr = @($rows | ForEach-Object { [double]$_.Surprise })
$preArr = @($rows | ForEach-Object { [double]$_.PreRunup })
$reactArr = @($rows | ForEach-Object { [double]$_.Reaction })
$driftArr = @($rows | ForEach-Object { [double]$_.Drift })

Write-Host ""
Write-Host "=== KORELASYONLAR (Pearson r, n=$($rows.Count)) ==="
Write-Host ("1) Sürpriz  vs  açıklama ÖNCESİ run-up : r = {0}  (pozitifse: iyi bilanço önceden fiyata sızıyor)" -f (Get-Pearson -X $surpriseArr -Y $preArr))
Write-Host ("2) Sürpriz  vs  açıklama GÜNÜ tepki     : r = {0}  (pozitifse: piyasa sürpriz yönünde tepki veriyor)" -f (Get-Pearson -X $surpriseArr -Y $reactArr))
Write-Host ("3) Sürpriz  vs  açıklama SONRASI drift  : r = {0}  (pozitifse: PEAD - sürüklenme sürüyor)" -f (Get-Pearson -X $surpriseArr -Y $driftArr))
Write-Host ("4) Ön run-up vs sonraki drift           : r = {0}  (pozitifse: önceki momentum sonrasını da sürüklüyor)" -f (Get-Pearson -X $preArr -Y $driftArr))
Write-Host ("5) Açıklama günü tepki vs sonraki drift : r = {0}  (pozitifse: ilk tepki yönü devam ediyor)" -f (Get-Pearson -X $reactArr -Y $driftArr))

$pos = @($rows | Where-Object { $_.Surprise -ge 60 })
$neg = @($rows | Where-Object { $_.Surprise -le 40 })
function MeanOf { param($items, $field) if ($items.Count -eq 0) { return $null } [Math]::Round((($items | ForEach-Object { [double]$_.$field }) | Measure-Object -Average).Average, 2) }

Write-Host ""
Write-Host "=== GRUP ORTALAMALARI (%) ==="
Write-Host ("Pozitif sürpriz (>=60), n=$($pos.Count): ön run-up {0}, gün tepki {1}, sonraki drift {2}" -f (MeanOf $pos 'PreRunup'), (MeanOf $pos 'Reaction'), (MeanOf $pos 'Drift'))
Write-Host ("Negatif sürpriz (<=40), n=$($neg.Count): ön run-up {0}, gün tepki {1}, sonraki drift {2}" -f (MeanOf $neg 'PreRunup'), (MeanOf $neg 'Reaction'), (MeanOf $neg 'Drift'))

if ($pos.Count -ge 5 -and $neg.Count -ge 5) {
    $posDriftHit = [Math]::Round((@($pos | Where-Object { $_.Drift -gt 0 }).Count / [double]$pos.Count) * 100, 1)
    $negDriftHit = [Math]::Round((@($neg | Where-Object { $_.Drift -lt 0 }).Count / [double]$neg.Count) * 100, 1)
    Write-Host ""
    Write-Host "=== PEAD İSABET ORANLARI ==="
    Write-Host ("Pozitif sürpriz -> sonraki dönem pozitif drift: %$posDriftHit")
    Write-Host ("Negatif sürpriz -> sonraki dönem negatif drift: %$negDriftHit")
    $spread = (MeanOf $pos 'Drift')
    $negSpread = (MeanOf $neg 'Drift')
    if ($null -ne $spread -and $null -ne $negSpread) {
        Write-Host ("Pozitif-negatif drift farkı (long-short PEAD getirisi yaklaşığı): %{0}" -f [Math]::Round($spread - $negSpread, 2))
    }
}

Write-Host ""
Write-Host "=== EN GÜÇLÜ POZİTİF SÜRPRİZLER (örnek) ==="
$rows | Sort-Object Surprise -Descending | Select-Object -First 12 |
    Format-Table Symbol, @{N='Sürpriz';E={$_.Surprise}}, @{N='ÖnRunup%';E={[Math]::Round($_.PreRunup,1)}}, @{N='Tepki%';E={[Math]::Round($_.Reaction,1)}}, @{N='Drift%';E={[Math]::Round($_.Drift,1)}} -AutoSize | Out-String | Write-Host

Write-Host "=== Analiz tamam ($([int]((Get-Date)-$startedAt).TotalSeconds) sn) ==="
