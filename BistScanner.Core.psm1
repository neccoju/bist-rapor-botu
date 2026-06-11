Set-StrictMode -Version Latest

$script:TradingViewScannerUrl = 'https://scanner.tradingview.com/turkey/scan'
$script:TradingViewColumns = @(
    'name',
    'description',
    'close',
    'change',
    'volume',
    'market_cap_basic',
    'price_earnings_ttm',
    'price_book_fq',
    'return_on_equity_fq',
    'debt_to_equity_fq',
    'dividends_yield_current',
    'Recommend.All',
    'RSI',
    'SMA20',
    'SMA50',
    'SMA200',
    'relative_volume_10d_calc',
    'Volatility.D',
    'sector',
    'industry',
    'Perf.W',
    'Perf.1M',
    'Perf.3M',
    'Perf.6M',
    'Perf.Y',
    'average_volume_10d_calc',
    'fundamental_currency_code',
    'fiscal_period_end_fq',
    'earnings_release_date',
    'earnings_release_next_date',
    'net_income_fq_h',
    'total_revenue_fq_h',
    'total_assets_fq_h',
    'total_debt_fq_h',
    'free_cash_flow_fq_h',
    'oper_income_fq',
    'Perf.3Y',
    'Perf.5Y',
    'MACD.macd',
    'MACD.signal',
    'MACD.hist',
    'RSI|1W',
    'RSI|1M',
    'MACD.macd|1W',
    'MACD.signal|1W',
    'MACD.hist|1W',
    'MACD.macd|1M',
    'MACD.signal|1M',
    'MACD.hist|1M',
    'enterprise_value_ebitda_current',
    'enterprise_value_ebitda_ttm',
    'ebitda_fq',
    'ebitda_fq_h',
    'ebitda_ttm'
)

$script:BenchmarkColumns = @(
    'name',
    'description',
    'close',
    'change',
    'Perf.W',
    'Perf.1M',
    'Perf.3M',
    'Perf.Y',
    'Perf.3Y',
    'Perf.5Y',
    'SMA200',
    'MACD.macd',
    'MACD.signal',
    'MACD.hist'
)
$script:BenchmarkTickers = @(
    'BIST:XU100',
    'BIST:XBANK',
    'BIST:XU030',
    'BIST:XUSIN',
    'BIST:XUTEK',
    'BIST:XGIDA',
    'BIST:XELKT',
    'BIST:XINSA',
    'BIST:XULAS',
    'BIST:XHOLD'
)
$script:MacroInvestingInstruments = @(
    [pscustomobject]@{ Id = 'TR_CDS_5Y'; Name = 'Türkiye 5Y CDS'; Urls = @('https://tr.investing.com/rates-bonds/turkey-cds-5-year-usd', 'https://www.investing.com/rates-bonds/turkey-cds-5-year-usd'); Unit = 'bp'; LowerIsBetter = $true },
    [pscustomobject]@{ Id = 'TR_10Y'; Name = 'Türkiye 10Y tahvil faizi'; Urls = @('https://tr.investing.com/rates-bonds/turkey-10-year-bond-yield', 'https://www.investing.com/rates-bonds/turkey-10-year-bond-yield'); Unit = '%'; LowerIsBetter = $true },
    [pscustomobject]@{ Id = 'DXY'; Name = 'Dolar Endeksi DXY'; Urls = @('https://tr.investing.com/indices/usdollar', 'https://www.investing.com/indices/usdollar'); Unit = ''; LowerIsBetter = $true },
    [pscustomobject]@{ Id = 'VIX'; Name = 'VIX volatilite'; Urls = @('https://tr.investing.com/indices/volatility-s-p-500', 'https://www.investing.com/indices/volatility-s-p-500'); Unit = ''; LowerIsBetter = $true }
)
$script:InflationBenchmark = [pscustomobject][ordered]@{
    AsOf = 'Nisan 2026'
    Inflation1YPct = 32.37
    Inflation3YPct = 209.9
    Inflation5YPct = 656.7
    SourceNote = 'TÜİK Nisan 2026 yıllık TÜFE %32,37; 3Y ve 5Y eşikler Nisan yıllık TÜFE oranlarının bileşik yaklaşık değeridir.'
}

function ConvertTo-DoubleOrNull {
    param($Value)

    if ($null -eq $Value -or $Value -eq '') {
        return $null
    }

    try {
        return [Convert]::ToDouble($Value, [Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        return $null
    }
}

function ConvertTo-DoubleArray {
    param($Value)

    if ($null -eq $Value) {
        return @()
    }

    $result = foreach ($item in @($Value)) {
        ConvertTo-DoubleOrNull $item
    }

    return @($result)
}

function ConvertFrom-UnixSecondsOrNull {
    param($Value)

    $seconds = ConvertTo-DoubleOrNull $Value
    if ($null -eq $seconds -or $seconds -le 0) {
        return $null
    }

    try {
        return [DateTimeOffset]::FromUnixTimeSeconds([long]$seconds).UtcDateTime
    }
    catch {
        return $null
    }
}

function Get-ObjectPropertyValue {
    param(
        $Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-TurkishSectorName {
    param([string]$Sector)

    $sectorNames = @{
        'Commercial Services' = 'Ticari Hizmetler'
        'Communications' = 'İletişim'
        'Consumer Durables' = 'Dayanıklı Tüketim'
        'Consumer Non-Durables' = 'Dayanıksız Tüketim'
        'Consumer Services' = 'Tüketici Hizmetleri'
        'Distribution Services' = 'Dağıtım Hizmetleri'
        'Electronic Technology' = 'Elektronik Teknoloji'
        'Energy Minerals' = 'Enerji Hammaddeleri'
        'Finance' = 'Finans'
        'Health Services' = 'Sağlık Hizmetleri'
        'Health Technology' = 'Sağlık Teknolojisi'
        'Industrial Services' = 'Endüstriyel Hizmetler'
        'Miscellaneous' = 'Çeşitli'
        'Non-Energy Minerals' = 'Enerji Dışı Mineraller'
        'Process Industries' = 'Süreç Endüstrileri'
        'Producer Manufacturing' = 'Üretici İmalat'
        'Retail Trade' = 'Perakende Ticaret'
        'Technology Services' = 'Teknoloji Hizmetleri'
        'Transportation' = 'Ulaştırma'
        'Utilities' = 'Altyapı Hizmetleri'
    }

    if ([string]::IsNullOrWhiteSpace($Sector)) {
        return 'Sektör Verisi Yok'
    }

    if ($sectorNames.ContainsKey($Sector)) {
        return $sectorNames[$Sector]
    }

    return $Sector
}

function Limit-Value {
    param(
        [double]$Value,
        [double]$Minimum = 0,
        [double]$Maximum = 100
    )

    return [Math]::Max($Minimum, [Math]::Min($Maximum, $Value))
}

function Get-GrowthPercent {
    param(
        $Current,
        $Previous
    )

    if ($null -eq $Current -or $null -eq $Previous -or [double]$Previous -eq 0) {
        return $null
    }

    return (([double]$Current / [double]$Previous) - 1) * 100
}

function Get-QuarterLabel {
    param([datetime]$PeriodEnd)

    $quarter = [Math]::Ceiling($PeriodEnd.Month / 3)
    return '{0}/Q{1}' -f $PeriodEnd.Year, $quarter
}

function Get-TcmbUsdTryRate {
    param(
        [datetime]$Date,
        [int]$TimeoutSec = 15
    )

    for ($offset = 0; $offset -le 7; $offset++) {
        $candidate = $Date.Date.AddDays(-$offset)
        $url = 'https://www.tcmb.gov.tr/kurlar/{0}/{1}.xml' -f `
            $candidate.ToString('yyyyMM'), `
            $candidate.ToString('ddMMyyyy')

        try {
            $xml = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec $TimeoutSec -ErrorAction Stop
            $usd = @($xml.Tarih_Date.Currency | Where-Object Kod -eq 'USD') | Select-Object -First 1
            $rate = ConvertTo-DoubleOrNull $usd.ForexBuying
            if ($null -ne $rate -and $rate -gt 0) {
                return [pscustomobject]@{
                    RequestedDate = $Date.Date
                    RateDate = $candidate
                    Rate = $rate
                }
            }
        }
        catch {
            # Hafta sonu, tatil veya geçici bağlantı hatasında önceki güne bakılır.
        }
    }

    return $null
}

function Get-TcmbUsdTryRates {
    param(
        [datetime[]]$Dates,
        [int]$TimeoutSec = 15
    )

    $rates = @{}
    foreach ($date in @($Dates | Sort-Object -Unique)) {
        $key = $date.Date.ToString('yyyy-MM-dd')
        if (-not $rates.ContainsKey($key)) {
            $rates[$key] = Get-TcmbUsdTryRate -Date $date -TimeoutSec $TimeoutSec
        }
    }

    return $rates
}

function Get-ArrayValue {
    param(
        [object[]]$Values,
        [int]$Index
    )

    if ($null -eq $Values -or $Index -lt 0 -or $Index -ge $Values.Count) {
        return $null
    }

    return $Values[$Index]
}

function Convert-TryToUsd {
    param(
        $Value,
        $Rate
    )

    if ($null -eq $Value -or $null -eq $Rate -or [double]$Rate -le 0) {
        return $null
    }

    return [double]$Value / [double]$Rate
}

function Get-RoundedDifference {
    param(
        $Value,
        $Benchmark
    )

    if ($null -eq $Value -or $null -eq $Benchmark) {
        return $null
    }

    return [Math]::Round(([double]$Value - [double]$Benchmark), 1)
}

function Get-AverageNumber {
    param([object[]]$Values)

    $validValues = @(
        foreach ($value in @($Values)) {
            $number = ConvertTo-DoubleOrNull $value
            if ($null -ne $number) {
                $number
            }
        }
    )

    if ($validValues.Count -eq 0) {
        return $null
    }

    return [Math]::Round(($validValues | Measure-Object -Average).Average, 1)
}

function Get-SectorWatchIndexSymbol {
    param([string]$Sector)

    switch ($Sector) {
        'Finance' { return 'XBANK' }
        'Miscellaneous' { return 'XHOLD' }
        'Consumer Non-Durables' { return 'XGIDA' }
        'Technology Services' { return 'XUTEK' }
        'Electronic Technology' { return 'XUTEK' }
        'Utilities' { return 'XELKT' }
        'Industrial Services' { return 'XINSA' }
        'Transportation' { return 'XULAS' }
        'Producer Manufacturing' { return 'XUSIN' }
        'Process Industries' { return 'XUSIN' }
        'Non-Energy Minerals' { return 'XUSIN' }
        default { return 'Sektör proxy' }
    }
}

function ConvertFrom-TradingViewBenchmarkItem {
    param($Item)

    $values = @($Item.d)
    $mapped = New-Object object[] $script:BenchmarkColumns.Count
    for ($index = 0; $index -lt $script:BenchmarkColumns.Count; $index++) {
        if ($index -lt $values.Count) {
            $mapped[$index] = $values[$index]
        }
    }

    return [pscustomobject][ordered]@{
        Symbol = [string]$mapped[0]
        Company = [string]$mapped[1]
        TradingViewSymbol = [string]$Item.s
        Price = ConvertTo-DoubleOrNull $mapped[2]
        ChangePct = ConvertTo-DoubleOrNull $mapped[3]
        PerfWeek = ConvertTo-DoubleOrNull $mapped[4]
        PerfMonth = ConvertTo-DoubleOrNull $mapped[5]
        Perf3Month = ConvertTo-DoubleOrNull $mapped[6]
        PerfYear = ConvertTo-DoubleOrNull $mapped[7]
        Perf3Year = ConvertTo-DoubleOrNull $mapped[8]
        Perf5Year = ConvertTo-DoubleOrNull $mapped[9]
        SMA200 = ConvertTo-DoubleOrNull $mapped[10]
        MacdLine = ConvertTo-DoubleOrNull $mapped[11]
        MacdSignal = ConvertTo-DoubleOrNull $mapped[12]
        MacdHistogram = ConvertTo-DoubleOrNull $mapped[13]
    }
}

function Get-BistIndexBenchmarks {
    param([int]$TimeoutSec = 20)

    $empty = [pscustomobject][ordered]@{
        Bist100 = $null
        XBank = $null
        X30 = $null
        Indices = @{}
        SourceNote = 'BIST benchmark verisi alınamadı.'
    }

    $payload = @{
        filter = @()
        options = @{ lang = 'tr' }
        markets = @('turkey')
        symbols = @{
            query = @{ types = @() }
            tickers = $script:BenchmarkTickers
        }
        columns = $script:BenchmarkColumns
        sort = @{ sortBy = 'name'; sortOrder = 'asc' }
        range = @(0, $script:BenchmarkTickers.Count)
    }

    $headers = @{
        'User-Agent' = 'BIST-Hisse-Tarayici/1.0'
        'Accept' = 'application/json'
    }

    try {
        $response = Invoke-RestMethod `
            -Method Post `
            -Uri $script:TradingViewScannerUrl `
            -ContentType 'application/json' `
            -Headers $headers `
            -Body ($payload | ConvertTo-Json -Depth 8 -Compress) `
            -TimeoutSec $TimeoutSec `
            -ErrorAction Stop
    }
    catch {
        return $empty
    }

    if ($null -eq $response.data -or $response.data.Count -eq 0) {
        return $empty
    }

    $map = @{}
    foreach ($item in @($response.data)) {
        $benchmark = ConvertFrom-TradingViewBenchmarkItem -Item $item
        $map[[string]$benchmark.TradingViewSymbol] = $benchmark
        $map[[string]$benchmark.Symbol] = $benchmark
    }

    $bist100 = if ($map.ContainsKey('BIST:XU100')) { $map['BIST:XU100'] } elseif ($map.ContainsKey('XU100')) { $map['XU100'] } else { $null }
    $xbank = if ($map.ContainsKey('BIST:XBANK')) { $map['BIST:XBANK'] } elseif ($map.ContainsKey('XBANK')) { $map['XBANK'] } else { $null }
    $x30 = if ($map.ContainsKey('BIST:XU030')) { $map['BIST:XU030'] } elseif ($map.ContainsKey('XU030')) { $map['XU030'] } else { $null }

    return [pscustomobject][ordered]@{
        Bist100 = $bist100
        XBank = $xbank
        X30 = $x30
        Indices = $map
        SourceNote = 'BIST100, BIST30, XBANK ve seçili sektör endeksleri TradingView tarayıcısından alınır; endeks dönmediğinde sektör hisse ortalaması proxy olarak kullanılır.'
    }
}

function Get-SectorBenchmarkMap {
    param(
        [object[]]$Stocks,
        $IndexSnapshot
    )

    $bist100 = Get-ObjectPropertyValue -Object $IndexSnapshot -Name 'Bist100'
    $indices = Get-ObjectPropertyValue -Object $IndexSnapshot -Name 'Indices'
    if ($null -eq $indices) {
        $indices = @{}
    }
    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($group in @($Stocks | Group-Object SectorTR)) {
        $groupStocks = @($group.Group)
        $sector = [string]($groupStocks | Select-Object -First 1).Sector
        $watchIndex = Get-SectorWatchIndexSymbol -Sector $sector
        $indexSymbol = if ($watchIndex -ne 'Sektör proxy') { "BIST:$watchIndex" } else { $null }
        $indexBenchmark = if ($null -ne $indexSymbol -and $indices.ContainsKey($indexSymbol)) {
            $indices[$indexSymbol]
        }
        elseif ($watchIndex -ne 'Sektör proxy' -and $indices.ContainsKey($watchIndex)) {
            $indices[$watchIndex]
        }
        else {
            $null
        }

        $avgChange = Get-AverageNumber -Values @($groupStocks | ForEach-Object { $_.ChangePct })
        $avgPerfWeek = Get-AverageNumber -Values @($groupStocks | ForEach-Object { $_.PerfWeek })
        $avgPerfMonth = Get-AverageNumber -Values @($groupStocks | ForEach-Object { $_.PerfMonth })
        $avgPerf3Month = Get-AverageNumber -Values @($groupStocks | ForEach-Object { $_.Perf3Month })
        $avgPerfYear = Get-AverageNumber -Values @($groupStocks | ForEach-Object { $_.PerfYear })
        $avgPerf3Year = Get-AverageNumber -Values @($groupStocks | ForEach-Object { $_.Perf3Year })
        $avgPerf5Year = Get-AverageNumber -Values @($groupStocks | ForEach-Object { $_.Perf5Year })
        $avgRevenue = Get-AverageNumber -Values @($groupStocks | ForEach-Object { $_.RevenueUsdYoYPct })
        $avgNetIncome = Get-AverageNumber -Values @($groupStocks | ForEach-Object { $_.NetIncomeUsdYoYPct })
        $avgEbitda = Get-AverageNumber -Values @($groupStocks | ForEach-Object { $_.EbitdaUsdYoYPct })

        $indexSource = if ($null -ne $indexBenchmark) { "$watchIndex endeks verisi" } else { 'Sektör hisse ortalaması proxy' }
        $indexChange = if ($null -ne $indexBenchmark -and $null -ne $indexBenchmark.ChangePct) { $indexBenchmark.ChangePct } else { $avgChange }
        $indexPerfWeek = if ($null -ne $indexBenchmark -and $null -ne $indexBenchmark.PerfWeek) { $indexBenchmark.PerfWeek } else { $avgPerfWeek }
        $indexPerfMonth = if ($null -ne $indexBenchmark -and $null -ne $indexBenchmark.PerfMonth) { $indexBenchmark.PerfMonth } else { $avgPerfMonth }
        $indexPerf3Month = if ($null -ne $indexBenchmark -and $null -ne $indexBenchmark.Perf3Month) { $indexBenchmark.Perf3Month } else { $avgPerf3Month }
        $indexPerfYear = if ($null -ne $indexBenchmark -and $null -ne $indexBenchmark.PerfYear) { $indexBenchmark.PerfYear } else { $avgPerfYear }

        $sectorVsBistDay = Get-RoundedDifference -Value $indexChange -Benchmark (Get-ObjectPropertyValue -Object $bist100 -Name 'ChangePct')
        $sectorVsBistWeek = Get-RoundedDifference -Value $indexPerfWeek -Benchmark (Get-ObjectPropertyValue -Object $bist100 -Name 'PerfWeek')
        $sectorVsBistMonth = Get-RoundedDifference -Value $indexPerfMonth -Benchmark (Get-ObjectPropertyValue -Object $bist100 -Name 'PerfMonth')
        $sectorVsBist3Month = Get-RoundedDifference -Value $indexPerf3Month -Benchmark (Get-ObjectPropertyValue -Object $bist100 -Name 'Perf3Month')
        $sectorVsBistYear = Get-RoundedDifference -Value $indexPerfYear -Benchmark (Get-ObjectPropertyValue -Object $bist100 -Name 'PerfYear')
        $rotationAverage = Get-AverageNumber -Values @($sectorVsBistDay, $sectorVsBistWeek, $sectorVsBistMonth, $sectorVsBist3Month, $sectorVsBistYear)

        $rotationLabel = if ($null -eq $rotationAverage) {
            'Veri Yok'
        }
        elseif ($rotationAverage -ge 10) {
            'Güçlü Rotasyon'
        }
        elseif ($rotationAverage -ge 3) {
            'BIST Üstü'
        }
        elseif ($rotationAverage -le -5) {
            'Zayıf'
        }
        else {
            'Nötr'
        }

        [void]$rows.Add([pscustomobject][ordered]@{
                SectorTR = [string]$group.Name
                Sector = $sector
                StockCount = $groupStocks.Count
                WatchIndex = $watchIndex
                IndexSource = $indexSource
                ChangePctAvg = $avgChange
                PerfWeekAvg = $avgPerfWeek
                PerfMonthAvg = $avgPerfMonth
                Perf3MonthAvg = $avgPerf3Month
                PerfYearAvg = $avgPerfYear
                Perf3YearAvg = $avgPerf3Year
                Perf5YearAvg = $avgPerf5Year
                SectorIndexChangePct = $indexChange
                SectorIndexPerfWeek = $indexPerfWeek
                SectorIndexPerfMonth = $indexPerfMonth
                SectorIndexPerf3Month = $indexPerf3Month
                SectorIndexPerfYear = $indexPerfYear
                SectorVsBistDay = $sectorVsBistDay
                SectorVsBistWeek = $sectorVsBistWeek
                SectorVsBistMonth = $sectorVsBistMonth
                SectorVsBist3Month = $sectorVsBist3Month
                SectorVsBistYear = $sectorVsBistYear
                SectorRotationAverage = $rotationAverage
                RotationLabel = $rotationLabel
                RevenueUsdYoYPctAvg = $avgRevenue
                NetIncomeUsdYoYPctAvg = $avgNetIncome
                EbitdaUsdYoYPctAvg = $avgEbitda
            })
    }

    $map = @{}
    foreach ($row in $rows) {
        $map[[string]$row.SectorTR] = $row
    }

    return $map
}

function Add-MacroSectorBenchmarks {
    param(
        [object[]]$Stocks,
        $IndexSnapshot
    )

    $sectorMap = Get-SectorBenchmarkMap -Stocks $Stocks -IndexSnapshot $IndexSnapshot
    $bist100 = Get-ObjectPropertyValue -Object $IndexSnapshot -Name 'Bist100'
    $bistSourceNote = Get-ObjectPropertyValue -Object $IndexSnapshot -Name 'SourceNote'

    foreach ($stock in @($Stocks)) {
        $sectorBench = if ($sectorMap.ContainsKey([string]$stock.SectorTR)) { $sectorMap[[string]$stock.SectorTR] } else { $null }
        $properties = [ordered]@{}
        foreach ($property in $stock.PSObject.Properties) {
            if ($property.Name -notin @(
                    'InflationBenchmarkAsOf', 'Inflation1YPct', 'Inflation3YPct', 'Inflation5YPct',
                    'StockVsInflation1YPct', 'StockVsInflation3YPct', 'StockVsInflation5YPct',
                    'Bist100ChangePct', 'Bist100PerfWeek', 'Bist100PerfMonth',
                    'Bist100Perf3Month', 'Bist100PerfYear', 'Bist100Perf3Year', 'Bist100Perf5Year',
                    'StockVsBist1YPct', 'StockVsBist3YPct', 'StockVsBist5YPct',
                    'SectorWatchIndex', 'SectorBenchmarkSource', 'SectorStockCount',
                    'SectorChangePctAvg', 'SectorPerfWeekAvg', 'SectorPerfMonthAvg',
                    'SectorPerf3MonthAvg', 'SectorPerfYearAvg', 'SectorPerf3YearAvg', 'SectorPerf5YearAvg',
                    'SectorIndexChangePct', 'SectorIndexPerfWeek', 'SectorIndexPerfMonth',
                    'SectorIndexPerf3Month', 'SectorIndexPerfYear',
                    'SectorVsBistDay', 'SectorVsBistWeek', 'SectorVsBistMonth',
                    'SectorVsBist3Month', 'SectorVsBistYear', 'SectorRotationAverage', 'SectorRotationLabel',
                    'SectorRevenueUsdYoYPctAvg', 'SectorNetIncomeUsdYoYPctAvg', 'SectorEbitdaUsdYoYPctAvg',
                    'RevenueVsSectorPct', 'NetIncomeVsSectorPct', 'EbitdaVsSectorPct', 'MacroDataNote'
                )) {
                $properties[$property.Name] = $property.Value
            }
        }

        $properties.InflationBenchmarkAsOf = $script:InflationBenchmark.AsOf
        $properties.Inflation1YPct = $script:InflationBenchmark.Inflation1YPct
        $properties.Inflation3YPct = $script:InflationBenchmark.Inflation3YPct
        $properties.Inflation5YPct = $script:InflationBenchmark.Inflation5YPct
        $properties.StockVsInflation1YPct = Get-RoundedDifference -Value $stock.PerfYear -Benchmark $script:InflationBenchmark.Inflation1YPct
        $properties.StockVsInflation3YPct = Get-RoundedDifference -Value $stock.Perf3Year -Benchmark $script:InflationBenchmark.Inflation3YPct
        $properties.StockVsInflation5YPct = Get-RoundedDifference -Value $stock.Perf5Year -Benchmark $script:InflationBenchmark.Inflation5YPct

        $properties.Bist100ChangePct = Get-ObjectPropertyValue -Object $bist100 -Name 'ChangePct'
        $properties.Bist100PerfWeek = Get-ObjectPropertyValue -Object $bist100 -Name 'PerfWeek'
        $properties.Bist100PerfMonth = Get-ObjectPropertyValue -Object $bist100 -Name 'PerfMonth'
        $properties.Bist100Perf3Month = Get-ObjectPropertyValue -Object $bist100 -Name 'Perf3Month'
        $properties.Bist100PerfYear = Get-ObjectPropertyValue -Object $bist100 -Name 'PerfYear'
        $properties.Bist100Perf3Year = Get-ObjectPropertyValue -Object $bist100 -Name 'Perf3Year'
        $properties.Bist100Perf5Year = Get-ObjectPropertyValue -Object $bist100 -Name 'Perf5Year'
        $properties.StockVsBist1YPct = Get-RoundedDifference -Value $stock.PerfYear -Benchmark $properties.Bist100PerfYear
        $properties.StockVsBist3YPct = Get-RoundedDifference -Value $stock.Perf3Year -Benchmark $properties.Bist100Perf3Year
        $properties.StockVsBist5YPct = Get-RoundedDifference -Value $stock.Perf5Year -Benchmark $properties.Bist100Perf5Year

        $properties.SectorWatchIndex = Get-ObjectPropertyValue -Object $sectorBench -Name 'WatchIndex'
        $properties.SectorBenchmarkSource = Get-ObjectPropertyValue -Object $sectorBench -Name 'IndexSource'
        $properties.SectorStockCount = Get-ObjectPropertyValue -Object $sectorBench -Name 'StockCount'
        $properties.SectorChangePctAvg = Get-ObjectPropertyValue -Object $sectorBench -Name 'ChangePctAvg'
        $properties.SectorPerfWeekAvg = Get-ObjectPropertyValue -Object $sectorBench -Name 'PerfWeekAvg'
        $properties.SectorPerfMonthAvg = Get-ObjectPropertyValue -Object $sectorBench -Name 'PerfMonthAvg'
        $properties.SectorPerf3MonthAvg = Get-ObjectPropertyValue -Object $sectorBench -Name 'Perf3MonthAvg'
        $properties.SectorPerfYearAvg = Get-ObjectPropertyValue -Object $sectorBench -Name 'PerfYearAvg'
        $properties.SectorPerf3YearAvg = Get-ObjectPropertyValue -Object $sectorBench -Name 'Perf3YearAvg'
        $properties.SectorPerf5YearAvg = Get-ObjectPropertyValue -Object $sectorBench -Name 'Perf5YearAvg'
        $properties.SectorIndexChangePct = Get-ObjectPropertyValue -Object $sectorBench -Name 'SectorIndexChangePct'
        $properties.SectorIndexPerfWeek = Get-ObjectPropertyValue -Object $sectorBench -Name 'SectorIndexPerfWeek'
        $properties.SectorIndexPerfMonth = Get-ObjectPropertyValue -Object $sectorBench -Name 'SectorIndexPerfMonth'
        $properties.SectorIndexPerf3Month = Get-ObjectPropertyValue -Object $sectorBench -Name 'SectorIndexPerf3Month'
        $properties.SectorIndexPerfYear = Get-ObjectPropertyValue -Object $sectorBench -Name 'SectorIndexPerfYear'
        $properties.SectorVsBistDay = Get-ObjectPropertyValue -Object $sectorBench -Name 'SectorVsBistDay'
        $properties.SectorVsBistWeek = Get-ObjectPropertyValue -Object $sectorBench -Name 'SectorVsBistWeek'
        $properties.SectorVsBistMonth = Get-ObjectPropertyValue -Object $sectorBench -Name 'SectorVsBistMonth'
        $properties.SectorVsBist3Month = Get-ObjectPropertyValue -Object $sectorBench -Name 'SectorVsBist3Month'
        $properties.SectorVsBistYear = Get-ObjectPropertyValue -Object $sectorBench -Name 'SectorVsBistYear'
        $properties.SectorRotationAverage = Get-ObjectPropertyValue -Object $sectorBench -Name 'SectorRotationAverage'
        $properties.SectorRotationLabel = Get-ObjectPropertyValue -Object $sectorBench -Name 'RotationLabel'
        $properties.SectorRevenueUsdYoYPctAvg = Get-ObjectPropertyValue -Object $sectorBench -Name 'RevenueUsdYoYPctAvg'
        $properties.SectorNetIncomeUsdYoYPctAvg = Get-ObjectPropertyValue -Object $sectorBench -Name 'NetIncomeUsdYoYPctAvg'
        $properties.SectorEbitdaUsdYoYPctAvg = Get-ObjectPropertyValue -Object $sectorBench -Name 'EbitdaUsdYoYPctAvg'
        $properties.RevenueVsSectorPct = Get-RoundedDifference -Value $stock.RevenueUsdYoYPct -Benchmark $properties.SectorRevenueUsdYoYPctAvg
        $properties.NetIncomeVsSectorPct = Get-RoundedDifference -Value $stock.NetIncomeUsdYoYPct -Benchmark $properties.SectorNetIncomeUsdYoYPctAvg
        $properties.EbitdaVsSectorPct = Get-RoundedDifference -Value $stock.EbitdaUsdYoYPct -Benchmark $properties.SectorEbitdaUsdYoYPctAvg
        $properties.MacroDataNote = "$($script:InflationBenchmark.SourceNote) $bistSourceNote CDS, DXY, VIX, TR10Y ve USD/TRY raporun Makro Görünüm bölümünde izleme metriği olarak gösterilir; ücretsiz kaynaklar gecikmeli veya eksik olabilir."

        [pscustomobject]$properties
    }
}

function ConvertFrom-InvestingNumberText {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text) -or $text -eq '-') {
        return $null
    }

    $text = $text -replace '\s', ''
    $text = $text -replace '%', ''
    $text = $text -replace '\+', ''

    if ($text -match ',' -and $text -match '\.') {
        $lastComma = $text.LastIndexOf(',')
        $lastDot = $text.LastIndexOf('.')
        if ($lastComma -gt $lastDot) {
            $text = $text -replace '\.', ''
            $text = $text -replace ',', '.'
        }
        else {
            $text = $text -replace ',', ''
        }
    }
    elseif ($text -match ',') {
        $text = $text -replace ',', '.'
    }

    return ConvertTo-DoubleOrNull $text
}

function Get-PlainTextLinesFromHtml {
    param([string]$Html)

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return @()
    }

    $decoded = [Net.WebUtility]::HtmlDecode($Html)
    $text = $decoded -replace '<script[\s\S]*?</script>', ' '
    $text = $text -replace '<style[\s\S]*?</style>', ' '
    $text = $text -replace '<[^>]+>', [Environment]::NewLine
    return @(
        $text -split "(`r`n|`n|`r)" |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-InvestingInstrumentSnapshot {
    param(
        [string]$Id,
        [string]$Name,
        [string[]]$Urls,
        [string]$Unit = '',
        [bool]$LowerIsBetter = $true,
        [int]$TimeoutSec = 6
    )

    $headers = @{
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36'
        'Accept' = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        'Accept-Language' = 'en-US,en;q=0.9,tr;q=0.8'
    }

    $lastError = 'URL listesi boş'
    foreach ($url in @($Urls)) {
        try {
        $response = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
        $content = [string]$response.Content
        $valueText = $null
        $changeText = $null
        $changePctText = $null

        foreach ($pattern in @(
                'data-test="instrument-price-last"[^>]*>([^<]+)',
                '"last"\s*:\s*"?([0-9\.,]+)"?',
                '"last_close"\s*:\s*"?([0-9\.,]+)"?'
            )) {
            $match = [regex]::Match($content, $pattern, 'IgnoreCase')
            if ($match.Success) {
                $valueText = $match.Groups[1].Value
                break
            }
        }

        $changeMatch = [regex]::Match($content, 'data-test="instrument-price-change"[^>]*>([^<]+)', 'IgnoreCase')
        if ($changeMatch.Success) {
            $changeText = $changeMatch.Groups[1].Value
        }
        $changePctMatch = [regex]::Match($content, 'data-test="instrument-price-change-percent"[^>]*>\(?([^<\)]+)\)?', 'IgnoreCase')
        if ($changePctMatch.Success) {
            $changePctText = $changePctMatch.Groups[1].Value
        }

        if ([string]::IsNullOrWhiteSpace($valueText)) {
            $lines = @(Get-PlainTextLinesFromHtml -Html $content)
            $nameIndex = -1
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match [regex]::Escape($Name) -or $lines[$i] -match 'TRGV5YUSAC=R' -or $lines[$i] -match 'TR10YT=XX') {
                    $nameIndex = $i
                    break
                }
            }

            if ($nameIndex -ge 0) {
                for ($i = $nameIndex + 1; $i -lt [Math]::Min($lines.Count, $nameIndex + 20); $i++) {
                    if ($lines[$i] -match '^[+-]?[0-9]{1,4}([\.,][0-9]+)?$') {
                        $valueText = $lines[$i]
                        break
                    }
                }
            }
        }

        $value = ConvertFrom-InvestingNumberText $valueText
        $change = ConvertFrom-InvestingNumberText $changeText
        $changePct = ConvertFrom-InvestingNumberText $changePctText
        if ($null -eq $value) {
            throw 'fiyat alanı ayrıştırılamadı'
        }

        $direction = if ($null -eq $changePct) {
            'Veri Yok'
        }
        elseif (($LowerIsBetter -and $changePct -le 0) -or (-not $LowerIsBetter -and $changePct -ge 0)) {
            'Destekleyici'
        }
        else {
            'Baskı'
        }

        return [pscustomobject][ordered]@{
            Id = $Id
            Name = $Name
            Value = [Math]::Round([double]$value, 2)
            Change = if ($null -ne $change) { [Math]::Round([double]$change, 2) } else { $null }
            ChangePct = if ($null -ne $changePct) { [Math]::Round([double]$changePct, 2) } else { $null }
            Unit = $Unit
            Status = $direction
            Source = 'Investing.com'
            Url = $url
            Note = 'Ücretsiz web kaynağı; gecikmeli veya eksik olabilir.'
        }
    }
    catch {
        $lastError = $_.Exception.Message
        continue
    }
    }

    return [pscustomobject][ordered]@{
        Id = $Id
        Name = $Name
        Value = $null
        Change = $null
        ChangePct = $null
        Unit = $Unit
        Status = 'Veri Yok'
        Source = 'Investing.com'
        Url = (@($Urls) -join ' | ')
        Note = "Alınamadı: $lastError"
    }
}

function Get-MarketMetricStatus {
    param(
        [string]$Id,
        $Value,
        $ChangePct
    )

    switch ($Id) {
        'TR_CDS_5Y' {
            if ($null -eq $Value) { return 'Veri Yok' }
            if ($Value -le 250) { return 'Risk primi destekleyici' }
            if ($Value -le 350) { return 'Risk primi izlenmeli' }
            return 'Risk primi baskı yaratıyor'
        }
        'TR_10Y' {
            if ($null -eq $Value) { return 'Veri Yok' }
            if ($Value -le 30) { return 'Faiz baskısı görece düşük' }
            if ($Value -le 40) { return 'Faiz baskısı orta' }
            return 'Faiz baskısı yüksek'
        }
        'DXY' {
            if ($null -eq $ChangePct) { return 'Veri Yok' }
            if ($ChangePct -le -0.2) { return 'Küresel dolar baskısı azalıyor' }
            if ($ChangePct -ge 0.2) { return 'Küresel dolar baskısı artıyor' }
            return 'Dolar baskısı nötr'
        }
        'VIX' {
            if ($null -eq $Value) { return 'Veri Yok' }
            if ($Value -lt 15) { return 'Küresel risk iştahı sakin' }
            if ($Value -lt 22) { return 'Küresel risk nötr' }
            return 'Küresel volatilite yüksek'
        }
        default {
            return 'İzle'
        }
    }
}

function Get-BistMarketStatus {
    param($Index)

    if ($null -eq $Index) {
        return 'BIST verisi yok'
    }

    $price = Get-ObjectPropertyValue -Object $Index -Name 'Price'
    $sma200 = Get-ObjectPropertyValue -Object $Index -Name 'SMA200'
    $month = Get-ObjectPropertyValue -Object $Index -Name 'PerfMonth'
    $macdHist = Get-ObjectPropertyValue -Object $Index -Name 'MacdHistogram'
    $score = 0
    if ($null -ne $price -and $null -ne $sma200 -and $sma200 -gt 0 -and $price -ge $sma200) { $score += 2 }
    if ($null -ne $month -and $month -ge 0) { $score += 1 }
    if ($null -ne $macdHist -and $macdHist -ge 0) { $score += 1 }

    if ($score -ge 4) { return 'Pozitif trend' }
    if ($score -ge 2) { return 'Nötr / toparlanma' }
    return 'Zayıf trend'
}

function Get-TcmbUsdTrySnapshot {
    param(
        [datetime]$AsOf = (Get-Date),
        [int]$TimeoutSec = 6
    )

    $current = Get-TcmbUsdTryRate -Date $AsOf -TimeoutSec $TimeoutSec
    if ($null -eq $current) {
        return [pscustomobject][ordered]@{
            Id = 'USDTRY_Tcmb'
            Name = 'USD/TRY TCMB'
            Value = $null
            Change = $null
            ChangePct = $null
            Unit = 'TL'
            Status = 'Veri Yok'
            Source = 'TCMB'
            Url = 'https://www.tcmb.gov.tr/kurlar/kurlar_tr.html'
            Note = 'TCMB kuru alınamadı.'
        }
    }

    $previous = Get-TcmbUsdTryRate -Date ([datetime]$current.RateDate).AddDays(-1) -TimeoutSec $TimeoutSec
    $change = if ($null -ne $previous -and $null -ne $previous.Rate) { [double]$current.Rate - [double]$previous.Rate } else { $null }
    $changePct = if ($null -ne $previous -and $null -ne $previous.Rate -and [double]$previous.Rate -ne 0) {
        (([double]$current.Rate / [double]$previous.Rate) - 1) * 100
    }
    else {
        $null
    }
    $status = if ($null -eq $changePct) {
        'Veri Yok'
    }
    elseif ([Math]::Abs($changePct) -lt 0.5) {
        'Kur sakin'
    }
    elseif ($changePct -ge 0.5) {
        'Kur yukarı baskı'
    }
    else {
        'TL lehine'
    }

    return [pscustomobject][ordered]@{
        Id = 'USDTRY_Tcmb'
        Name = 'USD/TRY TCMB'
        Value = [Math]::Round([double]$current.Rate, 4)
        Change = if ($null -ne $change) { [Math]::Round([double]$change, 4) } else { $null }
        ChangePct = if ($null -ne $changePct) { [Math]::Round([double]$changePct, 2) } else { $null }
        Unit = 'TL'
        Status = $status
        Source = 'TCMB'
        Url = 'https://www.tcmb.gov.tr/kurlar/kurlar_tr.html'
        Note = "Kur tarihi: $(([datetime]$current.RateDate).ToString('dd.MM.yyyy'))"
    }
}

function Get-MacroSnapshot {
    param(
        $IndexSnapshot = $null,
        [datetime]$AsOf = (Get-Date),
        [int]$TimeoutSec = 6
    )

    if ($null -eq $IndexSnapshot) {
        $IndexSnapshot = Get-BistIndexBenchmarks -TimeoutSec $TimeoutSec
    }

    $metrics = [System.Collections.Generic.List[object]]::new()
    $bist100 = Get-ObjectPropertyValue -Object $IndexSnapshot -Name 'Bist100'
    $xbank = Get-ObjectPropertyValue -Object $IndexSnapshot -Name 'XBank'
    $x30 = Get-ObjectPropertyValue -Object $IndexSnapshot -Name 'X30'

    foreach ($indexInfo in @(
            [pscustomobject]@{ Id = 'XU100'; Name = 'BIST100'; Value = $bist100 },
            [pscustomobject]@{ Id = 'XU030'; Name = 'BIST30'; Value = $x30 },
            [pscustomobject]@{ Id = 'XBANK'; Name = 'XBANK'; Value = $xbank }
        )) {
        $index = $indexInfo.Value
        [void]$metrics.Add([pscustomobject][ordered]@{
                Id = $indexInfo.Id
                Name = $indexInfo.Name
                Value = Get-ObjectPropertyValue -Object $index -Name 'Price'
                Change = $null
                ChangePct = Get-ObjectPropertyValue -Object $index -Name 'ChangePct'
                Unit = 'puan'
                Status = Get-BistMarketStatus -Index $index
                Source = 'TradingView'
                Url = "https://www.tradingview.com/symbols/BIST-$($indexInfo.Id)/"
                Note = ('Hafta {0}, 1A {1}, 3A {2}, 1Y {3}; SMA200 {4}; MACD hist {5}.' -f `
                    (Get-OptionalNumberText -Value (Get-ObjectPropertyValue -Object $index -Name 'PerfWeek') -Suffix '%'), `
                    (Get-OptionalNumberText -Value (Get-ObjectPropertyValue -Object $index -Name 'PerfMonth') -Suffix '%'), `
                    (Get-OptionalNumberText -Value (Get-ObjectPropertyValue -Object $index -Name 'Perf3Month') -Suffix '%'), `
                    (Get-OptionalNumberText -Value (Get-ObjectPropertyValue -Object $index -Name 'PerfYear') -Suffix '%'), `
                    (Get-OptionalNumberText -Value (Get-ObjectPropertyValue -Object $index -Name 'SMA200')), `
                    (Get-OptionalNumberText -Value (Get-ObjectPropertyValue -Object $index -Name 'MacdHistogram')))
            })
    }

    [void]$metrics.Add((Get-TcmbUsdTrySnapshot -AsOf $AsOf -TimeoutSec $TimeoutSec))
    foreach ($instrument in $script:MacroInvestingInstruments) {
        $snapshot = Get-InvestingInstrumentSnapshot `
            -Id $instrument.Id `
            -Name $instrument.Name `
            -Urls $instrument.Urls `
            -Unit $instrument.Unit `
            -LowerIsBetter $instrument.LowerIsBetter `
            -TimeoutSec $TimeoutSec
        $snapshot.Status = Get-MarketMetricStatus -Id $snapshot.Id -Value $snapshot.Value -ChangePct $snapshot.ChangePct
        [void]$metrics.Add($snapshot)
    }

    $supportive = @($metrics | Where-Object { $_.Status -match 'Pozitif|Destekleyici|sakin|lehine|düşük|azalıyor' }).Count
    $pressure = @($metrics | Where-Object { $_.Status -match 'baskı|yüksek|Zayıf|artıyor' }).Count
    $overall = if ($supportive -gt ($pressure + 1)) {
        'Makro zemin destekleyici'
    }
    elseif ($pressure -gt $supportive) {
        'Makro zemin temkinli'
    }
    else {
        'Makro zemin nötr / seçici'
    }

    return [pscustomobject][ordered]@{
        GeneratedAt = $AsOf.ToString('o')
        Status = $overall
        SupportiveCount = $supportive
        PressureCount = $pressure
        MeasurementNote = 'Makro görünüm; BIST trendi, banka relatif gücü, USD/TRY, Türkiye 5Y CDS, TR10Y faiz, DXY ve VIX ile izlenir. Düşen CDS/faiz/VIX/DXY ve BIST100ün SMA200 üstünde kalması risk iştahı lehine yorumlanır.'
        Metrics = $metrics.ToArray()
    }
}

function Add-QuarterlyFinancials {
    param(
        $Stock,
        [hashtable]$UsdTryRates,
        [int]$QuarterCount = 5
    )

    $latestPeriodEnd = Get-ObjectPropertyValue -Object $Stock -Name 'FiscalPeriodEnd'
    $netIncomeHistory = @(Get-ObjectPropertyValue -Object $Stock -Name 'NetIncomeHistory')
    $revenueHistory = @(Get-ObjectPropertyValue -Object $Stock -Name 'RevenueHistory')
    $assetsHistory = @(Get-ObjectPropertyValue -Object $Stock -Name 'TotalAssetsHistory')
    $debtHistory = @(Get-ObjectPropertyValue -Object $Stock -Name 'TotalDebtHistory')
    $freeCashFlowHistory = @(Get-ObjectPropertyValue -Object $Stock -Name 'FreeCashFlowHistory')
    $ebitdaHistory = @(Get-ObjectPropertyValue -Object $Stock -Name 'EbitdaHistory')
    $operatingIncomeTry = Get-ObjectPropertyValue -Object $Stock -Name 'OperatingIncomeTRY'

    $quarters = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $latestPeriodEnd) {
        for ($index = 0; $index -lt $QuarterCount; $index++) {
            $periodEnd = ([datetime]$latestPeriodEnd).AddMonths(-3 * $index)
            $rateKey = $periodEnd.Date.ToString('yyyy-MM-dd')
            $rateInfo = if ($UsdTryRates.ContainsKey($rateKey)) { $UsdTryRates[$rateKey] } else { $null }
            $usdTryRate = Get-ObjectPropertyValue -Object $rateInfo -Name 'Rate'
            $rateDate = Get-ObjectPropertyValue -Object $rateInfo -Name 'RateDate'
            $netIncomeTry = Get-ArrayValue -Values $netIncomeHistory -Index $index
            $revenueTry = Get-ArrayValue -Values $revenueHistory -Index $index
            $assetsTry = Get-ArrayValue -Values $assetsHistory -Index $index
            $debtTry = Get-ArrayValue -Values $debtHistory -Index $index
            $freeCashFlowTry = Get-ArrayValue -Values $freeCashFlowHistory -Index $index
            $ebitdaTry = Get-ArrayValue -Values $ebitdaHistory -Index $index
            $netIncomeUsd = Convert-TryToUsd -Value $netIncomeTry -Rate $usdTryRate
            $revenueUsd = Convert-TryToUsd -Value $revenueTry -Rate $usdTryRate
            $ebitdaUsd = Convert-TryToUsd -Value $ebitdaTry -Rate $usdTryRate

            [void]$quarters.Add([pscustomobject][ordered]@{
                    Period = Get-QuarterLabel -PeriodEnd $periodEnd
                    PeriodEnd = $periodEnd.Date
                    UsdTryRate = $usdTryRate
                    RateDate = $rateDate
                    NetIncomeTRY = $netIncomeTry
                    NetIncomeTRYBn = if ($null -ne $netIncomeTry) { $netIncomeTry / 1000000000 } else { $null }
                    NetIncomeUSD = $netIncomeUsd
                    NetIncomeUSDMn = if ($null -ne $netIncomeUsd) { $netIncomeUsd / 1000000 } else { $null }
                    RevenueTRY = $revenueTry
                    RevenueTRYBn = if ($null -ne $revenueTry) { $revenueTry / 1000000000 } else { $null }
                    RevenueUSD = $revenueUsd
                    RevenueUSDMn = if ($null -ne $revenueUsd) { $revenueUsd / 1000000 } else { $null }
                    EbitdaTRY = $ebitdaTry
                    EbitdaTRYBn = if ($null -ne $ebitdaTry) { $ebitdaTry / 1000000000 } else { $null }
                    EbitdaUSD = $ebitdaUsd
                    EbitdaUSDMn = if ($null -ne $ebitdaUsd) { $ebitdaUsd / 1000000 } else { $null }
                    TotalAssetsTRY = $assetsTry
                    TotalAssetsTRYBn = if ($null -ne $assetsTry) { $assetsTry / 1000000000 } else { $null }
                    TotalDebtTRY = $debtTry
                    TotalDebtTRYBn = if ($null -ne $debtTry) { $debtTry / 1000000000 } else { $null }
                    FreeCashFlowTRY = $freeCashFlowTry
                    FreeCashFlowTRYBn = if ($null -ne $freeCashFlowTry) { $freeCashFlowTry / 1000000000 } else { $null }
                })
        }
    }

    $latest = if ($quarters.Count -gt 0) { $quarters[0] } else { $null }
    $yearAgo = if ($quarters.Count -gt 4) { $quarters[4] } else { $null }
    $latestNetIncomeUsd = Get-ObjectPropertyValue -Object $latest -Name 'NetIncomeUSD'
    $yearAgoNetIncomeUsd = Get-ObjectPropertyValue -Object $yearAgo -Name 'NetIncomeUSD'
    $latestRevenueUsd = Get-ObjectPropertyValue -Object $latest -Name 'RevenueUSD'
    $yearAgoRevenueUsd = Get-ObjectPropertyValue -Object $yearAgo -Name 'RevenueUSD'
    $latestEbitdaUsd = Get-ObjectPropertyValue -Object $latest -Name 'EbitdaUSD'
    $yearAgoEbitdaUsd = Get-ObjectPropertyValue -Object $yearAgo -Name 'EbitdaUSD'
    $latestNetIncomeTry = Get-ObjectPropertyValue -Object $latest -Name 'NetIncomeTRY'
    $profitUsdYoY = Get-GrowthPercent -Current $latestNetIncomeUsd -Previous $yearAgoNetIncomeUsd
    $revenueUsdYoY = Get-GrowthPercent -Current $latestRevenueUsd -Previous $yearAgoRevenueUsd
    $ebitdaUsdYoY = Get-GrowthPercent -Current $latestEbitdaUsd -Previous $yearAgoEbitdaUsd
    $turnaround = $null -ne $latestNetIncomeUsd -and $latestNetIncomeUsd -gt 0 -and
        $null -ne $yearAgoNetIncomeUsd -and $yearAgoNetIncomeUsd -le 0
    $positiveQuarterCount = @($quarters | Where-Object { $null -ne $_.NetIncomeUSD -and $_.NetIncomeUSD -gt 0 }).Count
    $positiveEbitdaQuarterCount = @($quarters | Where-Object { $null -ne $_.EbitdaUSD -and $_.EbitdaUSD -gt 0 }).Count
    $hasFiveProfitValues = @($quarters | Where-Object { $null -ne $_.NetIncomeUSD }).Count -ge 5
    $hasComparableRevenue = $null -ne $latestRevenueUsd -and $null -ne $yearAgoRevenueUsd -and $yearAgoRevenueUsd -ne 0

    $ebitdaSequentialIncreaseCount = 0
    for ($index = 0; $index -lt ($quarters.Count - 1); $index++) {
        $currentEbitda = Get-ObjectPropertyValue -Object $quarters[$index] -Name 'EbitdaUSD'
        $previousEbitda = Get-ObjectPropertyValue -Object $quarters[$index + 1] -Name 'EbitdaUSD'
        if ($null -ne $currentEbitda -and $null -ne $previousEbitda -and [double]$currentEbitda -gt [double]$previousEbitda) {
            $ebitdaSequentialIncreaseCount++
        }
    }
    $ebitdaTrendLabel = if ($null -eq $latestEbitdaUsd) {
        'Veri Yok'
    }
    elseif ($latestEbitdaUsd -le 0) {
        'Negatif'
    }
    elseif ($null -ne $ebitdaUsdYoY -and $ebitdaUsdYoY -ge 20 -and $positiveEbitdaQuarterCount -ge 4) {
        'Güçlü'
    }
    elseif ($positiveEbitdaQuarterCount -ge 4 -and $ebitdaSequentialIncreaseCount -ge 2) {
        'Düzenli Artıyor'
    }
    elseif ($null -ne $ebitdaUsdYoY -and $ebitdaUsdYoY -ge 0) {
        'Artıyor'
    }
    else {
        'Zayıf'
    }

    $strongUsdEarnings = $hasFiveProfitValues -and
        $null -ne $latestNetIncomeUsd -and $latestNetIncomeUsd -gt 0 -and
        $positiveQuarterCount -ge 4 -and
        ($turnaround -or ($null -ne $profitUsdYoY -and $profitUsdYoY -ge 15)) -and
        $hasComparableRevenue -and $null -ne $revenueUsdYoY -and $revenueUsdYoY -ge 0

    $strengthReasons = [System.Collections.Generic.List[string]]::new()
    $latestProfitReason = if ($null -eq $latestNetIncomeUsd) {
        'son çeyrek USD kâr verisi yok'
    }
    elseif ($latestNetIncomeUsd -gt 0) {
        'son çeyrek USD net kârı pozitif'
    }
    else {
        'son çeyrek USD net kârı pozitif değil'
    }
    [void]$strengthReasons.Add($latestProfitReason)
    [void]$strengthReasons.Add("son 5 çeyreğin $positiveQuarterCount tanesi USD bazında kârlı; eşik en az 4")
    $profitGrowthReason = if ($turnaround) {
        'USD net kâr geçen yılın aynı çeyreğindeki zarardan kâra döndü'
    }
    elseif ($null -ne $profitUsdYoY) {
        "USD net kâr yıllık $([Math]::Round($profitUsdYoY, 1))%; güçlü eşik en az %15"
    }
    else {
        'USD net kâr yıllık büyümesi hesaplanamadı'
    }
    [void]$strengthReasons.Add($profitGrowthReason)
    $revenueGrowthReason = if ($null -ne $revenueUsdYoY) {
        "USD ciro yıllık $([Math]::Round($revenueUsdYoY, 1))%; güçlü eşik negatif olmaması"
    }
    else {
        'USD ciro yıllık büyümesi hesaplanamadı'
    }
    [void]$strengthReasons.Add($revenueGrowthReason)

    $otherProfitContributionTry = if ($null -ne $latestNetIncomeTry -and $null -ne $operatingIncomeTry) {
        [double]$latestNetIncomeTry - [double]$operatingIncomeTry
    }
    else {
        $null
    }
    $profitSourceComponents = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $operatingIncomeTry -and $null -ne $otherProfitContributionTry) {
        $rawComponents = @(
            [pscustomobject]@{
                Name = 'Faaliyet kârı'
                ValueTRY = [double]$operatingIncomeTry
            },
            [pscustomobject]@{
                Name = 'Faaliyet dışı / vergi / değerleme ve diğer'
                ValueTRY = [double]$otherProfitContributionTry
            }
        )
        $positiveContributionTotal = 0.0
        foreach ($component in $rawComponents) {
            if ($component.ValueTRY -gt 0) {
                $positiveContributionTotal += [double]$component.ValueTRY
            }
        }
        foreach ($component in $rawComponents) {
            [void]$profitSourceComponents.Add([pscustomobject][ordered]@{
                    Name = $component.Name
                    ValueTRY = $component.ValueTRY
                    ValueTRYBn = $component.ValueTRY / 1000000000
                    SharePct = if ($component.ValueTRY -gt 0 -and $positiveContributionTotal -gt 0) {
                        [Math]::Round(($component.ValueTRY / $positiveContributionTotal) * 100, 1)
                    }
                    else {
                        $null
                    }
                    IsNegativeAdjustment = $component.ValueTRY -lt 0
                })
        }
    }

    $profitSourceNote = if ($null -eq $latestNetIncomeTry -or $null -eq $operatingIncomeTry) {
        'Kâr kaynağı grafiği için faaliyet kârı veya net kâr verisi yok.'
    }
    elseif ($latestNetIncomeTry -le 0) {
        'Son çeyrek net zarar olduğu için yüzde dağılımı kâr payı olarak yorumlanmamalıdır. Faaliyet kârı ve kalan mutabakat kalemi tutar olarak gösterilir.'
    }
    else {
        'Kalan kalem, net kâr eksi faaliyet kârıdır; vergi, finansman, iştirak, değerleme ve diğer faaliyet dışı etkileri birlikte içerebilir. Ayrı değerleme kârı olarak yorumlanmamalıdır.'
    }

    $properties = [ordered]@{}
    foreach ($property in $Stock.PSObject.Properties) {
        if ($property.Name -notin @(
                'QuarterlyFinancials', 'LatestQuarter', 'LatestNetIncomeTRYBn',
                'LatestNetIncomeUSDMn', 'NetIncomeUsdYoYPct', 'RevenueUsdYoYPct',
                'LatestEbitdaTRYBn', 'LatestEbitdaUSDMn', 'EbitdaUsdYoYPct',
                'PositiveQuarterCount', 'PositiveEbitdaQuarterCount', 'EbitdaSequentialIncreaseCount',
                'EbitdaTrendLabel', 'StrongUsdEarnings', 'StrongUsdEarningsLabel',
                'UsdEarningsReason', 'OperatingIncomeTRYBn', 'OtherProfitContributionTRY',
                'OtherProfitContributionTRYBn', 'ProfitSourceComponents', 'ProfitSourceNote'
            )) {
            $properties[$property.Name] = $property.Value
        }
    }

    $properties.QuarterlyFinancials = $quarters.ToArray()
    $properties.LatestQuarter = Get-ObjectPropertyValue -Object $latest -Name 'Period'
    $properties.LatestNetIncomeTRYBn = Get-ObjectPropertyValue -Object $latest -Name 'NetIncomeTRYBn'
    $properties.LatestNetIncomeUSDMn = Get-ObjectPropertyValue -Object $latest -Name 'NetIncomeUSDMn'
    $properties.NetIncomeUsdYoYPct = if ($null -ne $profitUsdYoY) { [Math]::Round($profitUsdYoY, 1) } else { $null }
    $properties.RevenueUsdYoYPct = if ($null -ne $revenueUsdYoY) { [Math]::Round($revenueUsdYoY, 1) } else { $null }
    $properties.LatestEbitdaTRYBn = Get-ObjectPropertyValue -Object $latest -Name 'EbitdaTRYBn'
    $properties.LatestEbitdaUSDMn = Get-ObjectPropertyValue -Object $latest -Name 'EbitdaUSDMn'
    $properties.EbitdaUsdYoYPct = if ($null -ne $ebitdaUsdYoY) { [Math]::Round($ebitdaUsdYoY, 1) } else { $null }
    $properties.PositiveQuarterCount = $positiveQuarterCount
    $properties.PositiveEbitdaQuarterCount = $positiveEbitdaQuarterCount
    $properties.EbitdaSequentialIncreaseCount = $ebitdaSequentialIncreaseCount
    $properties.EbitdaTrendLabel = $ebitdaTrendLabel
    $properties.StrongUsdEarnings = $strongUsdEarnings
    $properties.StrongUsdEarningsLabel = if ($strongUsdEarnings) { 'Güçlü' } elseif ($hasFiveProfitValues) { 'Değil' } else { 'Veri Yok' }
    $properties.UsdEarningsReason = $strengthReasons -join '; '
    $properties.OperatingIncomeTRYBn = if ($null -ne $operatingIncomeTry) { $operatingIncomeTry / 1000000000 } else { $null }
    $properties.OtherProfitContributionTRY = $otherProfitContributionTry
    $properties.OtherProfitContributionTRYBn = if ($null -ne $otherProfitContributionTry) { $otherProfitContributionTry / 1000000000 } else { $null }
    $properties.ProfitSourceComponents = $profitSourceComponents.ToArray()
    $properties.ProfitSourceNote = $profitSourceNote

    return [pscustomobject]$properties
}

function Get-OptionalNumberText {
    param(
        $Value,
        [string]$Format = 'N2',
        [string]$Suffix = ''
    )

    if ($null -eq $Value) {
        return 'veri yok'
    }

    return ('{0:' + $Format + '}{1}') -f $Value, $Suffix
}

function Get-PEComponentScore {
    param($Value)

    if ($null -eq $Value) { return 45 }
    if ($Value -le 0) { return 15 }
    if ($Value -le 5) { return 78 }
    if ($Value -le 10) { return 95 }
    if ($Value -le 15) { return 88 }
    if ($Value -le 25) { return 70 }
    if ($Value -le 40) { return 45 }
    if ($Value -le 60) { return 25 }
    return 10
}

function Get-PBComponentScore {
    param($Value)

    if ($null -eq $Value) { return 45 }
    if ($Value -le 0) { return 20 }
    if ($Value -le 0.75) { return 90 }
    if ($Value -le 1.5) { return 85 }
    if ($Value -le 3) { return 65 }
    if ($Value -le 5) { return 45 }
    if ($Value -le 10) { return 25 }
    return 10
}

function Get-EvEbitdaComponentScore {
    param(
        $Value,
        [string]$Sector
    )

    if ($Sector -eq 'Finance') { return 50 }
    if ($null -eq $Value) { return 45 }
    if ($Value -le 0) { return 15 }
    if ($Value -le 4) { return 95 }
    if ($Value -le 6) { return 90 }
    if ($Value -le 8) { return 78 }
    if ($Value -le 10) { return 65 }
    if ($Value -le 15) { return 45 }
    if ($Value -le 25) { return 25 }
    return 10
}

function Get-ROEComponentScore {
    param($Value)

    if ($null -eq $Value) { return 45 }
    if ($Value -le 0) { return 15 }
    if ($Value -lt 5) { return 35 }
    if ($Value -lt 10) { return 55 }
    if ($Value -lt 20) { return 75 }
    if ($Value -lt 30) { return 90 }
    if ($Value -lt 50) { return 80 }
    return 65
}

function Get-DebtComponentScore {
    param(
        $Value,
        [string]$Sector
    )

    if ($Sector -eq 'Finance' -or $null -eq $Value) { return 50 }
    if ($Value -le 0) { return 80 }
    if ($Value -le 50) { return 85 }
    if ($Value -le 100) { return 70 }
    if ($Value -le 200) { return 50 }
    if ($Value -le 400) { return 30 }
    return 15
}

function Get-RSIComponentScore {
    param($Value)

    if ($null -eq $Value) { return 45 }
    if ($Value -lt 25) { return 30 }
    if ($Value -lt 35) { return 50 }
    if ($Value -lt 45) { return 65 }
    if ($Value -le 65) { return 90 }
    if ($Value -le 75) { return 60 }
    return 30
}

function Get-PerformanceComponentScore {
    param(
        $Value,
        [double]$Multiplier
    )

    if ($null -eq $Value) { return 45 }
    return Limit-Value -Value (50 + ($Value * $Multiplier))
}

function Get-RelativeVolumeComponentScore {
    param($Value)

    if ($null -eq $Value) { return 45 }
    if ($Value -le 0) { return 25 }
    if ($Value -lt 0.5) { return 35 }
    if ($Value -lt 0.8) { return 50 }
    if ($Value -lt 1.2) { return 65 }
    if ($Value -lt 2) { return 80 }
    if ($Value -lt 4) { return 90 }
    return 75
}

function Get-VolumeConfirmationComponentScore {
    param($Value)

    if ($null -eq $Value) { return 45 }
    if ($Value -ge 1.5) { return 92 }
    if ($Value -ge 1.2) { return 75 }
    if ($Value -ge 1.0) { return 62 }
    if ($Value -ge 0.8) { return 45 }
    return 25
}

function Get-VolumeComponentScore {
    param($Value)

    if ($null -eq $Value) { return 40 }
    if ($Value -lt 100000) { return 20 }
    if ($Value -lt 250000) { return 35 }
    if ($Value -lt 1000000) { return 55 }
    if ($Value -lt 5000000) { return 75 }
    if ($Value -lt 20000000) { return 90 }
    return 100
}

function Get-MovingAverageComponentScore {
    param(
        $Price,
        $Average
    )

    if ($null -eq $Price -or $null -eq $Average -or $Average -le 0) { return 45 }
    if ($Price -ge $Average) { return 100 }
    if ($Price -ge ($Average * 0.9)) { return 55 }
    return 20
}

function Get-MacdComponentScore {
    param($Stock)

    $macd = Get-ObjectPropertyValue -Object $Stock -Name 'MacdLine'
    $signal = Get-ObjectPropertyValue -Object $Stock -Name 'MacdSignal'
    $histogram = Get-ObjectPropertyValue -Object $Stock -Name 'MacdHistogram'

    if ($null -eq $macd -or $null -eq $signal -or $null -eq $histogram) { return 45 }
    if ($macd -gt $signal -and $histogram -gt 0) { return 92 }
    if ($histogram -gt 0) { return 75 }
    if ($macd -gt $signal) { return 68 }
    if ($histogram -ge 0) { return 55 }
    return 28
}

function Get-EbitdaTrendComponentScore {
    param($Stock)

    $latestEbitda = Get-ObjectPropertyValue -Object $Stock -Name 'LatestEbitdaUSDMn'
    $positiveEbitdaCount = Get-ObjectPropertyValue -Object $Stock -Name 'PositiveEbitdaQuarterCount'
    $sequentialIncreaseCount = Get-ObjectPropertyValue -Object $Stock -Name 'EbitdaSequentialIncreaseCount'
    $ebitdaUsdYoY = Get-ObjectPropertyValue -Object $Stock -Name 'EbitdaUsdYoYPct'

    $score = 0.0
    $score += if ($null -eq $latestEbitda) { 12 } elseif ($latestEbitda -gt 0) { 25 } else { 0 }
    $score += if ($null -eq $positiveEbitdaCount) { 10 } else { [Math]::Min(20, [double]$positiveEbitdaCount * 4) }
    $score += if ($null -eq $sequentialIncreaseCount) {
        8
    }
    elseif ($sequentialIncreaseCount -ge 3) {
        20
    }
    elseif ($sequentialIncreaseCount -ge 2) {
        15
    }
    elseif ($sequentialIncreaseCount -ge 1) {
        9
    }
    else {
        3
    }

    if ($null -eq $ebitdaUsdYoY) {
        $score += 10
    }
    elseif ($ebitdaUsdYoY -ge 50) {
        $score += 35
    }
    elseif ($ebitdaUsdYoY -ge 20) {
        $score += 28
    }
    elseif ($ebitdaUsdYoY -ge 0) {
        $score += 20
    }
    elseif ($ebitdaUsdYoY -ge -15) {
        $score += 10
    }

    return Limit-Value -Value $score
}

function Get-SpreadComponentScore {
    param($Value)

    if ($null -eq $Value) { return 45 }
    if ($Value -ge 30) { return 90 }
    if ($Value -ge 10) { return 76 }
    if ($Value -ge 0) { return 62 }
    if ($Value -ge -10) { return 45 }
    return 25
}

function Get-SectorRotationComponentScore {
    param($Value)

    if ($null -eq $Value) { return 45 }
    if ($Value -ge 15) { return 90 }
    if ($Value -ge 5) { return 76 }
    if ($Value -ge 0) { return 62 }
    if ($Value -ge -10) { return 45 }
    return 25
}

function Get-MacroSectorComponentScore {
    param($Stock)

    $inflationScores = @(
        Get-SpreadComponentScore -Value (Get-ObjectPropertyValue -Object $Stock -Name 'StockVsInflation1YPct')
        Get-SpreadComponentScore -Value (Get-ObjectPropertyValue -Object $Stock -Name 'StockVsInflation3YPct')
        Get-SpreadComponentScore -Value (Get-ObjectPropertyValue -Object $Stock -Name 'StockVsInflation5YPct')
    )
    $bistScores = @(
        Get-SpreadComponentScore -Value (Get-ObjectPropertyValue -Object $Stock -Name 'StockVsBist1YPct')
        Get-SpreadComponentScore -Value (Get-ObjectPropertyValue -Object $Stock -Name 'StockVsBist3YPct')
        Get-SpreadComponentScore -Value (Get-ObjectPropertyValue -Object $Stock -Name 'StockVsBist5YPct')
    )
    $sectorRotationValues = @(
        Get-ObjectPropertyValue -Object $Stock -Name 'SectorVsBistDay'
        Get-ObjectPropertyValue -Object $Stock -Name 'SectorVsBistWeek'
        Get-ObjectPropertyValue -Object $Stock -Name 'SectorVsBistMonth'
        Get-ObjectPropertyValue -Object $Stock -Name 'SectorVsBist3Month'
        Get-ObjectPropertyValue -Object $Stock -Name 'SectorVsBistYear'
    )
    $sectorRotationScores = foreach ($rotationValue in $sectorRotationValues) {
        if ($null -ne $rotationValue) {
            Get-SectorRotationComponentScore -Value $rotationValue
        }
    }
    $sectorScore = if (@($sectorRotationScores).Count -gt 0) {
        ($sectorRotationScores | Measure-Object -Average).Average
    }
    else {
        Get-SectorRotationComponentScore -Value (Get-ObjectPropertyValue -Object $Stock -Name 'SectorVsBist3Month')
    }
    $growthScores = @(
        Get-SpreadComponentScore -Value (Get-ObjectPropertyValue -Object $Stock -Name 'RevenueVsSectorPct')
        Get-SpreadComponentScore -Value (Get-ObjectPropertyValue -Object $Stock -Name 'NetIncomeVsSectorPct')
        Get-SpreadComponentScore -Value (Get-ObjectPropertyValue -Object $Stock -Name 'EbitdaVsSectorPct')
    )

    $inflationScore = ($inflationScores | Measure-Object -Average).Average
    $bistScore = ($bistScores | Measure-Object -Average).Average
    $growthScore = ($growthScores | Measure-Object -Average).Average

    return Limit-Value -Value ((0.30 * $inflationScore) + (0.30 * $bistScore) + (0.25 * $sectorScore) + (0.15 * $growthScore))
}

function Test-RangeValue {
    param(
        $Value,
        [double]$Minimum,
        [double]$Maximum
    )

    return $null -ne $Value -and [double]$Value -ge $Minimum -and [double]$Value -le $Maximum
}

function Test-MacdBuySignal {
    param(
        $Line,
        $Signal,
        $Histogram
    )

    return $null -ne $Line -and $null -ne $Signal -and $null -ne $Histogram -and
        [double]$Line -gt [double]$Signal -and [double]$Histogram -gt 0
}

function Get-ConfirmationProfile {
    param(
        $Stock,
        [double]$TrendScore,
        [double]$ValueScore,
        [double]$QualityScore,
        [double]$EarningsScore,
        [double]$MomentumScore,
        [double]$LiquidityScore,
        [double]$MacroSectorScore
    )

    $checks = [ordered]@{
        MacroStrong = $MacroSectorScore -ge 65
        FundamentalStrong = $EarningsScore -ge 70 -and $QualityScore -ge 60
        ValueReasonable = $Stock.Sector -eq 'Finance' -or $null -eq (Get-ObjectPropertyValue -Object $Stock -Name 'EvEbitda') -or
            ([double](Get-ObjectPropertyValue -Object $Stock -Name 'EvEbitda') -gt 0 -and [double](Get-ObjectPropertyValue -Object $Stock -Name 'EvEbitda') -le 12)
        PriceAboveSma200 = $null -ne $Stock.Price -and $null -ne $Stock.SMA200 -and $Stock.SMA200 -gt 0 -and $Stock.Price -ge $Stock.SMA200
        DailyRsiHealthy = Test-RangeValue -Value $Stock.RSI -Minimum 40 -Maximum 65
        WeeklyRsiHealthy = Test-RangeValue -Value (Get-ObjectPropertyValue -Object $Stock -Name 'RSIWeekly') -Minimum 40 -Maximum 70
        MonthlyRsiHealthy = Test-RangeValue -Value (Get-ObjectPropertyValue -Object $Stock -Name 'RSIMonthly') -Minimum 40 -Maximum 75
        DailyMacdBuy = Test-MacdBuySignal `
            -Line (Get-ObjectPropertyValue -Object $Stock -Name 'MacdLine') `
            -Signal (Get-ObjectPropertyValue -Object $Stock -Name 'MacdSignal') `
            -Histogram (Get-ObjectPropertyValue -Object $Stock -Name 'MacdHistogram')
        WeeklyMacdBuy = Test-MacdBuySignal `
            -Line (Get-ObjectPropertyValue -Object $Stock -Name 'MacdLineWeekly') `
            -Signal (Get-ObjectPropertyValue -Object $Stock -Name 'MacdSignalWeekly') `
            -Histogram (Get-ObjectPropertyValue -Object $Stock -Name 'MacdHistogramWeekly')
        MonthlyMacdBuy = Test-MacdBuySignal `
            -Line (Get-ObjectPropertyValue -Object $Stock -Name 'MacdLineMonthly') `
            -Signal (Get-ObjectPropertyValue -Object $Stock -Name 'MacdSignalMonthly') `
            -Histogram (Get-ObjectPropertyValue -Object $Stock -Name 'MacdHistogramMonthly')
        VolumeConfirmed = $null -ne $Stock.RelativeVolume -and $Stock.RelativeVolume -ge 1.0
        VolumeStrong = $null -ne $Stock.RelativeVolume -and $Stock.RelativeVolume -ge 1.5
    }

    $technicalKeys = @('PriceAboveSma200', 'DailyRsiHealthy', 'WeeklyRsiHealthy', 'MonthlyRsiHealthy', 'DailyMacdBuy', 'WeeklyMacdBuy', 'MonthlyMacdBuy', 'VolumeConfirmed')
    $technicalPassCount = @($technicalKeys | Where-Object { [bool]$checks[$_] }).Count
    $criticalTechnical = $checks.PriceAboveSma200 -and $checks.DailyRsiHealthy -and $checks.DailyMacdBuy
    $allTechnical = $technicalPassCount -eq $technicalKeys.Count
    $confirmationScore = [Math]::Round((($technicalPassCount / [double]$technicalKeys.Count) * 55) +
        $(if ($checks.MacroStrong) { 15 } else { 0 }) +
        $(if ($checks.FundamentalStrong) { 20 } else { 0 }) +
        $(if ($checks.ValueReasonable) { 10 } else { 0 }), 1)

    $label = if ($checks.MacroStrong -and $checks.FundamentalStrong -and $checks.ValueReasonable -and $criticalTechnical -and $allTechnical) {
        'Tüm Teyitli Güçlü Aday'
    }
    elseif ($checks.MacroStrong -and $checks.FundamentalStrong -and $criticalTechnical -and $technicalPassCount -ge 6) {
        'Teknik Teyitli Güçlü İzle'
    }
    elseif ($checks.FundamentalStrong -and $technicalPassCount -ge 5) {
        'Temel İyi, Teknik İzle'
    }
    elseif ($checks.MacroStrong -and $technicalPassCount -ge 5) {
        'Sektör Güçlü, Teknik İzle'
    }
    else {
        'Teyit Bekle'
    }

    $entryNote = switch ($label) {
        'Tüm Teyitli Güçlü Aday' { 'Makro, temel ve teknik bacaklar birlikte destekli; kademeli giriş aday listesine alınabilir. Bu alım emri değildir; fiyat, stop ve pozisyon kararı ayrıca verilmelidir.' }
        'Teknik Teyitli Güçlü İzle' { 'Ana bacaklar destekli, fakat tüm teyitler eksiksiz değil; kademeli giriş için eksik teyitler ve hacim izlenmelidir.' }
        'Temel İyi, Teknik İzle' { 'Temel taraf güçlü; teknik tarafta eksikler olduğu için fiyat/hacim teyidi beklenmelidir.' }
        'Sektör Güçlü, Teknik İzle' { 'Sektör para akışı destekli; şirket temeli ve teknik teyitler birlikte tekrar kontrol edilmelidir.' }
        default { 'Karar ağacında eksik bacak var; izleme listesinde tutulup yeni teyit beklenmelidir.' }
    }

    $failed = @($checks.Keys | Where-Object { -not [bool]$checks[$_] })

    return [pscustomobject][ordered]@{
        Label = $label
        Score = $confirmationScore
        TechnicalPassCount = $technicalPassCount
        TechnicalCheckCount = $technicalKeys.Count
        AllTechnicalConfirmed = $allTechnical
        EntryNote = $entryNote
        FailedChecks = $failed -join ', '
        MacroStrong = $checks.MacroStrong
        FundamentalStrong = $checks.FundamentalStrong
        ValueReasonable = $checks.ValueReasonable
        PriceAboveSma200 = $checks.PriceAboveSma200
        DailyRsiHealthy = $checks.DailyRsiHealthy
        WeeklyRsiHealthy = $checks.WeeklyRsiHealthy
        MonthlyRsiHealthy = $checks.MonthlyRsiHealthy
        DailyMacdBuy = $checks.DailyMacdBuy
        WeeklyMacdBuy = $checks.WeeklyMacdBuy
        MonthlyMacdBuy = $checks.MonthlyMacdBuy
        VolumeConfirmed = $checks.VolumeConfirmed
        VolumeStrong = $checks.VolumeStrong
    }
}

function Get-EarningsComponentScore {
    param($Stock)

    $quarters = @(Get-ObjectPropertyValue -Object $Stock -Name 'QuarterlyFinancials' | Where-Object { $null -ne $_ })
    if ($quarters.Count -eq 0) {
        return 40
    }

    $latest = $quarters[0]
    $latestProfit = Get-ObjectPropertyValue -Object $latest -Name 'NetIncomeUSD'
    $latestFreeCashFlow = Get-ObjectPropertyValue -Object $latest -Name 'FreeCashFlowTRY'
    $positiveQuarterCount = Get-ObjectPropertyValue -Object $Stock -Name 'PositiveQuarterCount'
    $profitUsdYoY = Get-ObjectPropertyValue -Object $Stock -Name 'NetIncomeUsdYoYPct'
    $revenueUsdYoY = Get-ObjectPropertyValue -Object $Stock -Name 'RevenueUsdYoYPct'
    $yearAgoProfit = if ($quarters.Count -gt 4) {
        Get-ObjectPropertyValue -Object $quarters[4] -Name 'NetIncomeUSD'
    }
    else {
        $null
    }
    $turnaround = $null -ne $latestProfit -and $latestProfit -gt 0 -and
        $null -ne $yearAgoProfit -and $yearAgoProfit -le 0

    $score = 0.0
    $latestProfitScore = if ($null -eq $latestProfit) { 10 } elseif ($latestProfit -gt 0) { 25 } else { 0 }
    $profitContinuityScore = if ($null -eq $positiveQuarterCount) { 10 } else { [Math]::Min(25, [double]$positiveQuarterCount * 5) }
    $score += $latestProfitScore
    $score += $profitContinuityScore

    if ($turnaround) {
        $score += 25
    }
    elseif ($null -eq $profitUsdYoY) {
        $score += 10
    }
    elseif ($profitUsdYoY -ge 50) {
        $score += 25
    }
    elseif ($profitUsdYoY -ge 20) {
        $score += 22
    }
    elseif ($profitUsdYoY -ge 0) {
        $score += 16
    }
    elseif ($profitUsdYoY -ge -15) {
        $score += 8
    }

    if ($null -eq $revenueUsdYoY) {
        $score += 7
    }
    elseif ($revenueUsdYoY -ge 20) {
        $score += 15
    }
    elseif ($revenueUsdYoY -ge 5) {
        $score += 12
    }
    elseif ($revenueUsdYoY -ge 0) {
        $score += 8
    }

    $freeCashFlowScore = if ($null -eq $latestFreeCashFlow) { 5 } elseif ($latestFreeCashFlow -gt 0) { 10 } else { 0 }
    $score += $freeCashFlowScore
    $netIncomeScore = Limit-Value -Value $score
    $ebitdaScore = Get-EbitdaTrendComponentScore -Stock $Stock

    return Limit-Value -Value ((0.78 * $netIncomeScore) + (0.22 * $ebitdaScore))
}

function Get-BistRiskFlags {
    param($Stock)

    $flags = [System.Collections.Generic.List[string]]::new()

    if ($null -ne $Stock.MarketCap -and $Stock.MarketCap -lt 1000000000) {
        [void]$flags.Add('Piyasa değeri 1 milyar TL altında')
    }
    elseif ($null -ne $Stock.MarketCap -and $Stock.MarketCap -lt 3000000000) {
        [void]$flags.Add('Piyasa değeri görece düşük')
    }

    if ($null -ne $Stock.AverageVolume10D -and $Stock.AverageVolume10D -lt 100000) {
        [void]$flags.Add('Ortalama işlem hacmi düşük')
    }
    elseif ($null -ne $Stock.AverageVolume10D -and $Stock.AverageVolume10D -lt 250000) {
        [void]$flags.Add('Likidite sınırlı olabilir')
    }

    if ($null -ne $Stock.VolatilityD -and $Stock.VolatilityD -gt 7) {
        [void]$flags.Add('Günlük oynaklık çok yüksek')
    }
    elseif ($null -ne $Stock.VolatilityD -and $Stock.VolatilityD -gt 5) {
        [void]$flags.Add('Günlük oynaklık yüksek')
    }

    if ($null -ne $Stock.RSI -and $Stock.RSI -gt 80) {
        [void]$flags.Add('RSI aşırı alım bölgesinde')
    }
    elseif ($null -ne $Stock.RSI -and $Stock.RSI -lt 30) {
        [void]$flags.Add('RSI zayıf momentum gösteriyor')
    }

    if ($null -ne $Stock.Price -and $null -ne $Stock.SMA20 -and $Stock.SMA20 -gt 0 -and
        (($Stock.Price / $Stock.SMA20) - 1) -gt 0.25) {
        [void]$flags.Add('Fiyat 20 günlük ortalamadan çok uzak')
    }

    if ($null -ne $Stock.Price -and $null -ne $Stock.SMA200 -and $Stock.SMA200 -gt 0 -and $Stock.Price -lt $Stock.SMA200) {
        [void]$flags.Add('Fiyat 200 günlük ortalamanın altında')
    }

    $macdHistogram = Get-ObjectPropertyValue -Object $Stock -Name 'MacdHistogram'
    if ($null -ne $macdHistogram -and $macdHistogram -lt 0) {
        [void]$flags.Add('MACD henüz al teyidi vermiyor')
    }

    if ($null -eq $Stock.PE -and $null -eq $Stock.PB -and $null -eq $Stock.ROE) {
        [void]$flags.Add('Temel analiz verileri eksik')
    }
    elseif ($null -ne $Stock.PE -and $Stock.PE -le 0) {
        [void]$flags.Add('F/K pozitif değil')
    }

    $latestNetIncomeUsd = Get-ObjectPropertyValue -Object $Stock -Name 'LatestNetIncomeUSDMn'
    $positiveQuarterCount = Get-ObjectPropertyValue -Object $Stock -Name 'PositiveQuarterCount'
    $profitUsdYoY = Get-ObjectPropertyValue -Object $Stock -Name 'NetIncomeUsdYoYPct'

    if ($null -ne $latestNetIncomeUsd -and $latestNetIncomeUsd -le 0) {
        [void]$flags.Add('Son çeyrek USD bazında net kâr pozitif değil')
    }
    if ($null -ne $positiveQuarterCount -and $positiveQuarterCount -lt 3) {
        [void]$flags.Add('Son 5 çeyrekte kârlılık sürekliliği zayıf')
    }
    if ($null -ne $profitUsdYoY -and $profitUsdYoY -lt -30) {
        [void]$flags.Add('USD net kâr yıllık bazda sert geriledi')
    }

    $latestEbitdaUsd = Get-ObjectPropertyValue -Object $Stock -Name 'LatestEbitdaUSDMn'
    $ebitdaUsdYoY = Get-ObjectPropertyValue -Object $Stock -Name 'EbitdaUsdYoYPct'
    if ($null -ne $latestEbitdaUsd -and $latestEbitdaUsd -le 0) {
        [void]$flags.Add('Son çeyrek USD FAVÖK pozitif değil')
    }
    if ($null -ne $ebitdaUsdYoY -and $ebitdaUsdYoY -lt -20) {
        [void]$flags.Add('USD FAVÖK yıllık bazda geriledi')
    }

    $evEbitda = Get-ObjectPropertyValue -Object $Stock -Name 'EvEbitda'
    if ($Stock.Sector -ne 'Finance' -and $null -ne $evEbitda -and $evEbitda -gt 15) {
        [void]$flags.Add('FD/FAVÖK çarpanı yüksek')
    }

    $stockVsInflation1Y = Get-ObjectPropertyValue -Object $Stock -Name 'StockVsInflation1YPct'
    $stockVsBist1Y = Get-ObjectPropertyValue -Object $Stock -Name 'StockVsBist1YPct'
    if ($null -ne $stockVsInflation1Y -and $null -ne $stockVsBist1Y -and $stockVsInflation1Y -lt 0 -and $stockVsBist1Y -lt 0) {
        [void]$flags.Add('1 yılda hem enflasyonun hem BIST100ün altında')
    }

    return $flags.ToArray()
}

function Get-RiskPenalty {
    param($Stock)

    $penalty = 0.0

    if ($null -ne $Stock.VolatilityD) {
        if ($Stock.VolatilityD -gt 7) { $penalty += 12 }
        elseif ($Stock.VolatilityD -gt 5) { $penalty += 7 }
        elseif ($Stock.VolatilityD -gt 3.5) { $penalty += 3 }
    }

    if ($null -ne $Stock.MarketCap) {
        if ($Stock.MarketCap -lt 1000000000) { $penalty += 6 }
        elseif ($Stock.MarketCap -lt 3000000000) { $penalty += 3 }
    }

    if ($null -ne $Stock.AverageVolume10D) {
        if ($Stock.AverageVolume10D -lt 100000) { $penalty += 6 }
        elseif ($Stock.AverageVolume10D -lt 250000) { $penalty += 3 }
    }

    if ($null -ne $Stock.RSI -and $Stock.RSI -gt 80) { $penalty += 4 }
    if ($null -ne $Stock.RelativeVolume -and $Stock.RelativeVolume -lt 0.8) { $penalty += 2 }

    if ($null -ne $Stock.Price -and $null -ne $Stock.SMA20 -and $Stock.SMA20 -gt 0 -and
        (($Stock.Price / $Stock.SMA20) - 1) -gt 0.25) {
        $penalty += 4
    }
    if ($null -ne $Stock.Price -and $null -ne $Stock.SMA200 -and $Stock.SMA200 -gt 0 -and $Stock.Price -lt $Stock.SMA200) {
        $penalty += 5
    }
    $macdHistogram = Get-ObjectPropertyValue -Object $Stock -Name 'MacdHistogram'
    if ($null -ne $macdHistogram -and $macdHistogram -lt 0) { $penalty += 3 }

    $latestNetIncomeUsd = Get-ObjectPropertyValue -Object $Stock -Name 'LatestNetIncomeUSDMn'
    $positiveQuarterCount = Get-ObjectPropertyValue -Object $Stock -Name 'PositiveQuarterCount'
    $profitUsdYoY = Get-ObjectPropertyValue -Object $Stock -Name 'NetIncomeUsdYoYPct'
    $latestEbitdaUsd = Get-ObjectPropertyValue -Object $Stock -Name 'LatestEbitdaUSDMn'
    $ebitdaUsdYoY = Get-ObjectPropertyValue -Object $Stock -Name 'EbitdaUsdYoYPct'

    if ($null -ne $latestNetIncomeUsd -and $latestNetIncomeUsd -le 0) { $penalty += 5 }
    if ($null -ne $positiveQuarterCount -and $positiveQuarterCount -lt 3) { $penalty += 4 }
    if ($null -ne $profitUsdYoY -and $profitUsdYoY -lt -30) { $penalty += 4 }
    if ($null -ne $latestEbitdaUsd -and $latestEbitdaUsd -le 0) { $penalty += 4 }
    if ($null -ne $ebitdaUsdYoY -and $ebitdaUsdYoY -lt -20) { $penalty += 4 }
    $evEbitda = Get-ObjectPropertyValue -Object $Stock -Name 'EvEbitda'
    if ($Stock.Sector -ne 'Finance' -and $null -ne $evEbitda -and $evEbitda -gt 15) { $penalty += 5 }

    $stockVsInflation1Y = Get-ObjectPropertyValue -Object $Stock -Name 'StockVsInflation1YPct'
    $stockVsBist1Y = Get-ObjectPropertyValue -Object $Stock -Name 'StockVsBist1YPct'
    if ($null -ne $stockVsInflation1Y -and $null -ne $stockVsBist1Y -and $stockVsInflation1Y -lt 0 -and $stockVsBist1Y -lt 0) {
        $penalty += 4
    }

    return $penalty
}

function Get-StrategyWeights {
    param(
        [ValidateSet('Dengeli', 'Değer', 'Momentum', 'Kalite')]
        [string]$Strategy
    )

    switch ($Strategy) {
        'Değer' {
            return @{
                Trend = 0.06
                Value = 0.30
                Quality = 0.16
                Earnings = 0.18
                Momentum = 0.03
                Liquidity = 0.05
                MacroSector = 0.22
            }
        }
        'Momentum' {
            return @{
                Trend = 0.30
                Value = 0.03
                Quality = 0.05
                Earnings = 0.13
                Momentum = 0.22
                Liquidity = 0.07
                MacroSector = 0.20
            }
        }
        'Kalite' {
            return @{
                Trend = 0.11
                Value = 0.09
                Quality = 0.27
                Earnings = 0.24
                Momentum = 0.03
                Liquidity = 0.05
                MacroSector = 0.21
            }
        }
        default {
            return @{
                Trend = 0.18
                Value = 0.14
                Quality = 0.16
                Earnings = 0.20
                Momentum = 0.08
                Liquidity = 0.06
                MacroSector = 0.18
            }
        }
    }
}

function Get-SignalLabel {
    param([double]$Score)

    if ($Score -ge 75) { return 'Güçlü İzle' }
    if ($Score -ge 65) { return 'İzle' }
    if ($Score -ge 55) { return 'Nötr +' }
    if ($Score -ge 45) { return 'Nötr' }
    if ($Score -ge 35) { return 'Temkinli' }
    return 'Zayıf'
}

function Get-RiskLevel {
    param([string[]]$RiskFlags)

    if ($RiskFlags.Count -ge 3) { return 'Yüksek' }
    if ($RiskFlags.Count -ge 1) { return 'Orta' }
    return 'Düşük'
}

function Get-ScoreExplanation {
    param(
        $Stock,
        [double]$Score,
        [string]$Signal,
        [double]$TrendScore,
        [double]$ValueScore,
        [double]$QualityScore,
        [double]$EarningsScore,
        [double]$MomentumScore,
        [double]$LiquidityScore,
        [double]$MacroSectorScore,
        $ConfirmationProfile,
        [double]$RiskPenalty,
        [string[]]$RiskFlags,
        [string]$Strategy
    )

    $aboveCount = 0
    $averageCount = 0
    foreach ($average in @($Stock.SMA20, $Stock.SMA50, $Stock.SMA200)) {
        if ($null -ne $Stock.Price -and $null -ne $average) {
            $averageCount++
            if ($Stock.Price -ge $average) { $aboveCount++ }
        }
    }

    $weights = Get-StrategyWeights -Strategy $Strategy
    $formulaText = 'Ağırlıklı formül: Trend %{0} ({1} puan) + Değer %{2} ({3} puan) + Kalite %{4} ({5} puan) + Bilanço %{6} ({7} puan) + Momentum %{8} ({9} puan) + Likidite %{10} ({11} puan) + Makro/Sektör %{12} ({13} puan) - Risk indirimi {14}.' -f `
        ([Math]::Round($weights.Trend * 100)), `
        ([Math]::Round($TrendScore * $weights.Trend, 1)), `
        ([Math]::Round($weights.Value * 100)), `
        ([Math]::Round($ValueScore * $weights.Value, 1)), `
        ([Math]::Round($weights.Quality * 100)), `
        ([Math]::Round($QualityScore * $weights.Quality, 1)), `
        ([Math]::Round($weights.Earnings * 100)), `
        ([Math]::Round($EarningsScore * $weights.Earnings, 1)), `
        ([Math]::Round($weights.Momentum * 100)), `
        ([Math]::Round($MomentumScore * $weights.Momentum, 1)), `
        ([Math]::Round($weights.Liquidity * 100)), `
        ([Math]::Round($LiquidityScore * $weights.Liquidity, 1)), `
        ([Math]::Round($weights.MacroSector * 100)), `
        ([Math]::Round($MacroSectorScore * $weights.MacroSector, 1)), `
        ([Math]::Round($RiskPenalty, 1))

    $trendText = if ($averageCount -gt 0) {
        'Trend puanı {0}: TradingView teknik özeti {1}; fiyat izlenen {2} hareketli ortalamanın {3} tanesinin üzerinde. Teknik özet -1 ile +1 aralığından 0-100 puana çevrilir; fiyatın 20, 50 ve 200 günlük ortalamaların üzerinde olması orta ve uzun vadeli trend teyidi kabul edilir.' -f `
            ([Math]::Round($TrendScore, 1)), `
            (Get-OptionalNumberText -Value $Stock.Recommendation), `
            $averageCount, `
            $aboveCount
    }
    else {
        "Trend puanı $([Math]::Round($TrendScore, 1)): Hareketli ortalama verisi eksik olduğu için bileşen temkinli-nötr değerlendirilir."
    }

    $evEbitda = Get-ObjectPropertyValue -Object $Stock -Name 'EvEbitda'
    $evEbitdaNote = if ($Stock.Sector -eq 'Finance') {
        ' Finans şirketlerinde FD/FAVÖK faaliyet modeli nedeniyle ana değerleme filtresi olarak kullanılmaz ve nötr kabul edilir.'
    }
    else {
        ' Finans dışı hisselerde FD/FAVÖK < 6 güçlü değerleme filtresi, 6-10 makul bölge, 15 üzeri pahalı/riskli bölge olarak ele alınır.'
    }
    $valuationText = 'Değer puanı {0}: F/K {1}, PD/DD {2}, FD/FAVÖK {3}. F/K için pozitif 5-15 aralığı, PD/DD için yaklaşık 0,75-1,5 aralığı görece makul kabul edilir; negatif kâr ve çok yüksek çarpanlar puanı düşürür.{4} Bu sabit eşikler içsel değer hesabı değildir ve sektör farklarını tamamen açıklamaz.' -f `
        ([Math]::Round($ValueScore, 1)), `
        (Get-OptionalNumberText -Value $Stock.PE), `
        (Get-OptionalNumberText -Value $Stock.PB), `
        (Get-OptionalNumberText -Value $evEbitda), `
        $evEbitdaNote

    $qualitySectorNote = if ($Stock.Sector -eq 'Finance') {
        ' Finans şirketlerinde borç/özsermaye faaliyet modelinin parçası olduğu için bu oran cezalandırılmaz ve nötr kabul edilir.'
    }
    else {
        ' Finans dışı şirketlerde daha düşük borç/özsermaye, bilanço dayanıklılığı lehine değerlendirilir.'
    }
    $qualityText = 'Kalite puanı {0}: ROE {1}, borç/özsermaye {2}. ROE için yaklaşık %20-30 aralığı güçlü kabul edilir; aşırı yüksek ROE sürdürülebilirlik riski nedeniyle tam puan almaz.{3}' -f `
        ([Math]::Round($QualityScore, 1)), `
        (Get-OptionalNumberText -Value $Stock.ROE -Suffix '%'), `
        (Get-OptionalNumberText -Value $Stock.DebtToEquity -Suffix '%'), `
        $qualitySectorNote

    $quarters = @(Get-ObjectPropertyValue -Object $Stock -Name 'QuarterlyFinancials' | Where-Object { $null -ne $_ })
    $quarterSummary = if ($quarters.Count -gt 0) {
        @($quarters | ForEach-Object {
                '{0}: Net {1} / {2}; FAVÖK {3} / {4}' -f `
                    $_.Period, `
                    (Get-OptionalNumberText -Value $_.NetIncomeTRYBn -Suffix ' Mr TL'), `
                    (Get-OptionalNumberText -Value $_.NetIncomeUSDMn -Suffix ' Mn USD'), `
                    (Get-OptionalNumberText -Value (Get-ObjectPropertyValue -Object $_ -Name 'EbitdaTRYBn') -Suffix ' Mr TL'), `
                    (Get-OptionalNumberText -Value (Get-ObjectPropertyValue -Object $_ -Name 'EbitdaUSDMn') -Suffix ' Mn USD')
            }) -join '; '
    }
    else {
        'çeyreklik veri yok'
    }
    $strongUsdLabel = Get-ObjectPropertyValue -Object $Stock -Name 'StrongUsdEarningsLabel'
    $usdReason = Get-ObjectPropertyValue -Object $Stock -Name 'UsdEarningsReason'
    $ebitdaTrendLabel = Get-ObjectPropertyValue -Object $Stock -Name 'EbitdaTrendLabel'
    $earningsText = 'Bilanço puanı {0}: Son 5 çeyrek net kârı ve FAVÖK TL / USD olarak {1}. USD güçlü bilanço sonucu: {2}. FAVÖK trendi: {3}; USD FAVÖK yıllık {4}, son 5 çeyrekte pozitif FAVÖK dönemi {5}. Kurlar her çeyrek sonundaki veya önceki ilk iş günündeki TCMB USD döviz alış kurudur. USD yıllık karşılaştırma, TL enflasyonu ve kur etkisini kısmen azaltmak; aynı çeyrek karşılaştırması ise mevsimselliği azaltmak için kullanılır. Kriter ayrıntısı: {6}.' -f `
        ([Math]::Round($EarningsScore, 1)), `
        $quarterSummary, `
        $(if ([string]::IsNullOrWhiteSpace([string]$strongUsdLabel)) { 'veri yok' } else { $strongUsdLabel }), `
        $(if ([string]::IsNullOrWhiteSpace([string]$ebitdaTrendLabel)) { 'veri yok' } else { $ebitdaTrendLabel }), `
        (Get-OptionalNumberText -Value (Get-ObjectPropertyValue -Object $Stock -Name 'EbitdaUsdYoYPct') -Suffix '%'), `
        $(if ($null -eq (Get-ObjectPropertyValue -Object $Stock -Name 'PositiveEbitdaQuarterCount')) { 'veri yok' } else { Get-ObjectPropertyValue -Object $Stock -Name 'PositiveEbitdaQuarterCount' }), `
        $(if ([string]::IsNullOrWhiteSpace([string]$usdReason)) { 'hesaplanamadı' } else { $usdReason })

    $operatingIncomeTryBn = Get-ObjectPropertyValue -Object $Stock -Name 'OperatingIncomeTRYBn'
    $otherProfitContributionTryBn = Get-ObjectPropertyValue -Object $Stock -Name 'OtherProfitContributionTRYBn'
    $profitSourceNote = Get-ObjectPropertyValue -Object $Stock -Name 'ProfitSourceNote'
    $profitSourceText = 'Son çeyrek kâr kaynağı mutabakatı: faaliyet kârı {0}; faaliyet dışı / vergi / değerleme ve diğer etkiler {1}. {2}' -f `
        (Get-OptionalNumberText -Value $operatingIncomeTryBn -Suffix ' Mr TL'), `
        (Get-OptionalNumberText -Value $otherProfitContributionTryBn -Suffix ' Mr TL'), `
        $(if ([string]::IsNullOrWhiteSpace([string]$profitSourceNote)) { 'Ayrıntılı mutabakat verisi yok.' } else { $profitSourceNote })

    $macdLine = Get-ObjectPropertyValue -Object $Stock -Name 'MacdLine'
    $macdSignal = Get-ObjectPropertyValue -Object $Stock -Name 'MacdSignal'
    $macdHistogram = Get-ObjectPropertyValue -Object $Stock -Name 'MacdHistogram'
    $macdText = if ($null -ne $macdLine -and $null -ne $macdSignal -and $null -ne $macdHistogram) {
        'MACD {0} / sinyal {1} / histogram {2}' -f `
            (Get-OptionalNumberText -Value $macdLine), `
            (Get-OptionalNumberText -Value $macdSignal), `
            (Get-OptionalNumberText -Value $macdHistogram)
    }
    else {
        'MACD veri yok'
    }
    $sma200Text = if ($null -ne $Stock.Price -and $null -ne $Stock.SMA200 -and $Stock.SMA200 -gt 0) {
        if ($Stock.Price -ge $Stock.SMA200) { 'fiyat 200 günlük ortalama üzerinde' } else { 'fiyat 200 günlük ortalama altında' }
    }
    else {
        '200 günlük ortalama veri yok'
    }
    $momentumText = 'Momentum puanı {0}: RSI {1}, haftalık performans {2}, aylık performans {3}, {4}, {5}, göreli hacim {6}. Teknik filtre rasyoneli: trend aşağıdaysa uğraşmamak için 200 günlük ortalama, al teyidi için MACD, aşırı kovalamamak için RSI 40-60 bandı, talep teyidi için hacim kullanılır. TradingView tarayıcı 20 günlük hacim ortalamasını döndürmediği için göreli hacimde 10 günlük proxy kullanılır; 1,5x ve üzeri güçlü teyit sayılır.' -f `
        ([Math]::Round($MomentumScore, 1)), `
        (Get-OptionalNumberText -Value $Stock.RSI), `
        (Get-OptionalNumberText -Value $Stock.PerfWeek -Suffix '%'), `
        (Get-OptionalNumberText -Value $Stock.PerfMonth -Suffix '%'), `
        $macdText, `
        $sma200Text, `
        (Get-OptionalNumberText -Value $Stock.RelativeVolume -Suffix 'x')

    $liquidityText = 'Likidite puanı {0}: Göreceli hacim {1}, 10 günlük ortalama hacim {2}. Yüksek ve sürdürülebilir hacim, fiyat kayması ve manipülasyon riskini azaltma eğilimindedir; aşırı göreceli hacim tek başına olumlu sayılmaz.' -f `
        ([Math]::Round($LiquidityScore, 1)), `
        (Get-OptionalNumberText -Value $Stock.RelativeVolume -Suffix 'x'), `
        (Get-OptionalNumberText -Value $Stock.AverageVolume10D -Format 'N0')

    $stockVsInflation1Y = Get-ObjectPropertyValue -Object $Stock -Name 'StockVsInflation1YPct'
    $stockVsInflation3Y = Get-ObjectPropertyValue -Object $Stock -Name 'StockVsInflation3YPct'
    $stockVsInflation5Y = Get-ObjectPropertyValue -Object $Stock -Name 'StockVsInflation5YPct'
    $stockVsBist1Y = Get-ObjectPropertyValue -Object $Stock -Name 'StockVsBist1YPct'
    $stockVsBist3Y = Get-ObjectPropertyValue -Object $Stock -Name 'StockVsBist3YPct'
    $stockVsBist5Y = Get-ObjectPropertyValue -Object $Stock -Name 'StockVsBist5YPct'
    $bist100PerfYear = Get-ObjectPropertyValue -Object $Stock -Name 'Bist100PerfYear'
    $bist100Perf3Year = Get-ObjectPropertyValue -Object $Stock -Name 'Bist100Perf3Year'
    $bist100Perf5Year = Get-ObjectPropertyValue -Object $Stock -Name 'Bist100Perf5Year'
    $inflationBenchmarkAsOf = Get-ObjectPropertyValue -Object $Stock -Name 'InflationBenchmarkAsOf'
    $inflation1Y = Get-ObjectPropertyValue -Object $Stock -Name 'Inflation1YPct'
    $inflation3Y = Get-ObjectPropertyValue -Object $Stock -Name 'Inflation3YPct'
    $inflation5Y = Get-ObjectPropertyValue -Object $Stock -Name 'Inflation5YPct'
    $sectorRotationLabel = Get-ObjectPropertyValue -Object $Stock -Name 'SectorRotationLabel'
    $sectorWatchIndex = Get-ObjectPropertyValue -Object $Stock -Name 'SectorWatchIndex'
    $sectorBenchmarkSource = Get-ObjectPropertyValue -Object $Stock -Name 'SectorBenchmarkSource'
    $sectorIndexPerf3Month = Get-ObjectPropertyValue -Object $Stock -Name 'SectorIndexPerf3Month'
    $bist100Perf3Month = Get-ObjectPropertyValue -Object $Stock -Name 'Bist100Perf3Month'
    $sectorVsBist3Month = Get-ObjectPropertyValue -Object $Stock -Name 'SectorVsBist3Month'
    $revenueVsSector = Get-ObjectPropertyValue -Object $Stock -Name 'RevenueVsSectorPct'
    $netIncomeVsSector = Get-ObjectPropertyValue -Object $Stock -Name 'NetIncomeVsSectorPct'
    $ebitdaVsSector = Get-ObjectPropertyValue -Object $Stock -Name 'EbitdaVsSectorPct'
    $macroText = 'Makro/Sektör puanı {0}: Karar ağacı makro uygun -> sektör güçlü -> bilanço güçlü -> teknik teyit -> kademeli giriş şeklinde okunur. Hisse 1Y/3Y/5Y performansı enflasyona göre {1} / {2} / {3}; BIST100e göre {4} / {5} / {6}. BIST100 1Y/3Y/5Y {7} / {8} / {9}; enflasyon eşiği {10} dönemi için {11} / {12} / {13}. Sektör rotasyonu: {14}, izlenen endeks/proxy {15}, 3 ay sektör {16}, BIST100 3 ay {17}, fark {18}. Büyüme sektöre göre: ciro {19}, net kâr {20}, FAVÖK {21}. CDS, yabancı takas, faiz ve DXY haftalık makro kontrol listesinde izlenir; güvenilir otomatik seri bağlı olmadığı için bu sürümde hisse puanına sayısal olarak dahil edilmez.' -f `
        ([Math]::Round($MacroSectorScore, 1)), `
        (Get-OptionalNumberText -Value $stockVsInflation1Y -Suffix ' puan'), `
        (Get-OptionalNumberText -Value $stockVsInflation3Y -Suffix ' puan'), `
        (Get-OptionalNumberText -Value $stockVsInflation5Y -Suffix ' puan'), `
        (Get-OptionalNumberText -Value $stockVsBist1Y -Suffix ' puan'), `
        (Get-OptionalNumberText -Value $stockVsBist3Y -Suffix ' puan'), `
        (Get-OptionalNumberText -Value $stockVsBist5Y -Suffix ' puan'), `
        (Get-OptionalNumberText -Value $bist100PerfYear -Suffix '%'), `
        (Get-OptionalNumberText -Value $bist100Perf3Year -Suffix '%'), `
        (Get-OptionalNumberText -Value $bist100Perf5Year -Suffix '%'), `
        $(if ([string]::IsNullOrWhiteSpace([string]$inflationBenchmarkAsOf)) { 'veri yok' } else { $inflationBenchmarkAsOf }), `
        (Get-OptionalNumberText -Value $inflation1Y -Suffix '%'), `
        (Get-OptionalNumberText -Value $inflation3Y -Suffix '%'), `
        (Get-OptionalNumberText -Value $inflation5Y -Suffix '%'), `
        $(if ([string]::IsNullOrWhiteSpace([string]$sectorRotationLabel)) { 'veri yok' } else { $sectorRotationLabel }), `
        $(if ([string]::IsNullOrWhiteSpace([string]$sectorWatchIndex)) { 'sektör proxy' } else { "$sectorWatchIndex / $sectorBenchmarkSource" }), `
        (Get-OptionalNumberText -Value $sectorIndexPerf3Month -Suffix '%'), `
        (Get-OptionalNumberText -Value $bist100Perf3Month -Suffix '%'), `
        (Get-OptionalNumberText -Value $sectorVsBist3Month -Suffix ' puan'), `
        (Get-OptionalNumberText -Value $revenueVsSector -Suffix ' puan'), `
        (Get-OptionalNumberText -Value $netIncomeVsSector -Suffix ' puan'), `
        (Get-OptionalNumberText -Value $ebitdaVsSector -Suffix ' puan')

    $riskText = if ($RiskFlags.Count -gt 0) {
        'Risk indirimi: ' + ($RiskFlags -join '; ') + ". Toplam indirim $([Math]::Round($RiskPenalty, 1)) puan."
    }
    else {
        'Risk indirimi: Belirgin otomatik risk bayrağı oluşmadı.'
    }

    return @(
        "$Signal | $Strategy stratejisi puanı: $([Math]::Round($Score, 1)) / 100 | Teyit etiketi: $($ConfirmationProfile.Label)",
        '',
        "Teyit notu: $($ConfirmationProfile.EntryNote) Teknik teyit $($ConfirmationProfile.TechnicalPassCount)/$($ConfirmationProfile.TechnicalCheckCount). Eksik teyitler: $(if ([string]::IsNullOrWhiteSpace([string]$ConfirmationProfile.FailedChecks)) { 'yok' } else { $ConfirmationProfile.FailedChecks }).",
        '',
        $formulaText,
        '',
        $trendText,
        '',
        $valuationText,
        '',
        $qualityText,
        '',
        $earningsText,
        '',
        $profitSourceText,
        '',
        $momentumText,
        '',
        $liquidityText,
        '',
        $macroText,
        '',
        $riskText,
        '',
        "Veri notu: Piyasa ve finansal veriler TradingView tarayıcısından, USD/TRY dönüşümleri TCMB kur arşivinden alınır. Yeni bilanço sağlayıcıya düştüğünde bir sonraki otomatik taramada içeri alınır. $(Get-ObjectPropertyValue -Object $Stock -Name 'MacroDataNote') KAP finansal raporu ve dipnotları işlem öncesinde mutlaka kontrol edilmelidir.",
        '',
        'Bu sonuç yalnızca sayısal tarama çıktısıdır; yatırım tavsiyesi veya alım-satım emri değildir.'
    ) -join [Environment]::NewLine
}

function ConvertFrom-TradingViewItem {
    param($Item)

    $values = @($Item.d)
    $mapped = New-Object object[] $script:TradingViewColumns.Count
    for ($index = 0; $index -lt $script:TradingViewColumns.Count; $index++) {
        if ($index -lt $values.Count) {
            $mapped[$index] = $values[$index]
        }
    }

    $marketCap = ConvertTo-DoubleOrNull $mapped[5]
    $sector = [string]$mapped[18]

    return [pscustomobject][ordered]@{
        Symbol = [string]$mapped[0]
        Company = [string]$mapped[1]
        TradingViewSymbol = [string]$Item.s
        Price = ConvertTo-DoubleOrNull $mapped[2]
        ChangePct = ConvertTo-DoubleOrNull $mapped[3]
        Volume = ConvertTo-DoubleOrNull $mapped[4]
        MarketCap = $marketCap
        MarketCapBn = if ($null -ne $marketCap) { $marketCap / 1000000000 } else { $null }
        PE = ConvertTo-DoubleOrNull $mapped[6]
        PB = ConvertTo-DoubleOrNull $mapped[7]
        ROE = ConvertTo-DoubleOrNull $mapped[8]
        DebtToEquity = ConvertTo-DoubleOrNull $mapped[9]
        DividendYield = ConvertTo-DoubleOrNull $mapped[10]
        Recommendation = ConvertTo-DoubleOrNull $mapped[11]
        RSI = ConvertTo-DoubleOrNull $mapped[12]
        SMA20 = ConvertTo-DoubleOrNull $mapped[13]
        SMA50 = ConvertTo-DoubleOrNull $mapped[14]
        SMA200 = ConvertTo-DoubleOrNull $mapped[15]
        RelativeVolume = ConvertTo-DoubleOrNull $mapped[16]
        VolatilityD = ConvertTo-DoubleOrNull $mapped[17]
        Sector = $sector
        SectorTR = Get-TurkishSectorName -Sector $sector
        Industry = [string]$mapped[19]
        PerfWeek = ConvertTo-DoubleOrNull $mapped[20]
        PerfMonth = ConvertTo-DoubleOrNull $mapped[21]
        Perf3Month = ConvertTo-DoubleOrNull $mapped[22]
        Perf6Month = ConvertTo-DoubleOrNull $mapped[23]
        PerfYear = ConvertTo-DoubleOrNull $mapped[24]
        AverageVolume10D = ConvertTo-DoubleOrNull $mapped[25]
        FinancialCurrency = [string]$mapped[26]
        FiscalPeriodEnd = ConvertFrom-UnixSecondsOrNull $mapped[27]
        LatestReportDate = ConvertFrom-UnixSecondsOrNull $mapped[28]
        NextEarningsDate = ConvertFrom-UnixSecondsOrNull $mapped[29]
        NetIncomeHistory = @(ConvertTo-DoubleArray $mapped[30])
        RevenueHistory = @(ConvertTo-DoubleArray $mapped[31])
        TotalAssetsHistory = @(ConvertTo-DoubleArray $mapped[32])
        TotalDebtHistory = @(ConvertTo-DoubleArray $mapped[33])
        FreeCashFlowHistory = @(ConvertTo-DoubleArray $mapped[34])
        OperatingIncomeTRY = ConvertTo-DoubleOrNull $mapped[35]
        Perf3Year = ConvertTo-DoubleOrNull $mapped[36]
        Perf5Year = ConvertTo-DoubleOrNull $mapped[37]
        MacdLine = ConvertTo-DoubleOrNull $mapped[38]
        MacdSignal = ConvertTo-DoubleOrNull $mapped[39]
        MacdHistogram = ConvertTo-DoubleOrNull $mapped[40]
        RSIWeekly = ConvertTo-DoubleOrNull $mapped[41]
        RSIMonthly = ConvertTo-DoubleOrNull $mapped[42]
        MacdLineWeekly = ConvertTo-DoubleOrNull $mapped[43]
        MacdSignalWeekly = ConvertTo-DoubleOrNull $mapped[44]
        MacdHistogramWeekly = ConvertTo-DoubleOrNull $mapped[45]
        MacdLineMonthly = ConvertTo-DoubleOrNull $mapped[46]
        MacdSignalMonthly = ConvertTo-DoubleOrNull $mapped[47]
        MacdHistogramMonthly = ConvertTo-DoubleOrNull $mapped[48]
        EvEbitda = if ($null -ne (ConvertTo-DoubleOrNull $mapped[49])) { ConvertTo-DoubleOrNull $mapped[49] } else { ConvertTo-DoubleOrNull $mapped[50] }
        EbitdaTRY = ConvertTo-DoubleOrNull $mapped[51]
        EbitdaTRYBn = if ($null -ne (ConvertTo-DoubleOrNull $mapped[51])) { (ConvertTo-DoubleOrNull $mapped[51]) / 1000000000 } else { $null }
        EbitdaHistory = @(ConvertTo-DoubleArray $mapped[52])
        EbitdaTtmTRY = ConvertTo-DoubleOrNull $mapped[53]
        EbitdaTtmTRYBn = if ($null -ne (ConvertTo-DoubleOrNull $mapped[53])) { (ConvertTo-DoubleOrNull $mapped[53]) / 1000000000 } else { $null }
    }
}

function Invoke-BistStockScan {
    [CmdletBinding()]
    param(
        [int]$Limit = 10000,
        [int]$TimeoutSec = 30
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $payload = @{
        filter = @(
            @{ left = 'exchange'; operation = 'equal'; right = 'BIST' },
            @{ left = 'type'; operation = 'equal'; right = 'stock' }
        )
        options = @{ lang = 'tr' }
        markets = @('turkey')
        symbols = @{
            query = @{ types = @() }
            tickers = @()
        }
        columns = $script:TradingViewColumns
        sort = @{ sortBy = 'market_cap_basic'; sortOrder = 'desc' }
        range = @(0, $Limit)
    }

    $headers = @{
        'User-Agent' = 'BIST-Hisse-Tarayici/1.0'
        'Accept' = 'application/json'
    }

    try {
        $response = Invoke-RestMethod `
            -Method Post `
            -Uri $script:TradingViewScannerUrl `
            -ContentType 'application/json' `
            -Headers $headers `
            -Body ($payload | ConvertTo-Json -Depth 8 -Compress) `
            -TimeoutSec $TimeoutSec `
            -ErrorAction Stop
    }
    catch {
        throw "Canlı BIST verisi alınamadı: $($_.Exception.Message)"
    }

    if ($null -eq $response.data -or $response.data.Count -eq 0) {
        throw 'Canlı BIST sorgusu boş sonuç döndürdü.'
    }

    $stocks = @($response.data | ForEach-Object {
        $item = $_
        ConvertFrom-TradingViewItem -Item $item
    })

    $quarterEndDates = foreach ($stock in $stocks) {
        if ($null -ne $stock.FiscalPeriodEnd) {
            for ($index = 0; $index -lt 5; $index++) {
                $stock.FiscalPeriodEnd.AddMonths(-3 * $index).Date
            }
        }
    }

    $usdTryRates = Get-TcmbUsdTryRates -Dates @($quarterEndDates)
    $enrichedStocks = foreach ($stock in $stocks) {
        Add-QuarterlyFinancials -Stock $stock -UsdTryRates $usdTryRates
    }
    $indexSnapshot = Get-BistIndexBenchmarks -TimeoutSec $TimeoutSec
    $macroEnrichedStocks = Add-MacroSectorBenchmarks -Stocks @($enrichedStocks) -IndexSnapshot $indexSnapshot

    return @($macroEnrichedStocks)
}

function Get-BistScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Stock,

        [ValidateSet('Dengeli', 'Değer', 'Momentum', 'Kalite')]
        [string]$Strategy = 'Dengeli'
    )

    $recommendationScore = if ($null -ne $Stock.Recommendation) {
        Limit-Value -Value (($Stock.Recommendation + 1) * 50)
    }
    else {
        45
    }

    $movingAverageScores = @(
        Get-MovingAverageComponentScore -Price $Stock.Price -Average $Stock.SMA20
        Get-MovingAverageComponentScore -Price $Stock.Price -Average $Stock.SMA50
        Get-MovingAverageComponentScore -Price $Stock.Price -Average $Stock.SMA200
    )
    $movingAverageScore = ($movingAverageScores | Measure-Object -Average).Average
    $trendScore = (0.55 * $recommendationScore) + (0.45 * $movingAverageScore)

    $peScore = Get-PEComponentScore -Value $Stock.PE
    $pbScore = Get-PBComponentScore -Value $Stock.PB
    $evEbitda = Get-ObjectPropertyValue -Object $Stock -Name 'EvEbitda'
    $evEbitdaScore = Get-EvEbitdaComponentScore -Value $evEbitda -Sector $Stock.Sector
    $valueScore = if ($Stock.Sector -eq 'Finance') {
        (0.35 * $peScore) + (0.65 * $pbScore)
    }
    else {
        (0.45 * $peScore) + (0.25 * $pbScore) + (0.30 * $evEbitdaScore)
    }

    $roeScore = Get-ROEComponentScore -Value $Stock.ROE
    $debtScore = Get-DebtComponentScore -Value $Stock.DebtToEquity -Sector $Stock.Sector
    $qualityScore = (0.75 * $roeScore) + (0.25 * $debtScore)
    $earningsScore = Get-EarningsComponentScore -Stock $Stock

    $rsiScore = Get-RSIComponentScore -Value $Stock.RSI
    $weekScore = Get-PerformanceComponentScore -Value $Stock.PerfWeek -Multiplier 3
    $monthScore = Get-PerformanceComponentScore -Value $Stock.PerfMonth -Multiplier 2
    $macdScore = Get-MacdComponentScore -Stock $Stock
    $volumeConfirmationScore = Get-VolumeConfirmationComponentScore -Value $Stock.RelativeVolume
    $momentumScore = (0.35 * $rsiScore) + (0.25 * $monthScore) + (0.15 * $weekScore) + (0.15 * $macdScore) + (0.10 * $volumeConfirmationScore)

    $relativeVolumeScore = Get-RelativeVolumeComponentScore -Value $Stock.RelativeVolume
    $volumeScore = Get-VolumeComponentScore -Value $Stock.AverageVolume10D
    $liquidityScore = (0.55 * $relativeVolumeScore) + (0.45 * $volumeScore)
    $macroSectorScore = Get-MacroSectorComponentScore -Stock $Stock
    $confirmationProfile = Get-ConfirmationProfile `
        -Stock $Stock `
        -TrendScore $trendScore `
        -ValueScore $valueScore `
        -QualityScore $qualityScore `
        -EarningsScore $earningsScore `
        -MomentumScore $momentumScore `
        -LiquidityScore $liquidityScore `
        -MacroSectorScore $macroSectorScore

    $weights = Get-StrategyWeights -Strategy $Strategy
    $riskPenalty = Get-RiskPenalty -Stock $Stock
    $rawScore = `
        ($trendScore * $weights.Trend) + `
        ($valueScore * $weights.Value) + `
        ($qualityScore * $weights.Quality) + `
        ($earningsScore * $weights.Earnings) + `
        ($momentumScore * $weights.Momentum) + `
        ($liquidityScore * $weights.Liquidity) + `
        ($macroSectorScore * $weights.MacroSector)

    $score = [Math]::Round((Limit-Value -Value ($rawScore - $riskPenalty)), 1)
    $signal = Get-SignalLabel -Score $score
    $riskFlags = @(Get-BistRiskFlags -Stock $Stock)
    $riskLevel = Get-RiskLevel -RiskFlags $riskFlags
    $explanation = Get-ScoreExplanation `
        -Stock $Stock `
        -Score $score `
        -Signal $signal `
        -TrendScore $trendScore `
        -ValueScore $valueScore `
        -QualityScore $qualityScore `
        -EarningsScore $earningsScore `
        -MomentumScore $momentumScore `
        -LiquidityScore $liquidityScore `
        -MacroSectorScore $macroSectorScore `
        -ConfirmationProfile $confirmationProfile `
        -RiskPenalty $riskPenalty `
        -RiskFlags $riskFlags `
        -Strategy $Strategy

    $properties = [ordered]@{}
    foreach ($property in $Stock.PSObject.Properties) {
        if ($property.Name -notin @(
                'Score', 'Signal', 'RiskLevel', 'RiskFlags', 'Explanation',
                'TrendScore', 'ValueScore', 'QualityScore', 'EarningsScore', 'MomentumScore',
                'LiquidityScore', 'MacroSectorScore', 'ConfirmationLabel', 'ConfirmationScore',
                'TechnicalPassCount', 'TechnicalCheckCount', 'AllTechnicalConfirmed', 'EntryNote',
                'FailedConfirmations', 'RiskPenalty', 'Strategy'
            )) {
            $properties[$property.Name] = $property.Value
        }
    }

    $properties.Score = $score
    $properties.Signal = $signal
    $properties.RiskLevel = $riskLevel
    $properties.RiskFlags = $riskFlags -join '; '
    $properties.Explanation = $explanation
    $properties.TrendScore = [Math]::Round($trendScore, 1)
    $properties.ValueScore = [Math]::Round($valueScore, 1)
    $properties.QualityScore = [Math]::Round($qualityScore, 1)
    $properties.EarningsScore = [Math]::Round($earningsScore, 1)
    $properties.MomentumScore = [Math]::Round($momentumScore, 1)
    $properties.LiquidityScore = [Math]::Round($liquidityScore, 1)
    $properties.MacroSectorScore = [Math]::Round($macroSectorScore, 1)
    $properties.ConfirmationLabel = $confirmationProfile.Label
    $properties.ConfirmationScore = $confirmationProfile.Score
    $properties.TechnicalPassCount = $confirmationProfile.TechnicalPassCount
    $properties.TechnicalCheckCount = $confirmationProfile.TechnicalCheckCount
    $properties.AllTechnicalConfirmed = $confirmationProfile.AllTechnicalConfirmed
    $properties.EntryNote = $confirmationProfile.EntryNote
    $properties.FailedConfirmations = $confirmationProfile.FailedChecks
    $properties.RiskPenalty = [Math]::Round($riskPenalty, 1)
    $properties.Strategy = $Strategy

    return [pscustomobject]$properties
}

function Get-BistScores {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Stocks,

        [ValidateSet('Dengeli', 'Değer', 'Momentum', 'Kalite')]
        [string]$Strategy = 'Dengeli'
    )

    $scoredStocks = foreach ($stock in $Stocks) {
        Get-BistScore -Stock $stock -Strategy $Strategy
    }

    return @($scoredStocks)
}

function Get-YahooFinanceSymbol {
    param([string]$Symbol)

    if ([string]::IsNullOrWhiteSpace($Symbol)) {
        return $null
    }

    $clean = ($Symbol -replace '[^A-Za-z0-9]', '').ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return $null
    }

    return "$clean.IS"
}

function Get-YahooWeeklyCloseSeries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Symbol,

        [int]$TimeoutSec = 12
    )

    $ticker = Get-YahooFinanceSymbol -Symbol $Symbol
    if ([string]::IsNullOrWhiteSpace($ticker)) {
        return @()
    }

    $url = 'https://query1.finance.yahoo.com/v8/finance/chart/{0}?range=2y&interval=1wk' -f ([Uri]::EscapeDataString($ticker))
    $headers = @{
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        'Accept' = 'application/json'
    }

    try {
        $response = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec $TimeoutSec -ErrorAction Stop
    }
    catch {
        return @()
    }

    $chart = Get-ObjectPropertyValue -Object $response -Name 'chart'
    $results = @(Get-ObjectPropertyValue -Object $chart -Name 'result')
    if ($results.Count -eq 0 -or $null -eq $results[0]) {
        return @()
    }

    $indicators = Get-ObjectPropertyValue -Object $results[0] -Name 'indicators'
    $quotes = @(Get-ObjectPropertyValue -Object $indicators -Name 'quote')
    if ($quotes.Count -eq 0 -or $null -eq $quotes[0]) {
        return @()
    }

    $closeValues = @(Get-ObjectPropertyValue -Object $quotes[0] -Name 'close')
    $closes = foreach ($value in $closeValues) {
        $number = ConvertTo-DoubleOrNull $value
        if ($null -ne $number -and $number -gt 0) {
            [double]$number
        }
    }

    return @($closes)
}

function Get-EmaSeries {
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Values,

        [Parameter(Mandatory)]
        [int]$Period
    )

    if ($null -eq $Values) {
        return @()
    }

    $result = New-Object 'object[]' $Values.Count
    if ($Values.Count -eq 0 -or $Period -le 0) {
        return $result
    }

    $multiplier = 2.0 / ($Period + 1)
    $seed = [System.Collections.Generic.List[double]]::new()
    $ema = $null

    for ($index = 0; $index -lt $Values.Count; $index++) {
        $value = ConvertTo-DoubleOrNull $Values[$index]
        if ($null -eq $value) {
            continue
        }

        if ($null -eq $ema) {
            [void]$seed.Add([double]$value)
            if ($seed.Count -eq $Period) {
                $ema = ($seed | Measure-Object -Average).Average
                $result[$index] = $ema
            }
            continue
        }

        $ema = (([double]$value - [double]$ema) * $multiplier) + [double]$ema
        $result[$index] = $ema
    }

    return $result
}

function Get-MacdHistogramSeries {
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Closes
    )

    if ($null -eq $Closes) {
        return @()
    }

    $ema12 = Get-EmaSeries -Values $Closes -Period 12
    $ema26 = Get-EmaSeries -Values $Closes -Period 26
    $macd = New-Object 'object[]' $Closes.Count

    for ($index = 0; $index -lt $Closes.Count; $index++) {
        $ema12Value = if ($index -lt $ema12.Count) { $ema12[$index] } else { $null }
        $ema26Value = if ($index -lt $ema26.Count) { $ema26[$index] } else { $null }
        if ($null -ne $ema12Value -and $null -ne $ema26Value) {
            $macd[$index] = [double]$ema12Value - [double]$ema26Value
        }
    }

    $signal = Get-EmaSeries -Values $macd -Period 9
    $histogram = New-Object 'object[]' $Closes.Count
    for ($index = 0; $index -lt $Closes.Count; $index++) {
        $signalValue = if ($index -lt $signal.Count) { $signal[$index] } else { $null }
        if ($null -ne $macd[$index] -and $null -ne $signalValue) {
            $histogram[$index] = [double]$macd[$index] - [double]$signalValue
        }
    }

    return $histogram
}

function Get-WeeklyMacdHistogramProfile {
    param(
        [Parameter(Mandatory)]
        [object[]]$Closes
    )

    if ($Closes.Count -lt 40) {
        return $null
    }

    $histogram = Get-MacdHistogramSeries -Closes $Closes
    $validHistogram = @(
        foreach ($value in $histogram) {
            $number = ConvertTo-DoubleOrNull $value
            if ($null -ne $number) {
                [double]$number
            }
        }
    )

    if ($validHistogram.Count -lt 10) {
        return $null
    }

    $lastEight = @($validHistogram | Select-Object -Last 8)
    if ($lastEight.Count -lt 8) {
        return $null
    }

    $consecutiveRise = 0
    for ($index = $lastEight.Count - 1; $index -gt 0; $index--) {
        if ([double]$lastEight[$index] -gt [double]$lastEight[$index - 1]) {
            $consecutiveRise++
        }
        else {
            break
        }
    }

    $increaseCount = 0
    for ($index = 1; $index -lt $lastEight.Count; $index++) {
        if ([double]$lastEight[$index] -gt [double]$lastEight[$index - 1]) {
            $increaseCount++
        }
    }

    $last = [double]$lastEight[$lastEight.Count - 1]
    $previous = [double]$lastEight[$lastEight.Count - 2]

    $recentZeroCross = $false
    for ($index = [Math]::Max(1, $lastEight.Count - 3); $index -lt $lastEight.Count; $index++) {
        if ([double]$lastEight[$index - 1] -lt 0 -and [double]$lastEight[$index] -ge 0) {
            $recentZeroCross = $true
            break
        }
    }

    $zeroCross = $previous -lt 0 -and $last -ge 0
    $label = if ($zeroCross) {
        'Sıfır üstüne yeni dönüş'
    }
    elseif ($recentZeroCross -and $last -ge 0) {
        'Sıfır üstü taze ivme'
    }
    elseif ($last -lt 0 -and $consecutiveRise -ge 3) {
        'Negatiften toparlanma'
    }
    elseif ($last -ge 0 -and $consecutiveRise -ge 3) {
        'Pozitif ivme'
    }
    elseif ($increaseCount -ge 5) {
        'Dalgalı toparlanma'
    }
    else {
        'Zayıf ivme'
    }

    $seriesText = (@($lastEight | ForEach-Object { '{0:N2}' -f [double]$_ }) -join ' / ')

    return [pscustomobject][ordered]@{
        ConsecutiveRisingWeeks = $consecutiveRise
        IncreaseCountLast8 = $increaseCount
        LastHistogram = [Math]::Round($last, 4)
        PreviousHistogram = [Math]::Round($previous, 4)
        ZeroCrossSignal = [bool]$zeroCross
        RecentZeroCrossSignal = [bool]$recentZeroCross
        Last8HistogramText = $seriesText
        Label = $label
    }
}

function Test-InstantEntryFundamentalCandidate {
    param($Stock)

    $marketCap = Get-ObjectPropertyValue -Object $Stock -Name 'MarketCap'
    $averageVolume = Get-ObjectPropertyValue -Object $Stock -Name 'AverageVolume10D'
    $price = Get-ObjectPropertyValue -Object $Stock -Name 'Price'
    $riskLevel = [string](Get-ObjectPropertyValue -Object $Stock -Name 'RiskLevel')
    $sector = [string](Get-ObjectPropertyValue -Object $Stock -Name 'Sector')
    $sectorTR = [string](Get-ObjectPropertyValue -Object $Stock -Name 'SectorTR')
    $latestNetIncome = Get-ObjectPropertyValue -Object $Stock -Name 'LatestNetIncomeTRYBn'
    $positiveQuarterCount = Get-ObjectPropertyValue -Object $Stock -Name 'PositiveQuarterCount'
    $positiveEbitdaQuarterCount = Get-ObjectPropertyValue -Object $Stock -Name 'PositiveEbitdaQuarterCount'
    $earningsScore = Get-ObjectPropertyValue -Object $Stock -Name 'EarningsScore'
    $qualityScore = Get-ObjectPropertyValue -Object $Stock -Name 'QualityScore'
    $valueScore = Get-ObjectPropertyValue -Object $Stock -Name 'ValueScore'
    $macroScore = Get-ObjectPropertyValue -Object $Stock -Name 'MacroSectorScore'
    $roe = Get-ObjectPropertyValue -Object $Stock -Name 'ROE'
    $pe = Get-ObjectPropertyValue -Object $Stock -Name 'PE'
    $pb = Get-ObjectPropertyValue -Object $Stock -Name 'PB'
    $evEbitda = Get-ObjectPropertyValue -Object $Stock -Name 'EvEbitda'
    $latestEbitda = Get-ObjectPropertyValue -Object $Stock -Name 'LatestEbitdaUSDMn'

    if ($null -eq $price -or $price -le 0) { return $false }
    if ($null -eq $marketCap -or $marketCap -lt 3000000000) { return $false }
    if ($null -eq $averageVolume -or $averageVolume -lt 200000) { return $false }
    if ($riskLevel -eq 'Yüksek' -or $riskLevel -eq 'Yuksek') { return $false }
    if ([string]::IsNullOrWhiteSpace($sectorTR) -or $sectorTR -eq 'Sektör Verisi Yok' -or $sectorTR -eq 'Sektor Verisi Yok') { return $false }
    if ($null -eq $latestNetIncome -or $latestNetIncome -le 0) { return $false }
    if ($null -eq $positiveQuarterCount -or $positiveQuarterCount -lt 3) { return $false }
    if ($null -ne $positiveEbitdaQuarterCount -and $positiveEbitdaQuarterCount -lt 3) { return $false }
    if ($null -ne $latestEbitda -and $latestEbitda -le 0 -and $sector -ne 'Finance') { return $false }
    if ($null -ne $earningsScore -and $earningsScore -lt 58) { return $false }
    if ($null -ne $qualityScore -and $qualityScore -lt 45) { return $false }
    if ($null -ne $valueScore -and $valueScore -lt 42) { return $false }
    if ($null -ne $macroScore -and $macroScore -lt 35) { return $false }
    if ($null -ne $roe -and $roe -lt 7) { return $false }

    $valueOk = if ($sector -eq 'Finance') {
        ($null -eq $pb -or ($pb -gt 0 -and $pb -le 2.5)) -and
        ($null -eq $pe -or ($pe -gt 0 -and $pe -le 20))
    }
    else {
        ($null -eq $evEbitda -or ($evEbitda -gt 0 -and $evEbitda -le 12)) -and
        ($null -eq $pe -or ($pe -gt 0 -and $pe -le 35))
    }

    return [bool]$valueOk
}

function Get-InstantEntryRangeProfile {
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Closes
    )

    $values = @($Closes | ForEach-Object {
            $number = ConvertTo-DoubleOrNull $_
            if ($null -ne $number -and $number -gt 0) {
                [double]$number
            }
        })

    if ($values.Count -lt 52) {
        return $null
    }

    $window = @($values | Select-Object -Last 52)
    $last = [double]$window[$window.Count - 1]
    $low = [double](($window | Measure-Object -Minimum).Minimum)
    $high = [double](($window | Measure-Object -Maximum).Maximum)
    $average = [double](($window | Measure-Object -Average).Average)

    $position = if ($high -gt $low) {
        (($last - $low) / ($high - $low)) * 100.0
    }
    else {
        50.0
    }

    $bucket = if ($position -le 10) {
        '52H Range 0-10'
    }
    elseif ($position -le 20) {
        '52H Range 10-20'
    }
    elseif ($position -le 50) {
        '52H Range 20-50'
    }
    else {
        '52H Range 50+'
    }

    return [pscustomobject][ordered]@{
        PositionPct = [Math]::Round((Limit-Value -Value $position), 1)
        DistanceToLowPct = if ($low -gt 0) { [Math]::Round((($last / $low) - 1.0) * 100.0, 1) } else { $null }
        DistanceToSmaPct = if ($average -gt 0) { [Math]::Round((($last / $average) - 1.0) * 100.0, 1) } else { $null }
        Sma = [Math]::Round($average, 4)
        Low = [Math]::Round($low, 4)
        High = [Math]::Round($high, 4)
        Bucket = $bucket
    }
}

function Get-InstantEntryRangeScore {
    param($RangeProfile)

    if ($null -eq $RangeProfile) { return 0 }

    $position = Get-ObjectPropertyValue -Object $RangeProfile -Name 'PositionPct'
    if ($null -eq $position) { return 0 }

    if ($position -gt 10 -and $position -le 20) { return 8 }
    if ($position -gt 20 -and $position -le 50) { return 3 }
    if ($position -le 10) { return -6 }
    return 1
}

function Get-InstantEntryHistogramBacktestScore {
    param($HistogramProfile)

    if ($null -eq $HistogramProfile) { return 0 }

    $label = [string](Get-ObjectPropertyValue -Object $HistogramProfile -Name 'Label')
    $risingWeeks = Get-ObjectPropertyValue -Object $HistogramProfile -Name 'ConsecutiveRisingWeeks'
    $score = switch ($label) {
        'Pozitif ivme' { 10; break }
        'Sıfır üstüne yeni dönüş' { 8; break }
        'Sıfır üstü taze ivme' { 5; break }
        'Negatiften toparlanma' { 3; break }
        'Dalgalı toparlanma' { -1; break }
        'Zayıf ivme' { -5; break }
        default { 0 }
    }

    if ($null -ne $risingWeeks -and [double]$risingWeeks -ge 6) {
        $score += 2
    }

    return $score
}

function Get-InstantEntryMarketRegime {
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$BenchmarkCloses
    )

    $values = @($BenchmarkCloses | ForEach-Object {
            $number = ConvertTo-DoubleOrNull $_
            if ($null -ne $number -and $number -gt 0) {
                [double]$number
            }
        })

    if ($values.Count -lt 5) {
        return $null
    }

    $last = [double]$values[$values.Count - 1]
    $previous = [double]$values[$values.Count - 5]
    if ($previous -le 0) {
        return $null
    }

    $changePct = (($last / $previous) - 1.0) * 100.0
    return [pscustomobject][ordered]@{
        Label = $(if ($changePct -ge 0) { 'BIST yükseliyor' } else { 'BIST düşüyor' })
        ChangePct = [Math]::Round($changePct, 2)
    }
}

function Get-InstantEntryRegimeScore {
    param(
        $MarketRegime,
        $RangeProfile
    )

    if ($null -eq $MarketRegime -or $null -eq $RangeProfile) { return 0 }

    $label = [string](Get-ObjectPropertyValue -Object $MarketRegime -Name 'Label')
    $bucket = [string](Get-ObjectPropertyValue -Object $RangeProfile -Name 'Bucket')

    if ($label -eq 'BIST düşüyor' -and $bucket -eq '52H Range 10-20') { return 3 }
    if ($label -eq 'BIST yükseliyor' -and $bucket -eq '52H Range 0-10') { return -2 }
    return 0
}

function Get-InstantEntryRsiScore {
    param($Value)

    if ($null -eq $Value) { return 5 }
    if ($Value -ge 45 -and $Value -le 60) { return 8 }
    if ($Value -ge 40 -and $Value -lt 45) { return 7 }
    if ($Value -gt 60 -and $Value -le 65) { return 6 }
    if ($Value -ge 35 -and $Value -lt 40) { return 3 }
    if ($Value -gt 65 -and $Value -le 70) { return 1 }
    return 0
}

function Get-InstantEntryTechnicalScore {
    param(
        $Stock,
        $HistogramProfile
    )

    $score = 0.0
    $price = Get-ObjectPropertyValue -Object $Stock -Name 'Price'
    $sma20 = Get-ObjectPropertyValue -Object $Stock -Name 'SMA20'
    $sma50 = Get-ObjectPropertyValue -Object $Stock -Name 'SMA50'
    $sma200 = Get-ObjectPropertyValue -Object $Stock -Name 'SMA200'
    $macdLine = Get-ObjectPropertyValue -Object $Stock -Name 'MacdLine'
    $macdSignal = Get-ObjectPropertyValue -Object $Stock -Name 'MacdSignal'
    $macdHistogram = Get-ObjectPropertyValue -Object $Stock -Name 'MacdHistogram'
    $weeklyHistogram = Get-ObjectPropertyValue -Object $Stock -Name 'MacdHistogramWeekly'
    $relativeVolume = Get-ObjectPropertyValue -Object $Stock -Name 'RelativeVolume'

    if ($null -ne $price -and $null -ne $sma20 -and $sma20 -gt 0) {
        $distance = ([double]$price / [double]$sma20) - 1
        if ($distance -ge -0.02 -and $distance -le 0.12) { $score += 8 }
        elseif ($distance -gt 0 -and $distance -le 0.22) { $score += 5 }
        elseif ($distance -ge -0.06 -and $distance -lt -0.02) { $score += 3 }
    }
    if ($null -ne $price -and $null -ne $sma50 -and $sma50 -gt 0 -and $price -ge $sma50) { $score += 5 }
    if ($null -ne $price -and $null -ne $sma200 -and $sma200 -gt 0) {
        if ($price -ge $sma200) { $score += 4 }
        elseif ($HistogramProfile.LastHistogram -lt 0 -and $HistogramProfile.ConsecutiveRisingWeeks -ge 4) { $score += 2 }
    }
    if ($null -ne $macdHistogram -and $macdHistogram -ge 0) { $score += 6 }
    if ($null -ne $macdLine -and $null -ne $macdSignal -and $macdLine -gt $macdSignal) { $score += 4 }
    if ($null -ne $weeklyHistogram -and $weeklyHistogram -ge 0) { $score += 3 }
    if ($null -ne $relativeVolume) {
        if ($relativeVolume -ge 1.2) { $score += 5 }
        elseif ($relativeVolume -ge 0.8) { $score += 2 }
    }

    return $score
}

function Get-InstantEntryNumberText {
    param(
        $Value,
        [string]$Format = 'N1',
        [string]$Suffix = ''
    )

    if ($null -eq $Value) {
        return 'veri yok'
    }

    return ('{0:' + $Format + '}{1}') -f [double]$Value, $Suffix
}

function Test-InstantEntryOpportunityFilter {
    param($Opportunity)

    if ($null -eq $Opportunity) { return $false }

    $score = Get-ObjectPropertyValue -Object $Opportunity -Name 'EntryOpportunityScore'
    $rangeBucket = [string](Get-ObjectPropertyValue -Object $Opportunity -Name 'Range52Bucket')
    $label = [string](Get-ObjectPropertyValue -Object $Opportunity -Name 'WeeklyHistogramLabel')
    $zeroCross = [bool](Get-ObjectPropertyValue -Object $Opportunity -Name 'WeeklyHistogramZeroCross')

    if ($null -eq $score -or [double]$score -lt 85) { return $false }
    if ($rangeBucket -eq '52H Range 0-10') { return $false }

    $zeroCrossLabels = @(
        'Sıfır üstüne yeni dönüş',
        'Sifir ustune yeni donus'
    )

    if ($zeroCross -or $label -in $zeroCrossLabels) { return $true }
    if ($label -eq 'Pozitif ivme' -and $rangeBucket -eq '52H Range 20-50') { return $true }

    return $false
}

function New-InstantEntryOpportunity {
    param(
        $Stock,
        $HistogramProfile,
        $RangeProfile = $null,
        $MarketRegime = $null
    )

    $earningsScore = Get-ObjectPropertyValue -Object $Stock -Name 'EarningsScore'
    $qualityScore = Get-ObjectPropertyValue -Object $Stock -Name 'QualityScore'
    $valueScore = Get-ObjectPropertyValue -Object $Stock -Name 'ValueScore'
    $macroScore = Get-ObjectPropertyValue -Object $Stock -Name 'MacroSectorScore'
    $rsi = Get-ObjectPropertyValue -Object $Stock -Name 'RSI'
    $evEbitda = Get-ObjectPropertyValue -Object $Stock -Name 'EvEbitda'
    $pe = Get-ObjectPropertyValue -Object $Stock -Name 'PE'
    $pb = Get-ObjectPropertyValue -Object $Stock -Name 'PB'
    $relativeVolume = Get-ObjectPropertyValue -Object $Stock -Name 'RelativeVolume'
    $sectorRotationAverage = Get-ObjectPropertyValue -Object $Stock -Name 'SectorRotationAverage'

    $fundamentalAverage = Get-AverageNumber -Values @($earningsScore, $qualityScore, $valueScore)
    if ($null -eq $fundamentalAverage) { $fundamentalAverage = 50 }
    if ($null -eq $macroScore) { $macroScore = 45 }

    $zeroCross = [bool](Get-ObjectPropertyValue -Object $HistogramProfile -Name 'ZeroCrossSignal')
    $recentZeroCross = [bool](Get-ObjectPropertyValue -Object $HistogramProfile -Name 'RecentZeroCrossSignal')
    $histogramScore = [Math]::Min(
        34,
        ([double]$HistogramProfile.ConsecutiveRisingWeeks * 5.0) +
        ([double]$HistogramProfile.IncreaseCountLast8 * 1.5) +
        $(if ($HistogramProfile.LastHistogram -gt $HistogramProfile.PreviousHistogram) { 4 } else { 0 }) +
        $(if ($HistogramProfile.LastHistogram -ge 0) { 4 } else { 2 })
    )

    $entryScore = [Math]::Round((Limit-Value -Value (
                $histogramScore +
                (0.22 * [double]$fundamentalAverage) +
                (0.10 * [double]$macroScore) +
                (Get-InstantEntryRsiScore -Value $rsi) +
                (Get-InstantEntryRangeScore -RangeProfile $RangeProfile) +
                (Get-InstantEntryHistogramBacktestScore -HistogramProfile $HistogramProfile) +
                (Get-InstantEntryRegimeScore -MarketRegime $MarketRegime -RangeProfile $RangeProfile) +
                (Get-InstantEntryTechnicalScore -Stock $Stock -HistogramProfile $HistogramProfile)
            )), 1)

    $reasons = [System.Collections.Generic.List[string]]::new()
    [void]$reasons.Add(('Haftalık MACD histogramı son 8 haftada {0}/7 kez, son {1} hafta üst üste iyileşti; son {2}, önceki {3}.' -f `
                $HistogramProfile.IncreaseCountLast8, `
                $HistogramProfile.ConsecutiveRisingWeeks, `
                (Get-InstantEntryNumberText -Value $HistogramProfile.LastHistogram -Format 'N2'), `
                (Get-InstantEntryNumberText -Value $HistogramProfile.PreviousHistogram -Format 'N2')))
    if ($zeroCross) {
        [void]$reasons.Add('Histogram negatiften pozitife bu hafta geçti; erken dönüş sinyali en güçlü teknik gerekçe.')
    }
    elseif ($recentZeroCross) {
        [void]$reasons.Add('Histogram son 3 haftada sıfır üstüne geçti; taze pozitif ivme korunuyor.')
    }
    elseif ($HistogramProfile.LastHistogram -lt 0) {
        [void]$reasons.Add('Histogram hâlâ negatif ama yukarı eğim güçleniyor; dönüş teyidi izlenmeli.')
    }

    switch ([string]$HistogramProfile.Label) {
        'Pozitif ivme' {
            [void]$reasons.Add('Backtestte pozitif ivme etiketi en güçlü 1 aylık segmentti; skorda ek ağırlık aldı.')
        }
        'Sıfır üstüne yeni dönüş' {
            [void]$reasons.Add('Backtestte sıfır üstüne yeni dönüş yüksek kazanma oranı verdi; skorda teyit olarak öne alındı.')
        }
        'Zayıf ivme' {
            [void]$reasons.Add('Backtestte zayıf ivme segmenti daha düşük kaldı; skor temkinli kırpıldı.')
        }
    }

    [void]$reasons.Add(('Temel filtre geçti: bilanço {0}, kalite {1}, değer {2}; son {3} çeyrek kârlı.' -f `
                (Get-InstantEntryNumberText -Value $earningsScore), `
                (Get-InstantEntryNumberText -Value $qualityScore), `
                (Get-InstantEntryNumberText -Value $valueScore), `
                (Get-InstantEntryNumberText -Value (Get-ObjectPropertyValue -Object $Stock -Name 'PositiveQuarterCount') -Format 'N0')))

    if ($null -ne $rsi) {
        if ($rsi -ge 40 -and $rsi -le 65) {
            [void]$reasons.Add(('RSI {0}; aşırı alıma girmeden momentum toparlanması var.' -f (Get-InstantEntryNumberText -Value $rsi)))
        }
        elseif ($rsi -lt 40) {
            [void]$reasons.Add(('RSI {0}; erken dönüş radarı, teyit beklenmeli.' -f (Get-InstantEntryNumberText -Value $rsi)))
        }
        else {
            [void]$reasons.Add(('RSI {0}; momentum var ama kısa vadeli yorulma riski izlenmeli.' -f (Get-InstantEntryNumberText -Value $rsi)))
        }
    }

    if ($null -ne $RangeProfile) {
        $rangePosition = Get-ObjectPropertyValue -Object $RangeProfile -Name 'PositionPct'
        $rangeDistanceToLow = Get-ObjectPropertyValue -Object $RangeProfile -Name 'DistanceToLowPct'
        $rangeDistanceToSma = Get-ObjectPropertyValue -Object $RangeProfile -Name 'DistanceToSmaPct'
        $rangeBucket = [string](Get-ObjectPropertyValue -Object $RangeProfile -Name 'Bucket')

        if ($rangeBucket -eq '52H Range 10-20') {
            [void]$reasons.Add(('52 haftalık bandın dipten sonraki %10-20 bölgesinde: konum {0}, dibe mesafe {1}; backtestte en dengeli dönüş bölgesi.' -f `
                        (Get-InstantEntryNumberText -Value $rangePosition -Format 'N1' -Suffix '%'), `
                        (Get-InstantEntryNumberText -Value $rangeDistanceToLow -Format 'N1' -Suffix '%')))
        }
        elseif ($rangeBucket -eq '52H Range 0-10') {
            [void]$reasons.Add(('52 haftalık bandın en dip %10 bölgesinde: konum {0}; backtestte tek başına zayıf kaldığı için ek teyit beklenmeli.' -f `
                        (Get-InstantEntryNumberText -Value $rangePosition -Format 'N1' -Suffix '%')))
        }
        elseif ($rangeBucket -eq '52H Range 20-50') {
            [void]$reasons.Add(('52 haftalık bandın orta-alt bölgesinde: konum {0}, 52H ortalamaya mesafe {1}.' -f `
                        (Get-InstantEntryNumberText -Value $rangePosition -Format 'N1' -Suffix '%'), `
                        (Get-InstantEntryNumberText -Value $rangeDistanceToSma -Format 'N1' -Suffix '%')))
        }
        else {
            [void]$reasons.Add(('52 haftalık bandın üst yarısında: konum {0}; güç var ama dip fırsatı değil.' -f `
                        (Get-InstantEntryNumberText -Value $rangePosition -Format 'N1' -Suffix '%')))
        }

        if ($null -ne $MarketRegime) {
            $regimeLabel = [string](Get-ObjectPropertyValue -Object $MarketRegime -Name 'Label')
            $regimeChange = Get-ObjectPropertyValue -Object $MarketRegime -Name 'ChangePct'
            if ($regimeLabel -eq 'BIST düşüyor' -and $rangeBucket -eq '52H Range 10-20') {
                [void]$reasons.Add(('BIST son 4 haftada {0}; backtestte BIST düşüşü + 52H %10-20 bandı daha güçlü çalıştı.' -f `
                            (Get-InstantEntryNumberText -Value $regimeChange -Format 'N1' -Suffix '%')))
            }
        }
    }

    $sectorText = Get-ObjectPropertyValue -Object $Stock -Name 'SectorRotationLabel'
    if ($null -ne $sectorRotationAverage) {
        [void]$reasons.Add(('Sektör rotasyonu {0}; BIST100e göre ortalama fark {1} puan.' -f `
                    $(if ([string]::IsNullOrWhiteSpace([string]$sectorText)) { 'veri yok' } else { [string]$sectorText }), `
                    (Get-InstantEntryNumberText -Value $sectorRotationAverage)))
    }

    if ($null -ne $evEbitda) {
        [void]$reasons.Add(('FD/FAVÖK {0}; ucuz/makul değerleme filtresinde.' -f (Get-InstantEntryNumberText -Value $evEbitda -Format 'N2')))
    }
    elseif ($null -ne $pe -or $null -ne $pb) {
        [void]$reasons.Add(('F/K {0}, PD/DD {1}; finansal değerleme filtresinde.' -f `
                    (Get-InstantEntryNumberText -Value $pe -Format 'N2'), `
                    (Get-InstantEntryNumberText -Value $pb -Format 'N2')))
    }

    if ($null -ne $relativeVolume -and $relativeVolume -ge 0.8) {
        [void]$reasons.Add(('Göreli hacim {0}; fiyat hareketi tamamen hacimsiz değil.' -f (Get-InstantEntryNumberText -Value $relativeVolume -Format 'N2' -Suffix 'x')))
    }

    $opportunity = [pscustomobject][ordered]@{
        Rank = 0
        EntryOpportunityScore = $entryScore
        Symbol = Get-ObjectPropertyValue -Object $Stock -Name 'Symbol'
        Company = Get-ObjectPropertyValue -Object $Stock -Name 'Company'
        SectorTR = Get-ObjectPropertyValue -Object $Stock -Name 'SectorTR'
        Price = Get-ObjectPropertyValue -Object $Stock -Name 'Price'
        Signal = Get-ObjectPropertyValue -Object $Stock -Name 'Signal'
        WeeklyHistogramRisingWeeks = $HistogramProfile.ConsecutiveRisingWeeks
        WeeklyHistogramIncreaseCount = $HistogramProfile.IncreaseCountLast8
        LastWeeklyHistogram = $HistogramProfile.LastHistogram
        PreviousWeeklyHistogram = $HistogramProfile.PreviousHistogram
        WeeklyHistogramZeroCross = $zeroCross
        WeeklyHistogramRecentZeroCross = $recentZeroCross
        WeeklyHistogramLabel = $HistogramProfile.Label
        WeeklyHistogramSeriesText = $HistogramProfile.Last8HistogramText
        RSI = $rsi
        RelativeVolume = $relativeVolume
        EvEbitda = $evEbitda
        PE = $pe
        PB = $pb
        EarningsScore = $earningsScore
        QualityScore = $qualityScore
        ValueScore = $valueScore
        MacroSectorScore = Get-ObjectPropertyValue -Object $Stock -Name 'MacroSectorScore'
        SectorRotationLabel = $sectorText
        Range52PositionPct = Get-ObjectPropertyValue -Object $RangeProfile -Name 'PositionPct'
        Range52DistanceToLowPct = Get-ObjectPropertyValue -Object $RangeProfile -Name 'DistanceToLowPct'
        Range52DistanceToSmaPct = Get-ObjectPropertyValue -Object $RangeProfile -Name 'DistanceToSmaPct'
        Range52Bucket = Get-ObjectPropertyValue -Object $RangeProfile -Name 'Bucket'
        MarketRegimeLabel = Get-ObjectPropertyValue -Object $MarketRegime -Name 'Label'
        MarketRegimeChangePct = Get-ObjectPropertyValue -Object $MarketRegime -Name 'ChangePct'
        Reason = ($reasons -join ' ')
        TradingViewSymbol = Get-ObjectPropertyValue -Object $Stock -Name 'TradingViewSymbol'
    }

    if (Test-InstantEntryOpportunityFilter -Opportunity $opportunity) {
        $opportunity.Reason = 'Sıkı anlık alış filtresi geçti: skor 85+, MACD yeni sıfır kesişimi veya pozitif ivme + 52H %20-50 bandı. ' + $opportunity.Reason
    }

    return $opportunity
}

function Get-InstantEntryOpportunities {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Stocks,

        [int]$Count = 0,

        [int]$CandidateLimit = 40,

        [int]$TimeoutSec = 5,

        [int]$MaxElapsedSec = 75
    )

    $startedAt = Get-Date
    $marketRegime = Get-InstantEntryMarketRegime -BenchmarkCloses @(Get-YahooWeeklyCloseSeries -Symbol 'XU100' -TimeoutSec $TimeoutSec)

    $prefiltered = @(
        $Stocks |
            Where-Object { Test-InstantEntryFundamentalCandidate -Stock $_ } |
            Sort-Object `
                @{ Expression = { Get-ObjectPropertyValue -Object $_ -Name 'Score' }; Descending = $true }, `
                @{ Expression = { Get-ObjectPropertyValue -Object $_ -Name 'EarningsScore' }; Descending = $true }, `
                @{ Expression = { Get-ObjectPropertyValue -Object $_ -Name 'ValueScore' }; Descending = $true } |
            Select-Object -First $CandidateLimit
    )

    $opportunities = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in $prefiltered) {
        if ($MaxElapsedSec -gt 0 -and ((Get-Date) - $startedAt).TotalSeconds -ge $MaxElapsedSec) {
            break
        }

        $symbol = [string](Get-ObjectPropertyValue -Object $candidate -Name 'Symbol')
        if ([string]::IsNullOrWhiteSpace($symbol)) {
            continue
        }

        $closes = @(Get-YahooWeeklyCloseSeries -Symbol $symbol -TimeoutSec $TimeoutSec)
        $profile = if ($closes.Count -gt 0) {
            Get-WeeklyMacdHistogramProfile -Closes $closes
        }
        else {
            $null
        }

        if ($null -eq $profile) {
            continue
        }
        if ($profile.ConsecutiveRisingWeeks -lt 2) {
            continue
        }

        $rangeProfile = Get-InstantEntryRangeProfile -Closes $closes
        [void]$opportunities.Add((New-InstantEntryOpportunity -Stock $candidate -HistogramProfile $profile -RangeProfile $rangeProfile -MarketRegime $marketRegime))
    }

    $ranked = @(
        $opportunities |
            Where-Object { Test-InstantEntryOpportunityFilter -Opportunity $_ } |
            Sort-Object EntryOpportunityScore -Descending
    )
    if ($Count -gt 0) {
        $ranked = @($ranked | Select-Object -First $Count)
    }

    $rank = 1
    foreach ($opportunity in $ranked) {
        $opportunity.Rank = $rank
        $rank++
    }

    return @($ranked)
}

function Get-ModelPortfolioDefinitions {
    return @(
        [pscustomobject][ordered]@{
            Id = 'Dengeli'
            Name = 'Dengeli Model Portföy'
            Strategy = 'Dengeli'
            Description = 'Makro/sektör bağlamı, trend, değerleme, kalite, bilanço, momentum ve likiditeyi dengeli ağırlıklarla bir arada değerlendirir.'
        },
        [pscustomobject][ordered]@{
            Id = 'Deger'
            Name = 'Değer Model Portföyü'
            Strategy = 'Değer'
            Description = 'F/K, PD/DD ve finans dışı hisselerde FD/FAVÖK ağırlıklı değerleme puanını öne çıkarır; kârlılık, makro/sektör bağlamı, likidite ve risk tabanı değer tuzağı riskini azaltmak için korunur.'
        },
        [pscustomobject][ordered]@{
            Id = 'Momentum'
            Name = 'Momentum Model Portföyü'
            Strategy = 'Momentum'
            Description = 'Trend, 200 günlük ortalama, MACD, RSI ve hacim teyidini öne çıkarır; yalnızca ortak kârlılık, büyüklük, makro/sektör, likidite ve risk koşullarını geçen hisseleri kullanır.'
        },
        [pscustomobject][ordered]@{
            Id = 'Kalite'
            Name = 'Kalite Model Portföyü'
            Strategy = 'Kalite'
            Description = 'ROE, bilanço puanı, FAVÖK sürekliliği ve kâr kalitesini öne çıkarır; fiyat, makro/sektör ve likidite koşullarını ortak koruma filtresi olarak uygular.'
        }
    )
}

function Get-ModelPortfolioNumberText {
    param(
        $Value,
        [string]$Suffix = ''
    )

    if ($null -eq $Value) {
        return 'veri yok'
    }

    return ('{0:N1}{1}' -f [double]$Value, $Suffix)
}

function Get-ModelPortfolioSelectionReason {
    param(
        $Stock,
        [ValidateSet('Dengeli', 'Değer', 'Momentum', 'Kalite')]
        [string]$Strategy
    )

    switch ($Strategy) {
        'Değer' {
            return 'Strateji skoru {0}; değer puanı {1}; F/K {2}; PD/DD {3}; FD/FAVÖK {4}; makro/sektör {5}; bilanço {6}; risk {7}.' -f `
                (Get-ModelPortfolioNumberText -Value $Stock.Score), `
                (Get-ModelPortfolioNumberText -Value $Stock.ValueScore), `
                (Get-ModelPortfolioNumberText -Value $Stock.PE), `
                (Get-ModelPortfolioNumberText -Value $Stock.PB), `
                (Get-ModelPortfolioNumberText -Value (Get-ObjectPropertyValue -Object $Stock -Name 'EvEbitda')), `
                (Get-ModelPortfolioNumberText -Value $Stock.MacroSectorScore), `
                (Get-ModelPortfolioNumberText -Value $Stock.EarningsScore), `
                $Stock.RiskLevel
        }
        'Momentum' {
            return 'Strateji skoru {0}; trend {1}; momentum {2}; 1 ay {3}; RSI {4}; MACD hist {5}; göreli hacim {6}; risk {7}.' -f `
                (Get-ModelPortfolioNumberText -Value $Stock.Score), `
                (Get-ModelPortfolioNumberText -Value $Stock.TrendScore), `
                (Get-ModelPortfolioNumberText -Value $Stock.MomentumScore), `
                (Get-ModelPortfolioNumberText -Value $Stock.PerfMonth -Suffix '%'), `
                (Get-ModelPortfolioNumberText -Value $Stock.RSI), `
                (Get-ModelPortfolioNumberText -Value (Get-ObjectPropertyValue -Object $Stock -Name 'MacdHistogram')), `
                (Get-ModelPortfolioNumberText -Value $Stock.RelativeVolume -Suffix 'x'), `
                $Stock.RiskLevel
        }
        'Kalite' {
            return 'Strateji skoru {0}; kalite {1}; ROE {2}; bilanço {3}; FAVÖK trendi {4}; son 5 çeyrekte {5} kârlı dönem; makro/sektör {6}; risk {7}.' -f `
                (Get-ModelPortfolioNumberText -Value $Stock.Score), `
                (Get-ModelPortfolioNumberText -Value $Stock.QualityScore), `
                (Get-ModelPortfolioNumberText -Value $Stock.ROE -Suffix '%'), `
                (Get-ModelPortfolioNumberText -Value $Stock.EarningsScore), `
                $(if ([string]::IsNullOrWhiteSpace([string](Get-ObjectPropertyValue -Object $Stock -Name 'EbitdaTrendLabel'))) { 'veri yok' } else { Get-ObjectPropertyValue -Object $Stock -Name 'EbitdaTrendLabel' }), `
                $Stock.PositiveQuarterCount, `
                (Get-ModelPortfolioNumberText -Value $Stock.MacroSectorScore), `
                $Stock.RiskLevel
        }
        default {
            return 'Strateji skoru {0}; makro/sektör {1}; trend {2}; değer {3}; kalite {4}; bilanço {5}; teknik RSI {6}; risk {7}.' -f `
                (Get-ModelPortfolioNumberText -Value $Stock.Score), `
                (Get-ModelPortfolioNumberText -Value $Stock.MacroSectorScore), `
                (Get-ModelPortfolioNumberText -Value $Stock.TrendScore), `
                (Get-ModelPortfolioNumberText -Value $Stock.ValueScore), `
                (Get-ModelPortfolioNumberText -Value $Stock.QualityScore), `
                (Get-ModelPortfolioNumberText -Value $Stock.EarningsScore), `
                (Get-ModelPortfolioNumberText -Value $Stock.RSI), `
                $Stock.RiskLevel
        }
    }
}

function Test-ModelPortfolioEligibleStock {
    param($Stock)

    $evEbitda = Get-ObjectPropertyValue -Object $Stock -Name 'EvEbitda'
    $latestEbitda = Get-ObjectPropertyValue -Object $Stock -Name 'LatestEbitdaUSDMn'
    $positiveEbitdaCount = Get-ObjectPropertyValue -Object $Stock -Name 'PositiveEbitdaQuarterCount'
    $macdLine = Get-ObjectPropertyValue -Object $Stock -Name 'MacdLine'
    $macdSignal = Get-ObjectPropertyValue -Object $Stock -Name 'MacdSignal'
    $macdHistogram = Get-ObjectPropertyValue -Object $Stock -Name 'MacdHistogram'

    $roeOk = $null -eq $Stock.ROE -or $Stock.ROE -ge 10
    $valueOk = $Stock.Sector -eq 'Finance' -or $null -eq $evEbitda -or ($evEbitda -gt 0 -and $evEbitda -le 12)
    $ebitdaOk = ($null -eq $latestEbitda -or $latestEbitda -gt 0) -and
        ($null -eq $positiveEbitdaCount -or $positiveEbitdaCount -ge 3)
    $macroOk = $null -eq $Stock.MacroSectorScore -or $Stock.MacroSectorScore -ge 35

    $technicalChecks = 0
    $technicalPasses = 0
    if ($null -ne $Stock.SMA200 -and $Stock.SMA200 -gt 0 -and $null -ne $Stock.Price) {
        $technicalChecks++
        if ($Stock.Price -ge $Stock.SMA200) { $technicalPasses++ }
    }
    if ($null -ne $macdLine -and $null -ne $macdSignal -and $null -ne $macdHistogram) {
        $technicalChecks++
        if ($macdLine -ge $macdSignal -and $macdHistogram -ge 0) { $technicalPasses++ }
    }
    if ($null -ne $Stock.RSI) {
        $technicalChecks++
        if ($Stock.RSI -ge 40 -and $Stock.RSI -le 65) { $technicalPasses++ }
    }
    if ($null -ne $Stock.RelativeVolume) {
        $technicalChecks++
        if ($Stock.RelativeVolume -ge 0.8) { $technicalPasses++ }
    }
    $technicalOk = $technicalChecks -eq 0 -or $technicalPasses -ge [Math]::Min(2, $technicalChecks)

    return $null -ne $Stock.Price -and $Stock.Price -gt 0 -and
        $null -ne $Stock.MarketCap -and $Stock.MarketCap -ge 5000000000 -and
        $null -ne $Stock.AverageVolume10D -and $Stock.AverageVolume10D -ge 250000 -and
        $Stock.RiskLevel -ne 'Yüksek' -and
        -not [string]::IsNullOrWhiteSpace([string]$Stock.SectorTR) -and
        $Stock.SectorTR -ne 'Sektör Verisi Yok' -and
        $null -ne $Stock.LatestNetIncomeTRYBn -and $Stock.LatestNetIncomeTRYBn -gt 0 -and
        $null -ne $Stock.PositiveQuarterCount -and $Stock.PositiveQuarterCount -ge 3 -and
        $roeOk -and
        $valueOk -and
        $ebitdaOk -and
        $macroOk -and
        $technicalOk
}

function Get-ModelPortfolioSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Stocks,

        [ValidateSet('Dengeli', 'Değer', 'Momentum', 'Kalite')]
        [string]$Strategy,

        [int]$Count = 5,

        [int]$MaxPerSector = 2
    )

    $candidates = @(
        Get-BistScores -Stocks $Stocks -Strategy $Strategy |
            Where-Object { Test-ModelPortfolioEligibleStock -Stock $_ } |
            Sort-Object Score -Descending
    )

    $selected = [System.Collections.Generic.List[object]]::new()
    $selectedSymbols = @{}
    $sectorCounts = @{}

    foreach ($candidate in $candidates) {
        $sector = [string]$candidate.SectorTR
        $sectorCount = if ($sectorCounts.ContainsKey($sector)) { [int]$sectorCounts[$sector] } else { 0 }
        if ($sectorCount -ge $MaxPerSector) {
            continue
        }

        [void]$selected.Add($candidate)
        $selectedSymbols[[string]$candidate.Symbol] = $true
        $sectorCounts[$sector] = $sectorCount + 1
        if ($selected.Count -ge $Count) {
            break
        }
    }

    if ($selected.Count -lt $Count) {
        foreach ($candidate in $candidates) {
            $symbol = [string]$candidate.Symbol
            if ($selectedSymbols.ContainsKey($symbol)) {
                continue
            }

            [void]$selected.Add($candidate)
            $selectedSymbols[$symbol] = $true
            if ($selected.Count -ge $Count) {
                break
            }
        }
    }

    if ($selected.Count -lt $Count) {
        throw "$Strategy model portföyü için uygun hisse sayısı $Count adedinin altında kaldı."
    }

    return @($selected.ToArray())
}

function Get-BistFullClosureDates {
    param([int]$Year)

    if ($Year -eq 2026) {
        return @(
            [datetime]'2026-01-01',
            [datetime]'2026-03-20',
            [datetime]'2026-04-23',
            [datetime]'2026-05-01',
            [datetime]'2026-05-19',
            [datetime]'2026-05-27',
            [datetime]'2026-05-28',
            [datetime]'2026-05-29',
            [datetime]'2026-07-15',
            [datetime]'2026-10-29'
        )
    }

    return @()
}

function Get-LastModelPortfolioTradingDay {
    param([datetime]$Month)

    $candidate = [datetime]::new($Month.Year, $Month.Month, [datetime]::DaysInMonth($Month.Year, $Month.Month))
    $closedDates = @(Get-BistFullClosureDates -Year $candidate.Year)
    while ($candidate.DayOfWeek -in @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday) -or
        @($closedDates | Where-Object { $_.Date -eq $candidate.Date }).Count -gt 0) {
        $candidate = $candidate.AddDays(-1)
    }

    return $candidate.Date
}

function Get-LatestCompletedModelPortfolioPeriodEnd {
    param([datetime]$AsOf)

    $currentMonthEnd = Get-LastModelPortfolioTradingDay -Month $AsOf
    $marketCloseBuffer = [timespan]::FromHours(18).Add([timespan]::FromMinutes(10))
    if ($AsOf.Date -gt $currentMonthEnd -or
        ($AsOf.Date -eq $currentMonthEnd -and $AsOf.TimeOfDay -ge $marketCloseBuffer)) {
        return $currentMonthEnd
    }

    return Get-LastModelPortfolioTradingDay -Month $AsOf.AddMonths(-1)
}

function Get-NextModelPortfolioRebalanceDate {
    param(
        $LastRebalancePeriodEnd,
        [datetime]$AsOf
    )

    $currentMonthEnd = Get-LastModelPortfolioTradingDay -Month $AsOf
    $lastPeriod = if ($null -ne $LastRebalancePeriodEnd -and
        -not [string]::IsNullOrWhiteSpace([string]$LastRebalancePeriodEnd)) {
        [datetime]$LastRebalancePeriodEnd
    }
    else {
        [datetime]::MinValue
    }

    if ($lastPeriod.Date -lt $currentMonthEnd) {
        return $currentMonthEnd
    }

    return Get-LastModelPortfolioTradingDay -Month $AsOf.AddMonths(1)
}

function New-ModelPortfolioTransaction {
    param(
        [int]$Sequence,
        [datetime]$ExecutionDate,
        [string]$Action,
        [string]$Symbol,
        [string]$Company,
        $Price,
        $Quantity,
        $AmountTL,
        [string]$Note
    )

    return [pscustomobject][ordered]@{
        Sequence = $Sequence
        ExecutionDate = $ExecutionDate.ToString('o')
        ExecutionDateText = $ExecutionDate.ToString('dd.MM.yyyy HH:mm')
        Action = $Action
        Symbol = $Symbol
        Company = $Company
        Price = if ($null -ne $Price) { [Math]::Round([double]$Price, 4) } else { $null }
        Quantity = if ($null -ne $Quantity) { [Math]::Round([double]$Quantity, 6) } else { $null }
        AmountTL = if ($null -ne $AmountTL) { [Math]::Round([double]$AmountTL, 2) } else { $null }
        Note = $Note
    }
}

function New-ModelPortfolioHolding {
    param(
        $Stock,
        [double]$TargetValue,
        [ValidateSet('Dengeli', 'Değer', 'Momentum', 'Kalite')]
        [string]$Strategy
    )

    $quantity = $TargetValue / [double]$Stock.Price
    return [pscustomobject][ordered]@{
        Symbol = [string]$Stock.Symbol
        Company = [string]$Stock.Company
        SectorTR = [string]$Stock.SectorTR
        StrategyScore = [Math]::Round([double]$Stock.Score, 1)
        MacroSectorScore = Get-ObjectPropertyValue -Object $Stock -Name 'MacroSectorScore'
        EvEbitda = Get-ObjectPropertyValue -Object $Stock -Name 'EvEbitda'
        SelectionReason = Get-ModelPortfolioSelectionReason -Stock $Stock -Strategy $Strategy
        Quantity = [Math]::Round($quantity, 6)
        RebalancePrice = [Math]::Round([double]$Stock.Price, 4)
        CostBasisTL = [Math]::Round($TargetValue, 2)
        CurrentPrice = [Math]::Round([double]$Stock.Price, 4)
        CurrentValueTL = [Math]::Round($TargetValue, 2)
        WeightPct = 20.0
        GainSinceRebalanceTL = 0.0
        GainSinceRebalancePct = 0.0
        PriceIsFresh = $true
    }
}

function New-ModelPortfolioSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Stocks,

        [datetime]$AsOf = (Get-Date),

        [double]$InitialCapital = 100000
    )

    $portfolios = [System.Collections.Generic.List[object]]::new()
    foreach ($definition in Get-ModelPortfolioDefinitions) {
        $selection = @(Get-ModelPortfolioSelection -Stocks $Stocks -Strategy $definition.Strategy)
        $targetValue = $InitialCapital / $selection.Count
        $holdings = [System.Collections.Generic.List[object]]::new()
        $transactions = [System.Collections.Generic.List[object]]::new()

        [void]$transactions.Add((New-ModelPortfolioTransaction `
                    -Sequence 1 `
                    -ExecutionDate $AsOf `
                    -Action 'İLK KURULUM' `
                    -Symbol 'PORTFÖY' `
                    -Company $definition.Name `
                    -Price $null `
                    -Quantity $null `
                    -AmountTL $InitialCapital `
                    -Note ('Başlangıç sermayesi 5 eşit parçaya bölündü; hisse başına hedef {0:N2} TL.' -f $targetValue)))

        $sequence = 2
        foreach ($stock in $selection) {
            $holding = New-ModelPortfolioHolding -Stock $stock -TargetValue $targetValue -Strategy $definition.Strategy
            [void]$holdings.Add($holding)
            [void]$transactions.Add((New-ModelPortfolioTransaction `
                        -Sequence $sequence `
                        -ExecutionDate $AsOf `
                        -Action 'AL' `
                        -Symbol $holding.Symbol `
                        -Company $holding.Company `
                        -Price $holding.CurrentPrice `
                        -Quantity $holding.Quantity `
                        -AmountTL $targetValue `
                        -Note ('İlk kurulum: portföyün %20 eşit ağırlığı. {0}' -f $holding.SelectionReason)))
            $sequence++
        }

        [void]$portfolios.Add([pscustomobject][ordered]@{
                Id = $definition.Id
                Name = $definition.Name
                Strategy = $definition.Strategy
                Description = $definition.Description
                StartDate = $AsOf.ToString('o')
                StartDateText = $AsOf.ToString('dd.MM.yyyy HH:mm')
                InitialCapitalTL = [Math]::Round($InitialCapital, 2)
                CurrentValueTL = [Math]::Round($InitialCapital, 2)
                TotalGainTL = 0.0
                TotalReturnPct = 0.0
                LastValuationAt = $AsOf.ToString('o')
                LastValuationAtText = $AsOf.ToString('dd.MM.yyyy HH:mm')
                LastRebalanceDate = $AsOf.ToString('o')
                LastRebalanceDateText = $AsOf.ToString('dd.MM.yyyy HH:mm')
                LastRebalancePeriodEnd = $AsOf.Date.ToString('yyyy-MM-dd')
                NextRebalanceDate = (Get-NextModelPortfolioRebalanceDate -LastRebalancePeriodEnd $AsOf.Date -AsOf $AsOf).ToString('yyyy-MM-dd')
                StatusNote = 'İlk model işlem canlı tarama fiyatlarıyla oluşturuldu.'
                Holdings = $holdings.ToArray()
                Transactions = $transactions.ToArray()
            })
    }

    return [pscustomobject][ordered]@{
        Version = 1
        CreatedAt = $AsOf.ToString('o')
        UpdatedAt = $AsOf.ToString('o')
        InitialCapitalPerPortfolioTL = [Math]::Round($InitialCapital, 2)
        Notes = 'Fiyat bazlı teorik modeldir. Kesirli adet kullanır; komisyon, vergi, kayma, temettü ve bedelli/bedelsiz sermaye hareketleri otomatik olarak hesaba katılmaz.'
        Portfolios = $portfolios.ToArray()
    }
}

function Get-ModelPortfolioStockMap {
    param([object[]]$Stocks)

    $stockMap = @{}
    foreach ($stock in $Stocks) {
        $symbol = [string](Get-ObjectPropertyValue -Object $stock -Name 'Symbol')
        if (-not [string]::IsNullOrWhiteSpace($symbol)) {
            $stockMap[$symbol] = $stock
        }
    }

    return $stockMap
}

function Update-ModelPortfolioValuation {
    param(
        $Portfolio,
        [hashtable]$StockMap,
        [datetime]$AsOf
    )

    $holdings = [System.Collections.Generic.List[object]]::new()
    $totalValue = 0.0
    foreach ($holding in @(Get-ObjectPropertyValue -Object $Portfolio -Name 'Holdings')) {
        $symbol = [string](Get-ObjectPropertyValue -Object $holding -Name 'Symbol')
        $stock = if ($StockMap.ContainsKey($symbol)) { $StockMap[$symbol] } else { $null }
        $freshPrice = Get-ObjectPropertyValue -Object $stock -Name 'Price'
        $priceIsFresh = $null -ne $freshPrice -and [double]$freshPrice -gt 0
        $currentPrice = if ($priceIsFresh) {
            [double]$freshPrice
        }
        else {
            [double](Get-ObjectPropertyValue -Object $holding -Name 'CurrentPrice')
        }
        $quantity = [double](Get-ObjectPropertyValue -Object $holding -Name 'Quantity')
        $costBasis = [double](Get-ObjectPropertyValue -Object $holding -Name 'CostBasisTL')
        $currentValue = $quantity * $currentPrice
        $gain = $currentValue - $costBasis
        $gainPct = if ($costBasis -ne 0) { ($gain / $costBasis) * 100 } else { 0 }
        $totalValue += $currentValue

        [void]$holdings.Add([pscustomobject][ordered]@{
                Symbol = $symbol
                Company = [string](Get-ObjectPropertyValue -Object $holding -Name 'Company')
                SectorTR = [string](Get-ObjectPropertyValue -Object $holding -Name 'SectorTR')
                StrategyScore = Get-ObjectPropertyValue -Object $holding -Name 'StrategyScore'
                MacroSectorScore = Get-ObjectPropertyValue -Object $holding -Name 'MacroSectorScore'
                EvEbitda = Get-ObjectPropertyValue -Object $holding -Name 'EvEbitda'
                SelectionReason = [string](Get-ObjectPropertyValue -Object $holding -Name 'SelectionReason')
                Quantity = [Math]::Round($quantity, 6)
                RebalancePrice = Get-ObjectPropertyValue -Object $holding -Name 'RebalancePrice'
                CostBasisTL = [Math]::Round($costBasis, 2)
                CurrentPrice = [Math]::Round($currentPrice, 4)
                CurrentValueTL = [Math]::Round($currentValue, 2)
                WeightPct = 0.0
                GainSinceRebalanceTL = [Math]::Round($gain, 2)
                GainSinceRebalancePct = [Math]::Round($gainPct, 2)
                PriceIsFresh = $priceIsFresh
            })
    }

    foreach ($holding in $holdings) {
        $holding.WeightPct = if ($totalValue -gt 0) {
            [Math]::Round(($holding.CurrentValueTL / $totalValue) * 100, 2)
        }
        else {
            0.0
        }
    }

    $initialCapital = [double](Get-ObjectPropertyValue -Object $Portfolio -Name 'InitialCapitalTL')
    $totalGain = $totalValue - $initialCapital
    $totalReturnPct = if ($initialCapital -ne 0) { ($totalGain / $initialCapital) * 100 } else { 0 }
    $properties = [ordered]@{}
    foreach ($property in $Portfolio.PSObject.Properties) {
        if ($property.Name -notin @(
                'CurrentValueTL', 'TotalGainTL', 'TotalReturnPct', 'LastValuationAt',
                'LastValuationAtText', 'NextRebalanceDate', 'Holdings'
            )) {
            $properties[$property.Name] = $property.Value
        }
    }

    $lastPeriodEnd = Get-ObjectPropertyValue -Object $Portfolio -Name 'LastRebalancePeriodEnd'
    $properties.CurrentValueTL = [Math]::Round($totalValue, 2)
    $properties.TotalGainTL = [Math]::Round($totalGain, 2)
    $properties.TotalReturnPct = [Math]::Round($totalReturnPct, 2)
    $properties.LastValuationAt = $AsOf.ToString('o')
    $properties.LastValuationAtText = $AsOf.ToString('dd.MM.yyyy HH:mm')
    $properties.NextRebalanceDate = (Get-NextModelPortfolioRebalanceDate -LastRebalancePeriodEnd $lastPeriodEnd -AsOf $AsOf).ToString('yyyy-MM-dd')
    $properties.Holdings = $holdings.ToArray()

    return [pscustomobject]$properties
}

function Invoke-ModelPortfolioRebalance {
    param(
        $Portfolio,
        [object[]]$Stocks,
        [hashtable]$StockMap,
        [datetime]$AsOf,
        [datetime]$PeriodEnd
    )

    $valuedPortfolio = Update-ModelPortfolioValuation -Portfolio $Portfolio -StockMap $StockMap -AsOf $AsOf
    $missingLivePrices = @(
        $valuedPortfolio.Holdings |
            Where-Object { -not $_.PriceIsFresh } |
            Select-Object -ExpandProperty Symbol
    )
    if ($missingLivePrices.Count -gt 0) {
        $valuedPortfolio.StatusNote = 'Ay sonu işlemi ertelendi; canlı fiyatı bulunmayan hisseler: ' + ($missingLivePrices -join ', ')
        return $valuedPortfolio
    }

    $selection = @(Get-ModelPortfolioSelection -Stocks $Stocks -Strategy $valuedPortfolio.Strategy)
    $totalValue = [double]$valuedPortfolio.CurrentValueTL
    $targetValue = $totalValue / $selection.Count
    $oldHoldings = @{}
    foreach ($holding in @($valuedPortfolio.Holdings)) {
        $oldHoldings[[string]$holding.Symbol] = $holding
    }

    $newSymbols = @($selection | Select-Object -ExpandProperty Symbol)
    $oldSymbols = @($valuedPortfolio.Holdings | Select-Object -ExpandProperty Symbol)
    $removedSymbols = @($oldSymbols | Where-Object { $_ -notin $newSymbols })
    $addedSymbols = @($newSymbols | Where-Object { $_ -notin $oldSymbols })
    $keptSymbols = @($newSymbols | Where-Object { $_ -in $oldSymbols })
    $actionLabel = if ($removedSymbols.Count -gt 0 -or $addedSymbols.Count -gt 0) {
        'AY SONU DEĞİŞİM + EŞİTLEME'
    }
    else {
        'AY SONU EŞİTLEME'
    }
    $delayText = if ($AsOf.Date -gt $PeriodEnd.Date) {
        " İşlem, $($PeriodEnd.ToString('dd.MM.yyyy')) ay sonu için ilk sonraki canlı taramada gecikmeli yapıldı."
    }
    else {
        ''
    }
    $summaryNote = 'Portföy {0:N2} TL olarak 5 eşit parçaya bölündü; hisse başına hedef {1:N2} TL. Çıkan: {2}. Giren: {3}. Kalan: {4}.{5}' -f `
        $totalValue, `
        $targetValue, `
        $(if ($removedSymbols.Count -gt 0) { $removedSymbols -join ', ' } else { 'yok' }), `
        $(if ($addedSymbols.Count -gt 0) { $addedSymbols -join ', ' } else { 'yok' }), `
        $(if ($keptSymbols.Count -gt 0) { $keptSymbols -join ', ' } else { 'yok' }), `
        $delayText

    $transactions = [System.Collections.Generic.List[object]]::new()
    foreach ($transaction in @(Get-ObjectPropertyValue -Object $valuedPortfolio -Name 'Transactions')) {
        [void]$transactions.Add($transaction)
    }
    $sequence = $transactions.Count + 1
    [void]$transactions.Add((New-ModelPortfolioTransaction `
                -Sequence $sequence `
                -ExecutionDate $AsOf `
                -Action $actionLabel `
                -Symbol 'PORTFÖY' `
                -Company $valuedPortfolio.Name `
                -Price $null `
                -Quantity $null `
                -AmountTL $totalValue `
                -Note $summaryNote))
    $sequence++

    foreach ($symbol in $removedSymbols) {
        $holding = $oldHoldings[$symbol]
        [void]$transactions.Add((New-ModelPortfolioTransaction `
                    -Sequence $sequence `
                    -ExecutionDate $AsOf `
                    -Action 'SAT' `
                    -Symbol $symbol `
                    -Company $holding.Company `
                    -Price $holding.CurrentPrice `
                    -Quantity $holding.Quantity `
                    -AmountTL $holding.CurrentValueTL `
                    -Note "$PeriodEnd ay sonu strateji sıralamasında portföyden çıktı."))
        $sequence++
    }

    $newHoldings = [System.Collections.Generic.List[object]]::new()
    foreach ($stock in $selection) {
        $symbol = [string]$stock.Symbol
        $newHolding = New-ModelPortfolioHolding -Stock $stock -TargetValue $targetValue -Strategy $valuedPortfolio.Strategy
        [void]$newHoldings.Add($newHolding)

        if ($oldHoldings.ContainsKey($symbol)) {
            $oldHolding = $oldHoldings[$symbol]
            $delta = $targetValue - [double]$oldHolding.CurrentValueTL
            if ([Math]::Abs($delta) -ge 0.01) {
                [void]$transactions.Add((New-ModelPortfolioTransaction `
                            -Sequence $sequence `
                            -ExecutionDate $AsOf `
                            -Action $(if ($delta -gt 0) { 'EŞİTLEME AL' } else { 'EŞİTLEME SAT' }) `
                            -Symbol $symbol `
                            -Company $newHolding.Company `
                            -Price $newHolding.CurrentPrice `
                            -Quantity ([Math]::Abs($delta) / $newHolding.CurrentPrice) `
                            -AmountTL ([Math]::Abs($delta)) `
                            -Note ('Ay sonu %20 eşit ağırlık hedefi; işlem öncesi değer {0:N2} TL, işlem sonrası hedef {1:N2} TL.' -f $oldHolding.CurrentValueTL, $targetValue)))
                $sequence++
            }
        }
        else {
            [void]$transactions.Add((New-ModelPortfolioTransaction `
                        -Sequence $sequence `
                        -ExecutionDate $AsOf `
                        -Action 'AL' `
                        -Symbol $symbol `
                        -Company $newHolding.Company `
                        -Price $newHolding.CurrentPrice `
                        -Quantity $newHolding.Quantity `
                        -AmountTL $targetValue `
                        -Note ("$PeriodEnd ay sonu strateji sıralamasında portföye girdi. $($newHolding.SelectionReason)")))
            $sequence++
        }
    }

    $properties = [ordered]@{}
    foreach ($property in $valuedPortfolio.PSObject.Properties) {
        if ($property.Name -notin @(
                'CurrentValueTL', 'TotalGainTL', 'TotalReturnPct', 'LastRebalanceDate',
                'LastRebalanceDateText', 'LastRebalancePeriodEnd', 'NextRebalanceDate',
                'StatusNote', 'Holdings', 'Transactions'
            )) {
            $properties[$property.Name] = $property.Value
        }
    }

    $initialCapital = [double]$valuedPortfolio.InitialCapitalTL
    $properties.CurrentValueTL = [Math]::Round($totalValue, 2)
    $properties.TotalGainTL = [Math]::Round($totalValue - $initialCapital, 2)
    $properties.TotalReturnPct = [Math]::Round((($totalValue - $initialCapital) / $initialCapital) * 100, 2)
    $properties.LastRebalanceDate = $AsOf.ToString('o')
    $properties.LastRebalanceDateText = $AsOf.ToString('dd.MM.yyyy HH:mm')
    $properties.LastRebalancePeriodEnd = $PeriodEnd.ToString('yyyy-MM-dd')
    $properties.NextRebalanceDate = (Get-NextModelPortfolioRebalanceDate -LastRebalancePeriodEnd $PeriodEnd -AsOf $AsOf).ToString('yyyy-MM-dd')
    $properties.StatusNote = $summaryNote
    $properties.Holdings = $newHoldings.ToArray()
    $properties.Transactions = $transactions.ToArray()

    return [pscustomobject]$properties
}

function Update-ModelPortfolioSet {
    [CmdletBinding()]
    param(
        $PortfolioSet,

        [Parameter(Mandatory)]
        [object[]]$Stocks,

        [datetime]$AsOf = (Get-Date),

        [switch]$AllowRebalance
    )

    if ($null -eq $PortfolioSet -or $null -eq (Get-ObjectPropertyValue -Object $PortfolioSet -Name 'Portfolios')) {
        if ($AllowRebalance) {
            return New-ModelPortfolioSet -Stocks $Stocks -AsOf $AsOf
        }
        return $null
    }

    $stockMap = Get-ModelPortfolioStockMap -Stocks $Stocks
    $latestCompletedPeriodEnd = Get-LatestCompletedModelPortfolioPeriodEnd -AsOf $AsOf
    $portfolios = [System.Collections.Generic.List[object]]::new()
    foreach ($portfolio in @(Get-ObjectPropertyValue -Object $PortfolioSet -Name 'Portfolios')) {
        $valuedPortfolio = Update-ModelPortfolioValuation -Portfolio $portfolio -StockMap $stockMap -AsOf $AsOf
        $lastPeriodValue = Get-ObjectPropertyValue -Object $valuedPortfolio -Name 'LastRebalancePeriodEnd'
        $lastPeriodEnd = if ($null -ne $lastPeriodValue -and -not [string]::IsNullOrWhiteSpace([string]$lastPeriodValue)) {
            [datetime]$lastPeriodValue
        }
        else {
            [datetime]::MinValue
        }

        if ($AllowRebalance -and $lastPeriodEnd.Date -lt $latestCompletedPeriodEnd.Date) {
            [void]$portfolios.Add((Invoke-ModelPortfolioRebalance `
                        -Portfolio $valuedPortfolio `
                        -Stocks $Stocks `
                        -StockMap $stockMap `
                        -AsOf $AsOf `
                        -PeriodEnd $latestCompletedPeriodEnd))
        }
        else {
            [void]$portfolios.Add($valuedPortfolio)
        }
    }

    $properties = [ordered]@{}
    foreach ($property in $PortfolioSet.PSObject.Properties) {
        if ($property.Name -notin @('UpdatedAt', 'Portfolios')) {
            $properties[$property.Name] = $property.Value
        }
    }
    $properties.UpdatedAt = $AsOf.ToString('o')
    $properties.Portfolios = $portfolios.ToArray()

    return [pscustomobject]$properties
}

Export-ModuleMember -Function `
    Invoke-BistStockScan, `
    Get-ObjectPropertyValue, `
    Get-BistScore, `
    Get-BistScores, `
    Get-ModelPortfolioDefinitions, `
    Get-ModelPortfolioSelection, `
    Get-LastModelPortfolioTradingDay, `
    Get-MacroSnapshot, `
    Get-InstantEntryOpportunities, `
    New-ModelPortfolioSet, `
    Update-ModelPortfolioSet
