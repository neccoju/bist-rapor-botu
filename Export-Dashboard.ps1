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

    # ---- performance (TUM model portfoyler + benchmark serileri) ----
    # Her portfoyun kendi Id'siyle anahtarlanir (pf_<Id>) ki panel her birini ayri
    # renk/isimle cizebilsin — yalniz birincil (Dengeli) degil, hepsi karsilastirilsin.
    $series = [System.Collections.Generic.List[object]]::new()
    $portfolioNameToId = @{}
    foreach ($p in $portfolios) {
        $nm = Get-DashStr -Object $p -Name 'Name'; $portfolioId = Get-DashStr -Object $p -Name 'Id'
        if ($nm -and $portfolioId) { $portfolioNameToId[$nm] = $portfolioId }
    }
    foreach ($s in @($StrategySeries)) {
        $nm = Get-DashStr -Object $s -Name 'Name'
        if ($nm -and $portfolioNameToId.ContainsKey($nm)) {
            [void]$series.Add((ConvertTo-DashSeries -Series $s -Key ('pf_' + $portfolioNameToId[$nm]) -Name $nm))
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

    # ---- sectorRotation (evrenden türetilmiş: sektör ortalaması — günlük/haftalık/aylık) ----
    $sectorRotation = @()
    try {
        $groups = @($Stocks | Where-Object { Get-DashStr -Object $_ -Name 'SectorTR' } | Group-Object { Get-DashStr -Object $_ -Name 'SectorTR' })
        $sectorRotation = @($groups | ForEach-Object {
            $d = @($_.Group | ForEach-Object { Get-DashNum -Object $_ -Name 'ChangePct' } | Where-Object { $null -ne $_ })
            $w = @($_.Group | ForEach-Object { Get-DashNum -Object $_ -Name 'PerfWeek' } | Where-Object { $null -ne $_ })
            $m = @($_.Group | ForEach-Object { Get-DashNum -Object $_ -Name 'PerfMonth' } | Where-Object { $null -ne $_ })
            $da = if ($d.Count) { [Math]::Round((($d | Measure-Object -Average).Average), 2) } else { $null }
            $wa = if ($w.Count) { [Math]::Round((($w | Measure-Object -Average).Average), 2) } else { $null }
            $ma = if ($m.Count) { [Math]::Round((($m | Measure-Object -Average).Average), 2) } else { $null }
            [pscustomobject]@{ sector = $_.Name; dailyPct = $da; weeklyPct = $wa; monthlyPct = $ma
                flow = if ($null -ne $wa) { if ($wa -gt 0.3) { 'giriş' } elseif ($wa -lt -0.3) { 'çıkış' } else { 'nötr' } } else { 'nötr' } }
        } | Where-Object { $null -ne $_.weeklyPct } | Sort-Object weeklyPct -Descending | Select-Object -First 12)
    } catch { $sectorRotation = @() }

    # ---- sectorFlow (Sankey icin TAHMINI rotasyon akisi — GERCEK sermaye takibi DEGIL) ----
    # Zayiflayan sektorlerden (kaynak) guclenen sektorlere (hedef) orantisal akis: her
    # kaynagin toplam "cikis" buyuklugu, hedeflerin goreli "giris" payina gore bolusturulur
    # (flow(i,j) = |kaynak_i| * hedef_j / toplam_hedef). Boylece her kaynagin TOPLAM giden
    # akisi kendi buyuklugune esittir (dogru); hedefler arasi PAYLASIM da orantili dogrudur;
    # yalniz hedeflerin MUTLAK toplami olcek sabitiyle carpilir (Sankey'de zaten goreli
    # boyut onemlidir). Tek zaman dilimi (aylik, yoksa haftalik) kullanilir — karisik
    # donemler kiyaslanmaz. Kaynak/hedef en fazla 5'er ile sinirlanir (okunabilirlik).
    $sectorFlow = @()
    $sectorFlowBasis = 'aylık'
    try {
        $flowBasis = @($sectorRotation | Where-Object { $null -ne $_.monthlyPct })
        $useKey = 'monthlyPct'
        if ($flowBasis.Count -lt 2) { $flowBasis = @($sectorRotation); $useKey = 'weeklyPct'; $sectorFlowBasis = 'haftalık' }
        $sources = @($flowBasis | Where-Object { [double](Get-DashProp -Object $_ -Name $useKey) -lt 0 } |
            ForEach-Object { [pscustomobject]@{ Name = $_.sector; Mag = [Math]::Abs([double](Get-DashProp -Object $_ -Name $useKey)) } } |
            Sort-Object Mag -Descending | Select-Object -First 5)
        $sinks = @($flowBasis | Where-Object { [double](Get-DashProp -Object $_ -Name $useKey) -gt 0 } |
            ForEach-Object { [pscustomobject]@{ Name = $_.sector; Mag = [double](Get-DashProp -Object $_ -Name $useKey) } } |
            Sort-Object Mag -Descending | Select-Object -First 5)
        $totalSinkMag = if ($sinks.Count -gt 0) { ($sinks | Measure-Object -Property Mag -Sum).Sum } else { 0 }
        if ($sources.Count -gt 0 -and $sinks.Count -gt 0 -and $totalSinkMag -gt 0) {
            foreach ($src in $sources) {
                foreach ($snk in $sinks) {
                    $flowVal = [Math]::Round($src.Mag * ($snk.Mag / $totalSinkMag), 3)
                    if ($flowVal -gt 0.01) { $sectorFlow += [pscustomobject]@{ from = $src.Name; to = $snk.Name; flow = $flowVal } }
                }
            }
        }
    } catch { $sectorFlow = @() }

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

    # ---- technicalSignals (RSI/trend/MACD/kırılım — tek anlık görüntüden dürüst türevler) ----
    $ob = @($Stocks | Where-Object { $r = Get-DashNum -Object $_ -Name 'RSI'; $null -ne $r -and $r -ge 70 } | Sort-Object @{ Expression = { Get-DashNum -Object $_ -Name 'RSI' }; Descending = $true } | Select-Object -First 8 | ForEach-Object { [pscustomobject]@{ ticker = (Get-DashStr -Object $_ -Name 'Symbol'); rsi = (Get-DashNum -Object $_ -Name 'RSI') } })
    $os = @($Stocks | Where-Object { $r = Get-DashNum -Object $_ -Name 'RSI'; $null -ne $r -and $r -le 30 } | Sort-Object @{ Expression = { Get-DashNum -Object $_ -Name 'RSI' } } | Select-Object -First 8 | ForEach-Object { [pscustomobject]@{ ticker = (Get-DashStr -Object $_ -Name 'Symbol'); rsi = (Get-DashNum -Object $_ -Name 'RSI') } })

    # MACD kesişimi YAKINDA: MacdLine ile MacdSignal birbirine cok yakinsa (fiyata oranla)
    # bir kesisim yaklastigi/yeni gerceklestigi anlamina gelir (tek anlik goruntuden dogru
    # tespit edilebilecek tek durum; "az once kesisti" gecmis veri gerektirir, iddia edilmez).
    $macdCross = @($Stocks | ForEach-Object {
            $line = Get-DashNum -Object $_ -Name 'MacdLine'; $sig = Get-DashNum -Object $_ -Name 'MacdSignal'; $price = Get-DashNum -Object $_ -Name 'Price'
            if ($null -eq $line -or $null -eq $sig -or $null -eq $price -or $price -le 0) { return }
            $gapPct = [Math]::Abs($line - $sig) / $price * 100.0
            if ($gapPct -le 0.15) {
                $crossNote = 'Düşüş kesişimine yakın'
                if ($line -ge $sig) { $crossNote = 'Yükseliş kesişimine yakın' }
                [pscustomobject]@{ ticker = (Get-DashStr -Object $_ -Name 'Symbol'); note = $crossNote; _g = $gapPct }
            }
        } | Sort-Object _g | Select-Object -First 8 | Select-Object ticker, note)

    # Trend guclenen: fiyat SMA20/50/200'un ustunde (tam boga hizalanmasi) + bugun pozitif.
    $trendUp = @($Stocks | ForEach-Object {
            $p = Get-DashNum -Object $_ -Name 'Price'; $s20 = Get-DashNum -Object $_ -Name 'SMA20'; $s50 = Get-DashNum -Object $_ -Name 'SMA50'; $s200 = Get-DashNum -Object $_ -Name 'SMA200'
            $ch = Get-DashNum -Object $_ -Name 'ChangePct'
            if ($null -eq $p -or $null -eq $s20 -or $null -eq $s50 -or $null -eq $s200 -or $s200 -le 0) { return }
            if ($p -gt $s20 -and $s20 -gt $s50 -and $s50 -gt $s200 -and $null -ne $ch -and $ch -gt 0) {
                $margin = ($p / $s200 - 1) * 100.0
                [pscustomobject]@{ ticker = (Get-DashStr -Object $_ -Name 'Symbol'); note = ('200g üstünde %{0} — tam boğa hizalanması' -f [Math]::Round($margin, 1)); _m = $margin }
            }
        } | Sort-Object _m -Descending | Select-Object -First 8 | Select-Object ticker, note)

    # Momentum kaybeden: orta/uzun vade hala yukarida (SMA50 ustu) ama kisa vadeli momentum (MACD histogram) negatife donmus.
    $momLosing = @($Stocks | ForEach-Object {
            $p = Get-DashNum -Object $_ -Name 'Price'; $s50 = Get-DashNum -Object $_ -Name 'SMA50'; $mh = Get-DashNum -Object $_ -Name 'MacdHistogram'
            if ($null -eq $p -or $null -eq $s50 -or $null -eq $mh -or $s50 -le 0) { return }
            if ($p -gt $s50 -and $mh -lt 0) {
                [pscustomobject]@{ ticker = (Get-DashStr -Object $_ -Name 'Symbol'); note = 'Trend hâlâ yukarı (50g üstü) ama MACD momentumu negatife döndü'; _h = $mh }
            }
        } | Sort-Object _h | Select-Object -First 8 | Select-Object ticker, note)

    # Kirilim/risk: yuksek goreli hacimle guclu fiyat hareketi (yon belirtilir; hem yukari kirilim hem asagi risk).
    $breakout = @($Stocks | ForEach-Object {
            $rv = Get-DashNum -Object $_ -Name 'RelativeVolume'; $ch = Get-DashNum -Object $_ -Name 'ChangePct'
            if ($null -eq $rv -or $rv -lt 2.0 -or $null -eq $ch -or [Math]::Abs($ch) -lt 3.0) { return }
            $dirNote = 'aşağı kırılma riski'
            if ($ch -gt 0) { $dirNote = 'yukarı kırılım' }
            [pscustomobject]@{ ticker = (Get-DashStr -Object $_ -Name 'Symbol'); note = ('Hacim {0}x + %{1} hareket — {2}' -f [Math]::Round($rv, 1), [Math]::Round($ch, 1), $dirNote); _rv = $rv }
        } | Sort-Object _rv -Descending | Select-Object -First 8 | Select-Object ticker, note)

    $technicalSignals = [ordered]@{
        overbought = $ob; oversold = $os
        macdCross = $macdCross; trendStrengthening = $trendUp; momentumLosing = $momLosing; breakout = $breakout
    }

    # ---- llmCommentary (ay sonu portföy yorumu — markdown-lite ayrıştırılır) ----
    $commentText = Get-DashStr -Object $PortfolioCommentary -Name 'Text'
    if (-not $commentText) { $commentText = if ($PortfolioCommentary -is [string]) { [string]$PortfolioCommentary } else { $null } }
    $commentaryTitle = $null
    $commentarySections = @()
    if ($commentText) {
        $lines = $commentText -split "`n"
        $curHeading = $null; $curBuf = New-Object System.Collections.Generic.List[string]
        $flush = {
            if ($curHeading -or $curBuf.Count -gt 0) {
                $txt = (($curBuf.ToArray() | Where-Object { $_.Trim() -ne '' }) -join "`n`n").Trim()
                if ($curHeading -or $txt) {
                    $commentarySections += [pscustomobject]@{ heading = $curHeading; text = $txt }
                }
            }
        }
        foreach ($ln in $lines) {
            if ($ln -match '^#\s+(.*)$') { $commentaryTitle = $Matches[1].Trim() }
            elseif ($ln -match '^#{2,4}\s+(.*)$') {
                . $flush
                $curHeading = $Matches[1].Trim(); $curBuf = New-Object System.Collections.Generic.List[string]
            }
            else { [void]$curBuf.Add($ln) }
        }
        . $flush
        $commentarySections = @($commentarySections | Where-Object { $_.text -or $_.heading })
    }
    $llmCommentary = [ordered]@{
        stance = $null
        marketSummary = $null
        portfolioComment = $commentText
        portfolioCommentTitle = $commentaryTitle
        portfolioCommentSections = $commentarySections
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

    # ---- modelPortfolios (TÜM model portföyler: Dengeli/Değer/Momentum/Kalite/RFS100/... ) ----
    $modelPortfolios = @($portfolios | ForEach-Object {
        $ph = @(Get-DashProp -Object $_ -Name 'Holdings')
        [pscustomobject]@{
            id                 = (Get-DashStr -Object $_ -Name 'Id')
            name               = (Get-DashStr -Object $_ -Name 'Name')
            strategy           = (Get-DashStr -Object $_ -Name 'Strategy')
            rankBy             = (Get-DashStr -Object $_ -Name 'RankBy')
            valueTL            = (Get-DashNum -Object $_ -Name 'CurrentValueTL')
            returnPct          = (Get-DashNum -Object $_ -Name 'TotalReturnPct')
            benchmarkReturnPct = (Get-DashNum -Object $_ -Name 'BenchmarkReturnPct')
            alphaPct           = (Get-DashNum -Object $_ -Name 'AlphaPct')
            holdings = @($ph | ForEach-Object {
                [pscustomobject]@{ ticker = (Get-DashStr -Object $_ -Name 'Symbol'); weightPct = (Get-DashNum -Object $_ -Name 'WeightPct') }
            })
        }
    })

    # ---- instantEntry (Anlık Giriş — kapalı döngü: 100k sermaye, 5k/gün) ----
    $ieHoldings = @(Get-DashProp -Object $InstantEntryPortfolio -Name 'Holdings')
    $instantEntry = if ($null -ne $InstantEntryPortfolio) {
        [pscustomobject]@{
            initialCapitalTL = (Get-DashNum -Object $InstantEntryPortfolio -Name 'InitialCapitalTL')
            cashTL           = (Get-DashNum -Object $InstantEntryPortfolio -Name 'CashTL')
            holdingsValueTL  = (Get-DashNum -Object $InstantEntryPortfolio -Name 'HoldingsValueTL')
            totalValueTL     = (Get-DashNum -Object $InstantEntryPortfolio -Name 'TotalValueTL')
            totalReturnPct   = (Get-DashNum -Object $InstantEntryPortfolio -Name 'TotalReturnPct')
            totalBoughtTL    = (Get-DashNum -Object $InstantEntryPortfolio -Name 'TotalBoughtTL')
            realizedGainTL   = (Get-DashNum -Object $InstantEntryPortfolio -Name 'RealizedGainTL')
            dailyBudgetTL    = (Get-DashNum -Object $InstantEntryPortfolio -Name 'DailyBudgetTL')
            statusNote       = (Get-DashStr -Object $InstantEntryPortfolio -Name 'StatusNote')
            holdings = @($ieHoldings | ForEach-Object {
                [pscustomobject]@{
                    ticker = (Get-DashStr -Object $_ -Name 'Symbol'); company = (Get-DashStr -Object $_ -Name 'Company')
                    weightPct = (Get-DashNum -Object $_ -Name 'WeightPct'); valueTL = (Get-DashNum -Object $_ -Name 'CurrentValueTL')
                    gainPct = (Get-DashNum -Object $_ -Name 'UnrealizedGainPct')
                }
            })
        }
    } else { $null }

    return [pscustomobject][ordered]@{
        meta = [pscustomobject]$meta
        history = @([pscustomobject]@{ date = $meta.reportDate; label = 'Son rapor' })
        summary = [pscustomobject]$summary
        performance = [pscustomobject]$performance
        allocation = [pscustomobject]$allocation
        modelPortfolios = $modelPortfolios
        instantEntry = $instantEntry
        stocks = $topRows
        sectorRotation = $sectorRotation
        sectorFlow = $sectorFlow
        sectorFlowBasis = $sectorFlowBasis
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
