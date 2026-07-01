#requires -Version 5.1
<#
    Export-Dashboard.ps1 — ADDITIVE köprü (mevcut bot mantığına dokunmaz).

    GunlukRapor.ps1'in bellekteki çıktı nesnelerini (skorlanmış evren, model
    portföy seti, anlık fırsat portföyü, performans serileri, piyasa genişliği)
    web panelinin (docs/) okuduğu JSON şemasına çevirir ve
    docs/data/latest_report.json olarak yazar.

    TASARIM:
    - Tamamen BEST-EFFORT ve null-güvenli: her alan ayrı ayrı korunur; bir alan
      üretilemezse null kalır (panel "henüz üretilmedi" fallback'i gösterir).
    - Mevcut hesaplama/strateji/sinyal/mail/LLM koduna DOKUNMAZ; yalnız OKUR ve
      yeni bir dosya YAZAR.
    - ConvertTo-DashboardReport saf fonksiyondur (test edilebilir); Export-DashboardReport
      onu çağırıp diske yazar.
#>

# Yardımcılar bu dosyaya özgüdür (modüle bağımlılığı en aza indirir).
function Get-DashProp {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [hashtable]) { if ($Object.ContainsKey($Name)) { return $Object[$Name] } else { return $null } }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -ne $p) { return $p.Value }
    return $null
}
function Get-DashNum {
    param($Object, [string]$Name)
    $v = Get-DashProp -Object $Object -Name $Name
    if ($null -eq $v -or $v -eq '') { return $null }
    $d = $v -as [double]
    if ($null -eq $d) { return $null }
    if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { return $null }
    return [Math]::Round($d, 4)
}
function Get-DashStr {
    param($Object, [string]$Name)
    $v = Get-DashProp -Object $Object -Name $Name
    if ($null -eq $v) { return $null }
    $s = [string]$v
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    return $s.Trim()
}
function Get-DashSeriesKey {
    param([string]$Name)
    $n = ([string]$Name).ToLowerInvariant()
    if ($n -match 'bist|xu100') { return 'bist100' }
    if ($n -match 'nasdaq|ixic') { return 'nasdaq' }
    if ($n -match 's&p|sp500|gspc') { return 'sp500' }
    if ($n -match 'altın|altin|gold') { return 'gold' }
    if ($n -match 'usd') { return 'usdtry' }
    if ($n -match 'mevduat|deposit') { return 'deposit' }
    return 'series'
}

function ConvertTo-DashboardReport {
    [CmdletBinding()]
    param(
        [object[]]$Stocks = @(),
        $PortfolioSet = $null,
        $InstantEntryPortfolio = $null,
        [object[]]$StrategySeries = @(),
        [object[]]$BenchmarkSeries = @(),
        $MarketBreadth = $null,
        $PortfolioCommentary = $null,
        [datetime]$AsOf = (Get-Date),
        [string]$Strategy = 'Dengeli',
        [string]$PrimaryPortfolioId = 'Dengeli',
        [int]$TopStocks = 30,
        [string]$PagesUrl = $null
    )

    # ---- meta ----
    $hour = $AsOf.Hour
    $isWeekday = @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday) -notcontains $AsOf.DayOfWeek
    $marketOpen = $isWeekday -and $hour -ge 10 -and ($hour -lt 18 -or ($hour -eq 18 -and $AsOf.Minute -lt 10))
    $meta = [ordered]@{
        schemaVersion  = 1
        reportDate     = $AsOf.ToString('yyyy-MM-dd')
        generatedAt    = $AsOf.ToString('o')
        lastUpdatedText = $AsOf.ToString('dd.MM.yyyy HH:mm')
        marketStatus   = if ($marketOpen) { 'Açık' } else { 'Kapalı' }
        strategy       = $Strategy
        scannedCount   = @($Stocks).Count
        source         = 'Mail raporundan üretildi'
        isSample       = $false
        pagesUrl       = $PagesUrl
        disclaimer     = 'Bu panel karar destek amaçlıdır, yatırım tavsiyesi değildir.'
    }

    # ---- birincil portföy (özet + dağılım) ----
    $portfolios = @(Get-DashProp -Object $PortfolioSet -Name 'Portfolios')
    $primary = $null
    foreach ($p in $portfolios) { if ((Get-DashStr -Object $p -Name 'Id') -eq $PrimaryPortfolioId) { $primary = $p; break } }
    if ($null -eq $primary -and $portfolios.Count -gt 0) { $primary = $portfolios[0] }

    # ---- summary ----
    $stockByDaily = @($Stocks | Where-Object { $null -ne (Get-DashNum -Object $_ -Name 'ChangePct') })
    $best = $null; $worst = $null
    if ($stockByDaily.Count -gt 0) {
        $sorted = @($stockByDaily | Sort-Object @{ Expression = { Get-DashNum -Object $_ -Name 'ChangePct' } })
        $worst = $sorted[0]; $best = $sorted[$sorted.Count - 1]
    }
    $breadthAbove = Get-DashNum -Object $MarketBreadth -Name 'AboveSMA200Pct'
    $riskScore = if ($null -ne $breadthAbove) { [pscustomobject]@{ value = [Math]::Round(100 - [double]$breadthAbove, 0); label = (Get-DashStr -Object $MarketBreadth -Name 'Label') } } else { $null }
    $summary = [ordered]@{
        portfolioValueTL = Get-DashNum -Object $primary -Name 'CurrentValueTL'
        initialCapitalTL = Get-DashNum -Object $primary -Name 'InitialCapitalTL'
        dailyChangePct   = $null   # portföy günlük değişim bot tarafından izlenmiyor
        weeklyChangePct  = $null   # portföy haftalık değişim bot tarafından izlenmiyor
        monthlyChangePct = Get-DashNum -Object $primary -Name 'TotalReturnPct'
        bestStock  = if ($best)  { [pscustomobject]@{ ticker = (Get-DashStr -Object $best -Name 'Symbol');  changePct = (Get-DashNum -Object $best -Name 'ChangePct') } } else { $null }
        worstStock = if ($worst) { [pscustomobject]@{ ticker = (Get-DashStr -Object $worst -Name 'Symbol'); changePct = (Get-DashNum -Object $worst -Name 'ChangePct') } } else { $null }
        riskScore  = $riskScore
        llmStance  = $null
    }

    # ---- performance (birincil portföy "Portföy" + benchmark serileri) ----
    $series = [System.Collections.Generic.List[object]]::new()
    $primaryName = Get-DashStr -Object $primary -Name 'Name'
    foreach ($s in @($StrategySeries)) {
        if ($primaryName -and (Get-DashStr -Object $s -Name 'Name') -eq $primaryName) {
            [void]$series.Add((ConvertTo-DashSeries -Series $s -Key 'portfolio' -Name 'Portföy')); break
        }
    }
    foreach ($b in @($BenchmarkSeries)) {
        $nm = Get-DashStr -Object $b -Name 'Name'
        [void]$series.Add((ConvertTo-DashSeries -Series $b -Key (Get-DashSeriesKey -Name $nm) -Name $nm))
    }
    $series = @($series | Where-Object { $_ -and @($_.points).Count -gt 0 })
    $performance = [ordered]@{ note = if ($series.Count -eq 0) { 'Performans serisi henüz üretilmedi.' } else { $null }; series = $series }

    # ---- allocation (birincil portföy holding'leri) ----
    $holds = @(Get-DashProp -Object $primary -Name 'Holdings')
    $target = if ($holds.Count -gt 0) { [Math]::Round(100.0 / $holds.Count, 1) } else { $null }
    $allocHoldings = @($holds | ForEach-Object {
        [pscustomobject]@{ ticker = (Get-DashStr -Object $_ -Name 'Symbol'); company = (Get-DashStr -Object $_ -Name 'Company'); weightPct = (Get-DashNum -Object $_ -Name 'WeightPct'); targetPct = $target }
    })
    $needsReb = $false
    foreach ($h in $allocHoldings) { if ($null -ne $h.weightPct -and $null -ne $target -and [Math]::Abs([double]$h.weightPct - [double]$target) -gt 3.0) { $needsReb = $true } }
    $allocation = [ordered]@{ rebalanceNeeded = $needsReb; rebalanceNote = if ($needsReb) { 'Bazı ağırlıklar hedeften >3 puan sapmış.' } else { $null }; holdings = $allocHoldings }

    # ---- stocks (en yüksek skorlu TopStocks) ----
    $topRows = @($Stocks |
        Sort-Object @{ Expression = { $v = Get-DashNum -Object $_ -Name 'Score'; if ($null -ne $v) { $v } else { -1 } }; Descending = $true } |
        Select-Object -First $TopStocks |
        ForEach-Object {
            $rv = Get-DashNum -Object $_ -Name 'RelativeVolume'
            [pscustomobject]@{
                ticker    = (Get-DashStr -Object $_ -Name 'Symbol')
                company   = (Get-DashStr -Object $_ -Name 'Company')
                price     = (Get-DashNum -Object $_ -Name 'Price')
                dailyPct  = (Get-DashNum -Object $_ -Name 'ChangePct')
                weeklyPct = (Get-DashNum -Object $_ -Name 'PerfWeek')
                rsi       = (Get-DashNum -Object $_ -Name 'RSI')
                macd      = (Get-DashNum -Object $_ -Name 'MacdHistogram')
                volume    = if ($null -ne $rv) { ([string]([Math]::Round($rv, 2)) + 'x') } else { $null }
                signal    = (Get-DashStr -Object $_ -Name 'Signal')
                llmNote   = $null    # bot per-stock LLM yorumu üretmiyor (ileride eklenebilir)
                action    = (Get-DashStockAction -Stock $_)
            }
        })

    # ---- sectorRotation (evrenden türetilmiş: sektör ortalaması) ----
    $sectorRotation = @()
    try {
        $groups = @($Stocks | Where-Object { Get-DashStr -Object $_ -Name 'SectorTR' } | Group-Object { Get-DashStr -Object $_ -Name 'SectorTR' })
        $sectorRotation = @($groups | ForEach-Object {
            $d = @($_.Group | ForEach-Object { Get-DashNum -Object $_ -Name 'ChangePct' } | Where-Object { $null -ne $_ })
            $w = @($_.Group | ForEach-Object { Get-DashNum -Object $_ -Name 'PerfWeek' } | Where-Object { $null -ne $_ })
            $da = if ($d.Count) { [Math]::Round((($d | Measure-Object -Average).Average), 2) } else { $null }
            $wa = if ($w.Count) { [Math]::Round((($w | Measure-Object -Average).Average), 2) } else { $null }
            [pscustomobject]@{ sector = $_.Name; dailyPct = $da; weeklyPct = $wa
                flow = if ($null -ne $wa) { if ($wa -gt 0.3) { 'giriş' } elseif ($wa -lt -0.3) { 'çıkış' } else { 'nötr' } } else { 'nötr' } }
        } | Where-Object { $null -ne $_.weeklyPct } | Sort-Object weeklyPct -Descending | Select-Object -First 12)
    } catch { $sectorRotation = @() }

    # ---- smartMoney (yüksek göreli hacim + yön) ----
    $strengthening = @($Stocks | Where-Object {
        $rv = Get-DashNum -Object $_ -Name 'RelativeVolume'; $ch = Get-DashNum -Object $_ -Name 'ChangePct'
        $null -ne $rv -and $rv -ge 1.5 -and $null -ne $ch -and $ch -gt 0
    } | Sort-Object @{ Expression = { Get-DashNum -Object $_ -Name 'RelativeVolume' }; Descending = $true } | Select-Object -First 6 | ForEach-Object { Get-DashStr -Object $_ -Name 'Symbol' })
    $weakening = @($Stocks | Where-Object {
        $rv = Get-DashNum -Object $_ -Name 'RelativeVolume'; $ch = Get-DashNum -Object $_ -Name 'ChangePct'
        $null -ne $rv -and $rv -ge 1.5 -and $null -ne $ch -and $ch -lt 0
    } | Sort-Object @{ Expression = { Get-DashNum -Object $_ -Name 'RelativeVolume' }; Descending = $true } | Select-Object -First 6 | ForEach-Object { Get-DashStr -Object $_ -Name 'Symbol' })
    $smartMoney = [ordered]@{
        commentary = if ($strengthening.Count -or $weakening.Count) { 'Göreli hacmi 1,5x ve üzeri olan hisselerde yön ayrışması (otomatik türetildi).' } else { $null }
        items = @()
        strengthening = @($strengthening | Where-Object { $_ })
        weakening = @($weakening | Where-Object { $_ })
    }

    # ---- technicalSignals (RSI/trend türevleri) ----
    $ob = @($Stocks | Where-Object { $r = Get-DashNum -Object $_ -Name 'RSI'; $null -ne $r -and $r -ge 70 } | Sort-Object @{ Expression = { Get-DashNum -Object $_ -Name 'RSI' }; Descending = $true } | Select-Object -First 8 | ForEach-Object { [pscustomobject]@{ ticker = (Get-DashStr -Object $_ -Name 'Symbol'); rsi = (Get-DashNum -Object $_ -Name 'RSI') } })
    $os = @($Stocks | Where-Object { $r = Get-DashNum -Object $_ -Name 'RSI'; $null -ne $r -and $r -le 30 } | Sort-Object @{ Expression = { Get-DashNum -Object $_ -Name 'RSI' } } | Select-Object -First 8 | ForEach-Object { [pscustomobject]@{ ticker = (Get-DashStr -Object $_ -Name 'Symbol'); rsi = (Get-DashNum -Object $_ -Name 'RSI') } })
    $technicalSignals = [ordered]@{
        overbought = $ob; oversold = $os
        macdCross = @(); trendStrengthening = @(); momentumLosing = @(); breakout = @()
    }

    # ---- llmCommentary (ay sonu portföy yorumu varsa) ----
    $commentText = Get-DashStr -Object $PortfolioCommentary -Name 'Text'
    if (-not $commentText) { $commentText = if ($PortfolioCommentary -is [string]) { [string]$PortfolioCommentary } else { $null } }
    $llmCommentary = [ordered]@{
        stance = $null
        marketSummary = $null
        portfolioComment = $commentText
        risks = @(); opportunities = @(); levels = @()
        watchNext = $null
    }

    # ---- actionItems (hafif türev) ----
    $watch = @($topRows | Where-Object { $_.signal -and ($_.signal -match 'İZLE|IZLE|AL') } | Select-Object -First 5 | ForEach-Object { $_.ticker })
    $riskReduction = @($topRows | Where-Object { $_.action -eq 'riskli' } | Select-Object -First 5 | ForEach-Object { $_.ticker })
    $actionItems = [ordered]@{
        watch = @($watch | Where-Object { $_ })
        rebalance = if ($needsReb) { @('Birincil portföyde ağırlık sapması var; ay sonu rebalance kontrol et.') } else { @() }
        riskReduction = @($riskReduction | Where-Object { $_ })
        buyWatchlist = @($topRows | Where-Object { $_.action -eq 'alım bölgesi' } | Select-Object -First 6 | ForEach-Object { $_.ticker })
        note = 'Karar destek amaçlıdır, yatırım tavsiyesi değildir.'
    }

    return [pscustomobject][ordered]@{
        meta = [pscustomobject]$meta
        history = @([pscustomobject]@{ date = $meta.reportDate; label = 'Son rapor' })
        summary = [pscustomobject]$summary
        performance = [pscustomobject]$performance
        allocation = [pscustomobject]$allocation
        stocks = $topRows
        sectorRotation = $sectorRotation
        smartMoney = [pscustomobject]$smartMoney
        technicalSignals = [pscustomobject]$technicalSignals
        llmCommentary = [pscustomobject]$llmCommentary
        actionItems = [pscustomobject]$actionItems
    }
}

function ConvertTo-DashSeries {
    param($Series, [string]$Key, [string]$Name)
    $pts = @(Get-DashProp -Object $Series -Name 'Points' | ForEach-Object {
        $t = Get-DashProp -Object $_ -Name 'Date'
        $v = Get-DashNum -Object $_ -Name 'ReturnPct'
        $ts = if ($t -is [datetime]) { $t.ToString('yyyy-MM-dd') } else { [string]$t }
        if ($ts -and $null -ne $v) { [pscustomobject]@{ t = $ts; v = $v } }
    } | Where-Object { $_ })
    [pscustomobject]@{ name = $Name; key = $Key; points = $pts }
}

function Get-DashStockAction {
    param($Stock)
    $risk = ([string](Get-DashStr -Object $Stock -Name 'RiskLevel')).ToLowerInvariant()
    $rsi = Get-DashNum -Object $Stock -Name 'RSI'
    $sig = ([string](Get-DashStr -Object $Stock -Name 'Signal')).ToUpperInvariant()
    if ($risk -match 'yüksek|yuksek|high') { return 'riskli' }
    if ($null -ne $rsi -and $rsi -ge 72) { return 'riskli' }
    if ($sig -match 'AL' -and $sig -notmatch 'ALMA') { return 'alım bölgesi' }
    if ($sig -match 'İZLE|IZLE|BEKLE') { return 'izle' }
    return 'bekle'
}

function Export-DashboardReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OutPath,
        [object[]]$Stocks = @(),
        $PortfolioSet = $null,
        $InstantEntryPortfolio = $null,
        [object[]]$StrategySeries = @(),
        [object[]]$BenchmarkSeries = @(),
        $MarketBreadth = $null,
        $PortfolioCommentary = $null,
        [datetime]$AsOf = (Get-Date),
        [string]$Strategy = 'Dengeli',
        [string]$PrimaryPortfolioId = 'Dengeli',
        [int]$TopStocks = 30,
        [string]$PagesUrl = $null
    )
    $report = ConvertTo-DashboardReport -Stocks $Stocks -PortfolioSet $PortfolioSet -InstantEntryPortfolio $InstantEntryPortfolio `
        -StrategySeries $StrategySeries -BenchmarkSeries $BenchmarkSeries -MarketBreadth $MarketBreadth `
        -PortfolioCommentary $PortfolioCommentary -AsOf $AsOf -Strategy $Strategy -PrimaryPortfolioId $PrimaryPortfolioId `
        -TopStocks $TopStocks -PagesUrl $PagesUrl
    $dir = Split-Path -Parent $OutPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutPath -Encoding UTF8
    return $OutPath
}
