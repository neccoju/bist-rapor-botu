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
    # dikkat: '$v -eq ""' sayisal 0'i da elerdi (PS tip donusumu); yalniz bos string'i ele
    if ($null -eq $v -or ($v -is [string] -and [string]::IsNullOrWhiteSpace($v))) { return $null }
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

function Get-DashRiskMetrics {
    <#
        Kurumsal portfoy risk metrikleri — panelin gunluk kumulatif % serilerinden
        ({t,v} noktalari) SAF MATEMATIKLE hesaplanir; ek veri kaynagi gerektirmez.
        Varsayimlar (durustluk): risksiz faiz = 0, yillikastirma 252 is gunu,
        getiriler ORTAK tarihlerde hizalanir. En az 10 ortak gunluk getiri yoksa
        insufficient=true doner (kisa gecmiste metrik uydurulmaz).
    #>
    param($PfPoints, $BenchPoints)

    $pfMap = @{}
    foreach ($p in @($PfPoints)) {
        $t = [string](Get-DashProp -Object $p -Name 't'); $v = Get-DashNum -Object $p -Name 'v'
        if ($t -and $null -ne $v) { $pfMap[$t] = 1.0 + $v / 100.0 }
    }
    $bMap = @{}
    foreach ($p in @($BenchPoints)) {
        $t = [string](Get-DashProp -Object $p -Name 't'); $v = Get-DashNum -Object $p -Name 'v'
        if ($t -and $null -ne $v) { $bMap[$t] = 1.0 + $v / 100.0 }
    }
    $hasBench = $bMap.Count -gt 1
    $dates = if ($hasBench) { @($pfMap.Keys | Where-Object { $bMap.ContainsKey($_) } | Sort-Object) } else { @($pfMap.Keys | Sort-Object) }

    $rp = New-Object System.Collections.Generic.List[double]
    $rb = New-Object System.Collections.Generic.List[double]
    $peak = $null; $maxDD = 0.0
    for ($i = 0; $i -lt $dates.Count; $i++) {
        $lvl = [double]$pfMap[$dates[$i]]
        if ($null -eq $peak -or $lvl -gt $peak) { $peak = $lvl }
        elseif ($peak -gt 0) { $dd = ($lvl / $peak - 1.0) * 100.0; if ($dd -lt $maxDD) { $maxDD = $dd } }
        if ($i -gt 0) {
            $prev = [double]$pfMap[$dates[$i - 1]]
            if ($prev -gt 0) { [void]$rp.Add($lvl / $prev - 1.0) }
            if ($hasBench) {
                $bPrev = [double]$bMap[$dates[$i - 1]]; $bCur = [double]$bMap[$dates[$i]]
                if ($bPrev -gt 0) { [void]$rb.Add($bCur / $bPrev - 1.0) }
            }
        }
    }
    $n = $rp.Count
    if ($n -lt 10) { return [pscustomobject]@{ days = $n; insufficient = $true } }

    $ann = [Math]::Sqrt(252.0)
    $meanP = 0.0; foreach ($r in $rp) { $meanP += $r }; $meanP /= $n
    $varP = 0.0; foreach ($r in $rp) { $varP += ($r - $meanP) * ($r - $meanP) }
    $sdP = if ($n -gt 1) { [Math]::Sqrt($varP / ($n - 1)) } else { 0.0 }
    $ddSum = 0.0; foreach ($r in $rp) { if ($r -lt 0) { $ddSum += $r * $r } }
    $downDev = [Math]::Sqrt($ddSum / $n)
    $annRetPct = $meanP * 252.0 * 100.0

    $sharpe = if ($sdP -gt 1e-12) { [Math]::Round($meanP / $sdP * $ann, 2) } else { $null }
    $sortino = if ($downDev -gt 1e-12) { [Math]::Round($meanP / $downDev * $ann, 2) } else { $null }
    $calmar = if ($maxDD -lt -0.01) { [Math]::Round($annRetPct / [Math]::Abs($maxDD), 2) } else { $null }

    $beta = $null; $alphaPct = $null; $tePct = $null; $ir = $null; $corr = $null
    if ($hasBench -and $rb.Count -eq $n -and $n -gt 1) {
        $meanB = 0.0; foreach ($r in $rb) { $meanB += $r }; $meanB /= $n
        $cov = 0.0; $varB = 0.0; $teVar = 0.0; $teMean = 0.0
        for ($i = 0; $i -lt $n; $i++) {
            $dp = $rp[$i] - $meanP; $db = $rb[$i] - $meanB
            $cov += $dp * $db; $varB += $db * $db
            $teMean += ($rp[$i] - $rb[$i])
        }
        $cov /= ($n - 1); $varB /= ($n - 1); $teMean /= $n
        for ($i = 0; $i -lt $n; $i++) { $d = ($rp[$i] - $rb[$i]) - $teMean; $teVar += $d * $d }
        $teSd = [Math]::Sqrt($teVar / ($n - 1))
        if ($varB -gt 1e-12) {
            $beta = [Math]::Round($cov / $varB, 2)
            $alphaPct = [Math]::Round(($meanP - ($cov / $varB) * $meanB) * 252.0 * 100.0, 2)
        }
        $tePct = [Math]::Round($teSd * $ann * 100.0, 2)
        if ($teSd -gt 1e-12) { $ir = [Math]::Round($teMean / $teSd * $ann, 2) }
        $sdB = [Math]::Sqrt($varB)
        if ($sdP -gt 1e-12 -and $sdB -gt 1e-12) { $corr = [Math]::Round($cov / ($sdP * $sdB), 2) }
    }

    return [pscustomobject][ordered]@{
        days = $n
        insufficient = $false
        annVolPct = [Math]::Round($sdP * $ann * 100.0, 2)
        annReturnPct = [Math]::Round($annRetPct, 2)
        sharpe = $sharpe
        sortino = $sortino
        maxDrawdownPct = [Math]::Round($maxDD, 2)
        calmar = $calmar
        beta = $beta
        alphaAnnPct = $alphaPct
        trackingErrorPct = $tePct
        infoRatio = $ir
        correlation = $corr
    }
}

function Get-DashKapNews {
    <#
        data/kap_enrichment.json'dan (LLM ile zenginlestirilmis KAP bildirimleri)
        panel icin haber listesi uretir. directionRefined: '+'=pozitif '-'=negatif
        '~'=notr '?'=belirsiz. Best-effort: dosya yoksa/bozuksa bos dizi.
    #>
    param([string]$DataDir)
    try {
        if ([string]::IsNullOrWhiteSpace($DataDir)) { $DataDir = Join-Path $PSScriptRoot 'data' }
        $path = Join-Path $DataDir 'kap_enrichment.json'
        if (-not (Test-Path -LiteralPath $path)) { return @() }
        $enr = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $items = Get-DashProp -Object $enr -Name 'items'
        if ($null -eq $items) { return @() }
        $rows = @()
        foreach ($prop in $items.PSObject.Properties) {
            $it = $prop.Value
            $dir = Get-DashStr -Object $it -Name 'directionRefined'
            if (-not $dir) { $dir = Get-DashStr -Object $it -Name 'directionHint' }
            $impact = switch ($dir) { '+' { 'pozitif' } '-' { 'negatif' } '~' { 'nötr' } default { 'belirsiz' } }
            $dateStr = Get-DashStr -Object $it -Name 'date'
            $dt = $null
            try { $dt = [datetime]::ParseExact($dateStr, 'dd.MM.yyyy HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture) } catch { $dt = [datetime]::MinValue }
            $rows += [pscustomobject]@{
                symbol = (Get-DashStr -Object $it -Name 'symbol'); title = (Get-DashStr -Object $it -Name 'title')
                date = $dateStr; impact = $impact; summary = (Get-DashStr -Object $it -Name 'summary'); _dt = $dt
            }
        }
        return @($rows | Sort-Object _dt -Descending | Select-Object -First 12 | Select-Object symbol, title, date, impact, summary)
    }
    catch { return @() }
}

function Get-DashForeignFlow {
    <#
        data/mkk_foreign.json'dan (MKK kaynakli yabanci saklama orani, haftalik
        collector) panel icin yabanci takas ozeti uretir. Donen deger:
        @{ map = @{SYM=pct}; panel = {updatedAt,note,count,risers,fallers} }.
        Best-effort: dosya yoksa/bozuksa $null (panel karti gizlenir).
    #>
    param([string]$DataDir)
    try {
        if ([string]::IsNullOrWhiteSpace($DataDir)) { $DataDir = Join-Path $PSScriptRoot 'data' }
        $path = Join-Path $DataDir 'mkk_foreign.json'
        if (-not (Test-Path -LiteralPath $path)) { return $null }
        $ff = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $items = Get-DashProp -Object $ff -Name 'items'
        if ($null -eq $items) { return $null }
        $rows = @()
        foreach ($prop in $items.PSObject.Properties) {
            $pct = Get-DashNum -Object $prop.Value -Name 'foreignPct'
            if ($null -eq $pct) { continue }
            $rows += [pscustomobject]@{ ticker = $prop.Name; pct = $pct; chg = (Get-DashNum -Object $prop.Value -Name 'chg1wBps') }
        }
        if (-not $rows.Count) { return $null }
        $map = @{}
        foreach ($r in $rows) { $map[$r.ticker] = $r.pct }
        $risers = @($rows | Where-Object { $null -ne $_.chg -and $_.chg -gt 0 } | Sort-Object chg -Descending | Select-Object -First 6)
        $fallers = @($rows | Where-Object { $null -ne $_.chg -and $_.chg -lt 0 } | Sort-Object chg | Select-Object -First 6)
        return @{
            map   = $map
            panel = [pscustomobject]@{
                updatedAt = (Get-DashStr -Object $ff -Name 'generatedAt')
                note      = (Get-DashStr -Object $ff -Name 'asOfNote')
                count     = $rows.Count
                risers    = $risers
                fallers   = $fallers
            }
        }
    }
    catch { return $null }
}

function Get-DashTefasFlow {
    <#
        data/tefas_flows.json'dan (haftalik TEFAS collector) yerli hisse fonu
        net akis ozetini panel icin okur. Best-effort: dosya yoksa/bozuksa $null.
        flow1wTL null olabilir (ilk kosu yalniz baz olusturur) — panel bunu
        "baz olusturuldu" diye gosterir.
    #>
    param([string]$DataDir)
    try {
        if ([string]::IsNullOrWhiteSpace($DataDir)) { $DataDir = Join-Path $PSScriptRoot 'data' }
        $path = Join-Path $DataDir 'tefas_flows.json'
        if (-not (Test-Path -LiteralPath $path)) { return $null }
        $tf = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $mapTop = { param($rows) @($rows | ForEach-Object {
                [pscustomobject]@{ code = (Get-DashStr -Object $_ -Name 'code'); name = (Get-DashStr -Object $_ -Name 'name'); flowTL = (Get-DashNum -Object $_ -Name 'flowTL') }
            } | Where-Object { $_.code }) }
        return [pscustomobject]@{
            asOf            = (Get-DashStr -Object $tf -Name 'asOf')
            note            = (Get-DashStr -Object $tf -Name 'note')
            equityFundCount = (Get-DashNum -Object $tf -Name 'equityFundCount')
            totalAumTL      = (Get-DashNum -Object $tf -Name 'totalAumTL')
            flow1wTL        = (Get-DashNum -Object $tf -Name 'flow1wTL')
            flow4wTL        = (Get-DashNum -Object $tf -Name 'flow4wTL')
            topInflow       = (& $mapTop (Get-DashProp -Object $tf -Name 'topInflow'))
            topOutflow      = (& $mapTop (Get-DashProp -Object $tf -Name 'topOutflow'))
        }
    }
    catch { return $null }
}

function Get-DashDataHealth {
    <#
        Saglayici saglik ozeti: her collector dosyasinin son basarili veri yasi.
        Sessiz kirilmalarin (kaynak API degisti, cron durdu) erken uyarisi.
        status: taze | bayat | yok. Best-effort; okunamayan dosya 'yok' sayilir.
    #>
    param([string]$DataDir)
    if ([string]::IsNullOrWhiteSpace($DataDir)) { $DataDir = Join-Path $PSScriptRoot 'data' }
    $sources = @(
        @{ File = 'mkk_foreign.json'; Name = 'Yabancı oran'; FreshHours = 36 },
        @{ File = 'tefas_flows.json'; Name = 'TEFAS akış'; FreshHours = 192 },
        @{ File = 'macro_news.json'; Name = 'Makro haber'; FreshHours = 36 },
        @{ File = 'kap_enrichment.json'; Name = 'KAP yorum'; FreshHours = 36 }
    )
    $nowUtc = (Get-Date).ToUniversalTime()
    return @($sources | ForEach-Object {
            $src = $_
            $ageH = $null; $status = 'yok'
            try {
                $p = Join-Path $DataDir $src.File
                if (Test-Path -LiteralPath $p) {
                    $doc = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
                    $gen = Get-DashStr -Object $doc -Name 'generatedAt'
                    if ($gen) {
                        $ageH = [Math]::Round(($nowUtc - ([datetime]::Parse($gen)).ToUniversalTime()).TotalHours, 1)
                        $status = if ($ageH -le $src.FreshHours) { 'taze' } else { 'bayat' }
                    }
                }
            }
            catch { $status = 'yok' }
            [pscustomobject]@{ source = [string]$src.Name; file = [string]$src.File; ageHours = $ageH; status = $status }
        })
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
        [string]$PagesUrl = $null,
        $MacroSnapshot = $null,
        [string]$DataDir = $null,
        [object[]]$StructureSignals = @(),
        $ForeignMarketFlow = $null
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

    # USD-REEL getiri (TR baglami): TL kumulatif getiriyi USD/TRY degisimiyle
    # deflate et -> "dolar bazinda ne kazandik". USD/TRY serisi benchmark'ta
    # 'usdtry' anahtarli. Ortak son tarihte: usdRet = ((1+tl/100)/(1+usd/100)-1)*100.
    $usdSeries = @($series | Where-Object { [string]$_.key -eq 'usdtry' } | Select-Object -First 1)
    $usdMap = @{}
    if ($usdSeries) { foreach ($p in @($usdSeries.points)) { $usdMap[[string]$p.t] = [double]$p.v } }
    $usdReturnOf = {
        param($pfSeries)
        if (-not $usdSeries -or -not $pfSeries) { return $null }
        $common = @(@($pfSeries.points) | Where-Object { $usdMap.ContainsKey([string]$_.t) } | Sort-Object { [string]$_.t })
        if ($common.Count -eq 0) { return $null }
        $last = $common[$common.Count - 1]
        $tlRet = [double]$last.v; $usdRet = [double]$usdMap[[string]$last.t]
        if ((1 + $usdRet / 100.0) -le 0) { return $null }
        return [Math]::Round(((1 + $tlRet / 100.0) / (1 + $usdRet / 100.0) - 1) * 100.0, 2)
    }
    # Her portfoy serisine usdReturnPct ekle (gorunum; karar etkisi yok).
    foreach ($s in $series) {
        if ([string]$s.key -like 'pf_*') {
            $s | Add-Member -NotePropertyName 'usdReturnPct' -NotePropertyValue (& $usdReturnOf $s) -Force
        }
    }
    $performance = [ordered]@{ note = if ($series.Count -eq 0) { 'Performans serisi henüz üretilmedi.' } else { $null }; series = $series }

    # Birincil portfoyun USD-reel getirisini summary basligina ekle.
    $primaryId = Get-DashStr -Object $primary -Name 'Id'
    $primaryUsdSeries = @($series | Where-Object { [string]$_.key -eq ('pf_' + $primaryId) } | Select-Object -First 1)
    $summary.usdMonthlyChangePct = if ($primaryUsdSeries) { $primaryUsdSeries.usdReturnPct } else { $null }

    # ---- riskMetrics (TUM portfoyler icin Sharpe/Sortino/Calmar/MaxDD/Beta/Alfa/TE/IR/korelasyon) ----
    # Mevcut gunluk serilerden saf matematik; BIST100 serisi benchmark. Ek veri kaynagi yok.
    $benchPts = $null
    foreach ($s in $series) { if ([string]$s.key -eq 'bist100') { $benchPts = $s.points; break } }
    $riskMetrics = @()
    foreach ($s in $series) {
        if ([string]$s.key -notlike 'pf_*') { continue }
        try {
            $m = Get-DashRiskMetrics -PfPoints $s.points -BenchPoints $benchPts
            $riskMetrics += [pscustomobject]@{ id = ([string]$s.key).Substring(3); name = [string]$s.name; metrics = $m }
        } catch { }
    }
    $riskNote = 'Varsayımlar: risksiz faiz=0, 252 gün yıllıklaştırma, BIST100 benchmark. Kısa geçmişte (≲60 gün) metrikler gürültülüdür; yön göstergesi olarak okuyun.'

    # ---- allocation (birincil portföy holding'leri) ----
    $holds = @(Get-DashProp -Object $primary -Name 'Holdings')
    $target = if ($holds.Count -gt 0) { [Math]::Round(100.0 / $holds.Count, 1) } else { $null }
    $allocHoldings = @($holds | ForEach-Object {
        [pscustomobject]@{ ticker = (Get-DashStr -Object $_ -Name 'Symbol'); company = (Get-DashStr -Object $_ -Name 'Company'); weightPct = (Get-DashNum -Object $_ -Name 'WeightPct'); targetPct = $target }
    })
    $needsReb = $false
    foreach ($h in $allocHoldings) { if ($null -ne $h.weightPct -and $null -ne $target -and [Math]::Abs([double]$h.weightPct - [double]$target) -gt 3.0) { $needsReb = $true } }
    $allocation = [ordered]@{ rebalanceNeeded = $needsReb; rebalanceNote = if ($needsReb) { 'Bazı ağırlıklar hedeften >3 puan sapmış.' } else { $null }; holdings = $allocHoldings }

    # ---- foreignFlow (MKK kaynakli yabanci saklama orani — dosyadan best-effort) ----
    $ffData = Get-DashForeignFlow -DataDir $DataDir
    $ffMap = if ($null -ne $ffData) { $ffData.map } else { $null }

    # ---- tefasFlow (TEFAS hisse fonu net akisi — dosyadan best-effort) ----
    $tefasFlow = Get-DashTefasFlow -DataDir $DataDir

    # foreignFlow paneli: hisse bazli MKK verisi + piyasa geneli TCMB haftalik
    # net seri (EVDS TP.MKNETHAR.M7) tek blokta birlesir; ikisi de best-effort.
    $foreignFlowPanel = if ($null -ne $ffData) { $ffData.panel } else { $null }
    if ($null -ne $ForeignMarketFlow) {
        if ($null -eq $foreignFlowPanel) {
            $foreignFlowPanel = [pscustomobject]@{ updatedAt = $null; note = $null; count = $null; risers = @(); fallers = @() }
        }
        $foreignFlowPanel | Add-Member -NotePropertyName market -NotePropertyValue $ForeignMarketFlow -Force
    }

    # ---- stocks (en yüksek skorlu TopStocks) ----
    $topRows = @($Stocks |
        Sort-Object @{ Expression = { $v = Get-DashNum -Object $_ -Name 'Score'; if ($null -ne $v) { $v } else { -1 } }; Descending = $true } |
        Select-Object -First $TopStocks |
        ForEach-Object {
            $rv = Get-DashNum -Object $_ -Name 'RelativeVolume'
            $tkSym = Get-DashStr -Object $_ -Name 'Symbol'
            [pscustomobject]@{
                ticker    = $tkSym
                company   = (Get-DashStr -Object $_ -Name 'Company')
                price     = (Get-DashNum -Object $_ -Name 'Price')
                dailyPct  = (Get-DashNum -Object $_ -Name 'ChangePct')
                weeklyPct = (Get-DashNum -Object $_ -Name 'PerfWeek')
                rsi       = (Get-DashNum -Object $_ -Name 'RSI')
                macd      = (Get-DashNum -Object $_ -Name 'MacdHistogram')
                volume    = if ($null -ne $rv) { ([string]([Math]::Round($rv, 2)) + 'x') } else { $null }
                foreignPct = if ($null -ne $ffMap -and $tkSym -and $ffMap.ContainsKey($tkSym)) { $ffMap[$tkSym] } else { $null }
                signal    = (Get-DashStr -Object $_ -Name 'Signal')
                # 4-skor kirilimi (aciklanabilirlik): temel = deger+kalite+bilanco
                # ort.; teknik = trend+momentum ort.; makro = MakroSektor bileseni;
                # final = Score (tum ayarlar dahil). Alan yoksa null.
                fundamentalScore = $(
                    $fv = @((Get-DashNum -Object $_ -Name 'ValueScore'), (Get-DashNum -Object $_ -Name 'QualityScore'), (Get-DashNum -Object $_ -Name 'EarningsScore')) | Where-Object { $null -ne $_ }
                    if ($fv.Count) { [Math]::Round(($fv | Measure-Object -Average).Average, 0) } else { $null }
                )
                technicalScore = $(
                    $tv = @((Get-DashNum -Object $_ -Name 'TrendScore'), (Get-DashNum -Object $_ -Name 'MomentumScore')) | Where-Object { $null -ne $_ }
                    if ($tv.Count) { [Math]::Round(($tv | Measure-Object -Average).Average, 0) } else { $null }
                )
                macroScore = (Get-DashNum -Object $_ -Name 'MacroSectorScore')
                finalScore = (Get-DashNum -Object $_ -Name 'Score')
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
    # items: en yuksek goreli hacimli belirgin hareketler (>=2x) — panelde 'Para Akisi' kartini doldurur.
    $smItems = @($Stocks | ForEach-Object {
            $rv = Get-DashNum -Object $_ -Name 'RelativeVolume'; $ch = Get-DashNum -Object $_ -Name 'ChangePct'
            if ($null -eq $rv -or $rv -lt 2.0 -or $null -eq $ch) { return }
            $typ = 'Yoğun satış'; if ($ch -gt 0) { $typ = 'Yoğun alım' }
            [pscustomobject]@{ ticker = (Get-DashStr -Object $_ -Name 'Symbol'); type = $typ
                note = ('Göreli hacim {0}x · günlük %{1}' -f [Math]::Round($rv, 1), [Math]::Round($ch, 1)); _rv = $rv }
        } | Where-Object { $_ } | Sort-Object _rv -Descending | Select-Object -First 6 | Select-Object ticker, type, note)
    $smartMoney = [ordered]@{
        commentary = if ($strengthening.Count -or $weakening.Count) { 'Göreli hacmi 1,5x ve üzeri olan hisselerde yön ayrışması (otomatik türetildi).' } else { $null }
        items = $smItems
        strengthening = @($strengthening | Where-Object { $_ })
        weakening = @($weakening | Where-Object { $_ })
    }

    # ---- heatmap (tum evren: sektor gruplu, gunluk % ile renklendirilecek kompakt dizi) ----
    $heatmap = @($Stocks | ForEach-Object {
            $sec = Get-DashStr -Object $_ -Name 'SectorTR'; $tk = Get-DashStr -Object $_ -Name 'Symbol'
            $dp = Get-DashNum -Object $_ -Name 'ChangePct'
            if ($sec -and $tk -and $null -ne $dp) { [pscustomobject]@{ t = $tk; s = $sec; d = [Math]::Round($dp, 2) } }
        } | Where-Object { $_ } | Select-Object -First 700)

    # ---- macro (Get-MacroSnapshot -> panel karti; yalniz gosterim, karar mantigina dokunmaz) ----
    $macro = $null
    if ($null -ne $MacroSnapshot) {
        try {
            $mItems = @(Get-DashProp -Object $MacroSnapshot -Name 'Metrics' | ForEach-Object {
                    [pscustomobject]@{ id = (Get-DashStr -Object $_ -Name 'Id'); name = (Get-DashStr -Object $_ -Name 'Name')
                        value = (Get-DashNum -Object $_ -Name 'Value'); changePct = (Get-DashNum -Object $_ -Name 'ChangePct')
                        unit = (Get-DashStr -Object $_ -Name 'Unit'); status = (Get-DashStr -Object $_ -Name 'Status')
                        note = (Get-DashStr -Object $_ -Name 'Note') }
                } | Where-Object { $_.name })
            $sup = Get-DashNum -Object $MacroSnapshot -Name 'SupportiveCount'
            $pre = Get-DashNum -Object $MacroSnapshot -Name 'PressureCount'
            $riskApp = $null
            if ($null -ne $sup -and $null -ne $pre -and ($sup + $pre) -gt 0) { $riskApp = [Math]::Round(100.0 * $sup / ($sup + $pre), 0) }
            # Rejim ozeti (varsa): deterministik motorun etiketi + en guclu tiltler.
            $regimeObj = Get-DashProp -Object $MacroSnapshot -Name 'Regime'
            $regimePanel = $null
            if ($null -ne $regimeObj) {
                $tiltRows = @()
                $tiltMap = Get-DashProp -Object $regimeObj -Name 'SectorTilts'
                if ($null -ne $tiltMap) {
                    $tiltRows = @($tiltMap.Keys | ForEach-Object { [pscustomobject]@{ sector = [string]$_; tilt = [double]$tiltMap[$_] } } |
                            Sort-Object @{ Expression = { [Math]::Abs($_.tilt) }; Descending = $true } | Select-Object -First 4)
                }
                $regimePanel = [pscustomobject]@{
                    label = (Get-DashStr -Object $regimeObj -Name 'Regime')
                    score = (Get-DashNum -Object $regimeObj -Name 'Score')
                    confidence = (Get-DashNum -Object $regimeObj -Name 'Confidence')
                    tilts = $tiltRows
                    events = @(Get-DashProp -Object $regimeObj -Name 'Events' | ForEach-Object {
                            [pscustomobject]@{ type = (Get-DashStr -Object $_ -Name 'Type'); direction = (Get-DashNum -Object $_ -Name 'Direction'); note = (Get-DashStr -Object $_ -Name 'Note') }
                        } | Select-Object -First 6)
                }
            }
            $macro = [pscustomobject]@{ status = (Get-DashStr -Object $MacroSnapshot -Name 'Status')
                supportiveCount = $sup; pressureCount = $pre; riskAppetite = $riskApp
                regime = $regimePanel
                note = (Get-DashStr -Object $MacroSnapshot -Name 'MeasurementNote'); items = $mItems }
        } catch { $macro = $null }
    }

    # ---- kapNews (LLM ile zenginlestirilmis KAP bildirimleri — dosyadan best-effort) ----
    $kapNews = Get-DashKapNews -DataDir $DataDir

    # ---- dataHealth (saglayici saglik rozetleri — sessiz kirilma erken uyarisi) ----
    $dataHealth = @(Get-DashDataHealth -DataDir $DataDir)

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

    # Yapisal sinyaller (Darvas/Wyckoff — Yahoo H/L serisinden, rapor akisinda hesaplanip verilir)
    $structures = @($StructureSignals | ForEach-Object {
            $tk = Get-DashStr -Object $_ -Name 'Symbol'
            if (-not $tk) { return }
            $typ = Get-DashStr -Object $_ -Name 'Type'; $nt = Get-DashStr -Object $_ -Name 'Note'
            [pscustomobject]@{ ticker = $tk; note = (@($typ, $nt) | Where-Object { $_ }) -join ' — ' }
        } | Where-Object { $_ } | Select-Object -First 8)

    $technicalSignals = [ordered]@{
        overbought = $ob; oversold = $os
        macdCross = $macdCross; trendStrengthening = $trendUp; momentumLosing = $momLosing; breakout = $breakout
        structures = $structures
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

    # pf_<Id> serisinden USD-reel getiri haritasi (modelPortfolios'a bagla).
    $usdReturnById = @{}
    foreach ($s in $series) {
        if ([string]$s.key -like 'pf_*' -and $null -ne $s.usdReturnPct) {
            $usdReturnById[([string]$s.key).Substring(3)] = $s.usdReturnPct
        }
    }

    # ---- modelPortfolios (TÜM model portföyler: Dengeli/Değer/Momentum/Kalite/RFS100/... ) ----
    $modelPortfolios = @($portfolios | ForEach-Object {
        $ph = @(Get-DashProp -Object $_ -Name 'Holdings')
        $pfId = (Get-DashStr -Object $_ -Name 'Id')
        [pscustomobject]@{
            id                 = $pfId
            name               = (Get-DashStr -Object $_ -Name 'Name')
            strategy           = (Get-DashStr -Object $_ -Name 'Strategy')
            rankBy             = (Get-DashStr -Object $_ -Name 'RankBy')
            valueTL            = (Get-DashNum -Object $_ -Name 'CurrentValueTL')
            returnPct          = (Get-DashNum -Object $_ -Name 'TotalReturnPct')
            usdReturnPct       = if ($pfId -and $usdReturnById.ContainsKey($pfId)) { $usdReturnById[$pfId] } else { $null }
            benchmarkReturnPct = (Get-DashNum -Object $_ -Name 'BenchmarkReturnPct')
            alphaPct           = (Get-DashNum -Object $_ -Name 'AlphaPct')
            drawdownPct        = (Get-DashNum -Object $_ -Name 'CurrentDrawdownPct')
            circuitBreaker     = (Get-DashStr -Object $_ -Name 'CircuitBreakerState')
            holdings = @($ph | ForEach-Object {
                [pscustomobject]@{ ticker = (Get-DashStr -Object $_ -Name 'Symbol'); weightPct = (Get-DashNum -Object $_ -Name 'WeightPct')
                    selectionReason = (Get-DashStr -Object $_ -Name 'SelectionReason') }
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
        riskMetrics = $riskMetrics
        riskNote = $riskNote
        macro = $macro
        kapNews = $kapNews
        foreignFlow = $foreignFlowPanel
        tefasFlow = $tefasFlow
        dataHealth = $dataHealth
        heatmap = $heatmap
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
        [string]$PagesUrl = $null,
        $MacroSnapshot = $null,
        [object[]]$StructureSignals = @(),
        $ForeignMarketFlow = $null
    )
    $report = ConvertTo-DashboardReport -Stocks $Stocks -PortfolioSet $PortfolioSet -InstantEntryPortfolio $InstantEntryPortfolio `
        -StrategySeries $StrategySeries -BenchmarkSeries $BenchmarkSeries -MarketBreadth $MarketBreadth `
        -PortfolioCommentary $PortfolioCommentary -AsOf $AsOf -Strategy $Strategy -PrimaryPortfolioId $PrimaryPortfolioId `
        -TopStocks $TopStocks -PagesUrl $PagesUrl -MacroSnapshot $MacroSnapshot -DataDir (Join-Path $PSScriptRoot 'data') `
        -StructureSignals $StructureSignals -ForeignMarketFlow $ForeignMarketFlow
    $dir = Split-Path -Parent $OutPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutPath -Encoding UTF8
    return $OutPath
}
