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
    'ebitda_ttm',
    # --- Denetim #3 genisletmesi (APPEND-ONLY: eslestirme indeks-tabanli, sona ekleme
    # mevcut alanlari bozmaz; ayni tek ucretsiz HTTP istegi). Teknik + temel: ---
    'ATR',                     # 54: ortalama gercek aralik (stop/pozisyon boyutlama)
    'ADX',                     # 55: trend gucu
    'EMA20',                   # 56
    'EMA50',                   # 57
    'EMA200',                  # 58
    'price_52_week_high',      # 59
    'price_52_week_low',       # 60
    'Stoch.K',                 # 61: asiri alim/satim capraz teyit
    'MoneyFlow',               # 62: MFI (para akisi)
    'BBPower',                 # 63
    'gap',                     # 64: acilis boslugu %
    'return_on_assets_fq',     # 65: ROA
    'gross_margin',            # 66
    'operating_margin',        # 67
    'after_tax_margin',        # 68: net marj
    'current_ratio'            # 69: cari oran
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
# Kendini ogrenen sinyal kalibrasyonu (Set-SignalCalibration ile yuklenir).
$script:SignalCalibration = $null
$script:SignalConfig = $null

$script:InflationBenchmark = [pscustomobject][ordered]@{
    AsOf = 'Nisan 2026'
    Inflation1YPct = 32.37
    Inflation3YPct = 209.9
    Inflation5YPct = 656.7
    SourceNote = 'TÜİK Nisan 2026 yıllık TÜFE %32,37; 3Y ve 5Y eşikler Nisan yıllık TÜFE oranlarının bileşik yaklaşık değeridir.'
}

function Invoke-WithRetry {
    <#
        Gecici ag/HTTP hatalarinda ustel bekleme ile yeniden dener.
        Tum denemeler basarisiz olursa son istisnayi yeniden firlatir.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        [int]$MaxAttempts = 3,
        [double]$BaseDelaySec = 2.0,
        [string]$OperationName = 'islem'
    )

    if ($MaxAttempts -lt 1) { $MaxAttempts = 1 }

    $attempt = 0
    $lastError = $null
    while ($attempt -lt $MaxAttempts) {
        $attempt++
        try {
            return & $ScriptBlock
        }
        catch {
            $lastError = $_
            if ($attempt -ge $MaxAttempts) {
                break
            }
            $delay = $BaseDelaySec * [Math]::Pow(2, $attempt - 1)
            Write-Warning ("{0}: {1}. deneme basarisiz ({2}). {3:N1}sn sonra tekrar denenecek." -f $OperationName, $attempt, $_.Exception.Message, $delay)
            Start-Sleep -Seconds $delay
        }
    }

    throw $lastError
}

function ConvertTo-DoubleOrNull {
    param($Value)

    # DIKKAT: '$Value -eq ""' kullanma — PowerShell'de (0.0 -eq '') True'dur,
    # gercek sayisal 0 "eksik veri" sanilip $null olurdu (or. carpan 0, %0 degisim).
    if ($null -eq $Value -or ($Value -is [string] -and $Value.Trim() -eq '')) {
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
            $xml = Invoke-WithRetry -OperationName 'TCMB USD/TRY' -MaxAttempts 2 -BaseDelaySec 1 -ScriptBlock {
                Invoke-RestMethod -Uri $url -Method Get -TimeoutSec $TimeoutSec -ErrorAction Stop
            }
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
        [int]$TimeoutSec = 15,
        [int]$MaxElapsedSec = 20
    )

    $rates = @{}
    $startedAt = Get-Date
    foreach ($date in @($Dates | Sort-Object -Unique)) {
        if ($MaxElapsedSec -gt 0 -and ((Get-Date) - $startedAt).TotalSeconds -ge $MaxElapsedSec) {
            break
        }

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
        $response = Invoke-WithRetry -OperationName 'BIST endeks benchmark' -MaxAttempts 2 -BaseDelaySec 1 -ScriptBlock {
            Invoke-RestMethod `
                -Method Post `
                -Uri $script:TradingViewScannerUrl `
                -ContentType 'application/json' `
                -Headers $headers `
                -Body ($payload | ConvertTo-Json -Depth 8 -Compress) `
                -TimeoutSec $TimeoutSec `
                -ErrorAction Stop
        }
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
        $response = Invoke-WithRetry -OperationName "Investing $url" -MaxAttempts 1 -BaseDelaySec 1 -ScriptBlock {
            Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
        }
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

function Get-YahooQuoteSnapshot {
    <#
        Makro metrik icin Yahoo Finance chart API'sinden anlik deger + gunluk
        degisim. Runner'da calistigi kanitli (Investing.com engelli, TCMB 404
        olabilir); bu yuzden coklu-kaynak fallback'inde birincil kaynaktir.
        Bos veride $null doner.
    #>
    param(
        [string]$Id,
        [string]$Name,
        [string]$YahooSymbol,
        [string]$Unit = '',
        [string]$Source = 'Yahoo Finance',
        [int]$TimeoutSec = 8
    )

    $series = @(Get-YahooDailyCloseSeries -Symbol $YahooSymbol -Range '1mo' -TimeoutSec $TimeoutSec -AsRawTicker)
    if ($series.Count -lt 1) { return $null }
    $last = [double]$series[$series.Count - 1].Close
    $prev = if ($series.Count -ge 2) { [double]$series[$series.Count - 2].Close } else { $null }
    $chg = if ($null -ne $prev -and $prev -ne 0) { (($last / $prev) - 1.0) * 100.0 } else { $null }

    return [pscustomobject][ordered]@{
        Id = $Id
        Name = $Name
        Value = [Math]::Round($last, 4)
        Change = if ($null -ne $prev) { [Math]::Round($last - $prev, 4) } else { $null }
        ChangePct = if ($null -ne $chg) { [Math]::Round($chg, 2) } else { $null }
        Unit = $Unit
        Status = 'Veri Yok'
        Source = $Source
        Url = "https://finance.yahoo.com/quote/$YahooSymbol"
        Note = ''
    }
}

function Get-TradingViewQuoteSnapshot {
    <#
        TradingView global scanner'dan tek sembol icin deger + gunluk degisim.
        TVC:TR10Y gibi BIST disi semboller icin (runner'da scanner POST calisir).
        Hata/bos veride $null doner.
    #>
    param(
        [string]$Ticker,
        [string]$Id,
        [string]$Name,
        [string]$Unit = '',
        [int]$TimeoutSec = 8
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $payload = @{ symbols = @{ tickers = @($Ticker) }; columns = @('close', 'change') }
    $headers = @{ 'User-Agent' = 'BIST-Hisse-Tarayici/1.0'; 'Accept' = 'application/json' }
    $body = $payload | ConvertTo-Json -Depth 6 -Compress

    try {
        $resp = Invoke-WithRetry -OperationName "TradingView $Ticker" -MaxAttempts 2 -BaseDelaySec 1 -ScriptBlock {
            Invoke-RestMethod -Method Post -Uri 'https://scanner.tradingview.com/global/scan' `
                -ContentType 'application/json' -Headers $headers -Body $body -TimeoutSec $TimeoutSec -ErrorAction Stop
        }
    }
    catch { return $null }

    $data = @(Get-ObjectPropertyValue -Object $resp -Name 'data')
    if ($data.Count -eq 0) { return $null }
    $d = @(Get-ObjectPropertyValue -Object $data[0] -Name 'd')
    if ($d.Count -lt 1) { return $null }
    $value = ConvertTo-DoubleOrNull $d[0]
    if ($null -eq $value) { return $null }
    $chgPct = if ($d.Count -ge 2) { ConvertTo-DoubleOrNull $d[1] } else { $null }

    return [pscustomobject][ordered]@{
        Id = $Id
        Name = $Name
        Value = [Math]::Round([double]$value, 2)
        Change = $null
        ChangePct = if ($null -ne $chgPct) { [Math]::Round([double]$chgPct, 2) } else { $null }
        Unit = $Unit
        Status = 'Veri Yok'
        Source = 'TradingView'
        Url = "https://www.tradingview.com/symbols/$($Ticker -replace ':', '-')/"
        Note = 'TradingView kaynağı.'
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
                Sma200 = Get-ObjectPropertyValue -Object $index -Name 'SMA200'   # rejim-nakit hedefi trend kapisi icin
                Sma50 = Get-ObjectPropertyValue -Object $index -Name 'SMA50'     # devre kesici kurtarma kapisi icin
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

    # USD/TRY: once TCMB, alinamazsa Yahoo Finance (USDTRY=X) yedegi.
    $usdTry = Get-TcmbUsdTrySnapshot -AsOf $AsOf -TimeoutSec $TimeoutSec
    if ($null -eq $usdTry.Value) {
        $usdTryYahoo = Get-YahooQuoteSnapshot -Id 'USDTRY_Tcmb' -Name 'USD/TRY' -YahooSymbol 'USDTRY=X' -Unit 'TL' -Source 'Yahoo Finance' -TimeoutSec $TimeoutSec
        if ($null -ne $usdTryYahoo -and $null -ne $usdTryYahoo.Value) {
            $pct = $usdTryYahoo.ChangePct
            $usdTryYahoo.Status = if ($null -eq $pct) { 'Veri Yok' }
            elseif ([Math]::Abs([double]$pct) -lt 0.5) { 'Kur sakin' }
            elseif ([double]$pct -ge 0.5) { 'Kur yukarı baskı' }
            else { 'TL lehine' }
            $usdTryYahoo.Note = 'TCMB kuru alınamadı; Yahoo Finance USDTRY=X kullanıldı.'
            $usdTry = $usdTryYahoo
        }
    }
    [void]$metrics.Add($usdTry)

    # CDS/TR10Y/DXY/VIX: DXY ve VIX icin Yahoo birincil, Investing yedek.
    # CDS ve TR10Y'nin guvenilir ucretsiz Yahoo karsiligi yok -> Investing (best-effort).
    $yahooMacroMap = @{ 'DXY' = 'DX-Y.NYB'; 'VIX' = '^VIX' }
    foreach ($instrument in $script:MacroInvestingInstruments) {
        $snapshot = $null
        # TR10Y: EVDS (seri kodu varsa) -> TradingView (TVC:TR10Y) -> Investing.
        if ($instrument.Id -eq 'TR_10Y') {
            $tr10ySeries = $env:BIST_EVDS_TR10Y_SERIES
            if (-not [string]::IsNullOrWhiteSpace($tr10ySeries)) {
                $snapshot = Get-EvdsRateSnapshot -Series $tr10ySeries -Id 'TR_10Y' -Name $instrument.Name -Unit '%' -TimeoutSec $TimeoutSec
            }
            if ($null -eq $snapshot -or $null -eq $snapshot.Value) {
                $snapshot = Get-TradingViewQuoteSnapshot -Ticker 'TVC:TR10Y' -Id 'TR_10Y' -Name $instrument.Name -Unit '%' -TimeoutSec $TimeoutSec
            }
        }
        if (($null -eq $snapshot -or $null -eq $snapshot.Value) -and $yahooMacroMap.ContainsKey($instrument.Id)) {
            $snapshot = Get-YahooQuoteSnapshot -Id $instrument.Id -Name $instrument.Name `
                -YahooSymbol $yahooMacroMap[$instrument.Id] -Unit $instrument.Unit -TimeoutSec $TimeoutSec
            if ($null -ne $snapshot -and $null -ne $snapshot.Value) { $snapshot.Note = 'Yahoo Finance kaynağı.' }
        }
        if ($null -eq $snapshot -or $null -eq $snapshot.Value) {
            $snapshot = Get-InvestingInstrumentSnapshot `
                -Id $instrument.Id `
                -Name $instrument.Name `
                -Urls $instrument.Urls `
                -Unit $instrument.Unit `
                -LowerIsBetter $instrument.LowerIsBetter `
                -TimeoutSec $TimeoutSec
        }
        $snapshot.Status = Get-MarketMetricStatus -Id $snapshot.Id -Value $snapshot.Value -ChangePct $snapshot.ChangePct
        [void]$metrics.Add($snapshot)
    }

    # TCMB EVDS (anahtar $env:BIST_EVDS_API_KEY varsa): faiz + TÜFE
    foreach ($evdsMetric in @(Get-EvdsMacroMetrics -TimeoutSec $TimeoutSec)) {
        [void]$metrics.Add($evdsMetric)
    }

    # Brent petrol: Turkiye enflasyon/cari denge kanali (yukselis = baski) +
    # sektorel ayrisma (havacilik/petrokimya girdisi, rafineri karisik).
    try {
        $brent = Get-YahooQuoteSnapshot -Id 'BRENT' -Name 'Brent petrol' -YahooSymbol 'BZ=F' -Unit '$' -Source 'Yahoo Finance' -TimeoutSec $TimeoutSec
        if ($null -ne $brent -and $null -ne $brent.Value) {
            $bp = ConvertTo-DoubleOrNull $brent.ChangePct
            $brent.Status = if ($null -eq $bp) { 'Veri Yok' }
            elseif ($bp -ge 1.5) { 'Petrol baskısı' }
            elseif ($bp -le -1.5) { 'Destekleyici' }
            else { 'Nötr' }
            $brent.Note = 'Yükselen petrol TR enflasyonu ve cari denge için negatiftir.'
            [void]$metrics.Add($brent)
        }
    }
    catch { }

    # Akis metrikleri: yabanci net hisse alimi (TCMB haftalik) + yerli hisse fonu
    # akisi (TEFAS). Rejim sayaclarina (Destekleyici/Baski) katilir; veri yoksa atlanir.
    foreach ($flowMetric in @(Get-FlowMacroMetrics -TimeoutSec $TimeoutSec)) {
        [void]$metrics.Add($flowMetric)
    }

    $supportive = @($metrics | Where-Object { $_.Status -match 'Pozitif|Destekleyici|sakin|lehine|düşük|azalıyor|ılımlı|düşüyor' }).Count
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
        MeasurementNote = 'Makro görünüm; BIST trendi, banka relatif gücü, USD/TRY, Türkiye 5Y CDS, TR10Y faiz, DXY, VIX ve akış verileri (yabancı net hisse alımı, TEFAS hisse fonu akışı) ile izlenir. Düşen CDS/faiz/VIX/DXY, BIST100ün SMA200 üstünde kalması ve pozitif akış risk iştahı lehine yorumlanır.'
        Metrics = $metrics.ToArray()
    }
}

function Get-MacroRegime {
    <#
        DETERMINISTIK makro rejim motoru (Turkiye/BIST ozel). Get-MacroSnapshot
        metriklerini makro OLAYLARA cevirir, olaylari agirlikli toplayip rejim
        etiketi ve sektor tiltleri uretir. LLM YOK — tamamen kural tabanli;
        haber-LLM katmani ileride yalniz olay-cikarimi icin opsiyonel eklenebilir.

        Olay taksonomisi: inflation, interest_rate, cds_risk, fx_pressure,
        foreign_flow, domestic_flow, global_risk, commodity_oil, market_trend.
        Her olay: Type, Direction(-1/0/+1; BIST icin), Confidence(0-1),
        Sectors(@{sektor=tilt -1..+1}), Horizon(short/medium/long), Note.

        Cikti: { Regime='risk-on|neutral|risk-off', Score(-1..+1), Confidence,
                 Events[], SectorTilts(@{}), Note }. Veri yoksa olay atlanir;
        hic olay yoksa $null (cagiran ayari 0 birakir — veri-kapili).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Snapshot,
        # data/macro_news.json okunacak dizin; bos = <repo>/data. $null gecilirse haber katmani atlanmaz,
        # dosya yoksa zaten sessizce atlanir (veri-kapili).
        [string]$DataDir
    )

    $metricById = @{}
    foreach ($m in @(Get-ObjectPropertyValue -Object $Snapshot -Name 'Metrics')) {
        $mid = [string](Get-ObjectPropertyValue -Object $m -Name 'Id')
        if ($mid -and -not $metricById.ContainsKey($mid)) { $metricById[$mid] = $m }
    }
    if ($metricById.Count -eq 0) { return $null }
    $val = { param($id, $name) if ($metricById.ContainsKey($id)) { ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $metricById[$id] -Name $name) } else { $null } }

    $events = [System.Collections.Generic.List[object]]::new()
    $addEvent = {
        param($type, $dir, $conf, $sectors, $horizon, $note)
        [void]$events.Add([pscustomobject]@{ Type = $type; Direction = [int]$dir; Confidence = [double]$conf; Sectors = $sectors; Horizon = $horizon; Note = [string]$note })
    }

    # 1) inflation + interest_rate (faiz indirimi beklentisi kanali):
    #    Dusen yillik TUFE -> gevseme beklentisi -> Banka/GYO/ic talep pozitif.
    $cpiChg = & $val 'TR_CPI_YOY' 'Change'
    $cpiYoy = & $val 'TR_CPI_YOY' 'Value'
    if ($null -ne $cpiChg) {
        if ($cpiChg -le -0.5) { & $addEvent 'inflation' 1 0.7 @{ Banka = 1.0; GYO = 1.0; Holding = 0.5; Perakende = 0.5 } 'medium' ("Yıllık TÜFE {0} puan geriledi; faiz indirimi beklentisi kanalı." -f $cpiChg) }
        elseif ($cpiChg -ge 0.5) { & $addEvent 'inflation' -1 0.7 @{ Banka = -0.5; GYO = -1.0; Perakende = -0.5; İhracatçı = 0.3 } 'medium' ("Yıllık TÜFE {0} puan yükseldi; sıkı duruş uzayabilir." -f $cpiChg) }
    }
    $fundChg = & $val 'TR_FUNDING' 'Change'
    if ($null -ne $fundChg -and $fundChg -ne 0) {
        if ($fundChg -lt 0) { & $addEvent 'interest_rate' 1 0.8 @{ Banka = 1.0; GYO = 1.0; Holding = 0.5 } 'medium' ("TCMB fonlama {0} puan düştü (gevşeme döngüsü)." -f $fundChg) }
        else { & $addEvent 'interest_rate' -1 0.8 @{ Banka = -0.3; GYO = -1.0; Perakende = -0.5 } 'medium' ("TCMB fonlama {0} puan arttı (sıkılaşma)." -f $fundChg) }
    }

    # 2) cds_risk: CDS gunluk degisim (ulke risk primi).
    $cdsPct = & $val 'TR_CDS_5Y' 'ChangePct'
    if ($null -ne $cdsPct) {
        if ($cdsPct -le -2) { & $addEvent 'cds_risk' 1 0.6 @{ Banka = 0.7; Holding = 0.5 } 'short' ("CDS %{0} geriledi; risk primi iyileşiyor." -f [Math]::Round($cdsPct, 1)) }
        elseif ($cdsPct -ge 2) { & $addEvent 'cds_risk' -1 0.6 @{ Banka = -0.7; Holding = -0.5 } 'short' ("CDS %{0} yükseldi; risk primi bozuluyor." -f [Math]::Round($cdsPct, 1)) }
    }

    # 3) fx_pressure: USD/TRY gunluk degisim. Sert TL kaybi geneli baskilar ama
    #    ihracatciyi ayristirir; sakin kur ic-talep/finansallara alan acar.
    $fxPct = & $val 'USDTRY_Tcmb' 'ChangePct'
    if ($null -ne $fxPct) {
        if ($fxPct -ge 0.8) { & $addEvent 'fx_pressure' -1 ([Math]::Min(0.9, 0.5 + $fxPct / 4)) @{ İhracatçı = 0.8; Banka = -0.7; GYO = -0.7; Perakende = -0.6; Havacılık = -0.4 } 'short' ("USD/TRY %{0} yükseldi; kur baskısı." -f [Math]::Round($fxPct, 2)) }
        elseif ($fxPct -le 0.2) { & $addEvent 'fx_pressure' 1 0.4 @{ Banka = 0.4; GYO = 0.3; Perakende = 0.3 } 'short' 'Kur sakin; iç talep/finansallar lehine.' }
    }

    # 4) foreign_flow + domestic_flow (haftalik akislar; mn USD / mlr TL 4H).
    $ff = & $val 'FOREIGN_EQ_FLOW' 'Value'
    if ($null -ne $ff) {
        if ($ff -ge 100) { & $addEvent 'foreign_flow' 1 0.7 @{ Banka = 0.6; Holding = 0.5; Havacılık = 0.4 } 'medium' ("Yabancı 4H net alım {0} mn$ (BIST30 ağırlıklı etki)." -f $ff) }
        elseif ($ff -le -100) { & $addEvent 'foreign_flow' -1 0.7 @{ Banka = -0.6; Holding = -0.5 } 'medium' ("Yabancı 4H net satış {0} mn$." -f $ff) }
    }
    $tf = & $val 'TEFAS_EQ_FLOW' 'Value'
    if ($null -ne $tf) {
        if ($tf -ge 1) { & $addEvent 'domestic_flow' 1 0.5 @{} 'short' ("Yerli fon 4H net girişi {0} mlr TL." -f $tf) }
        elseif ($tf -le -1) { & $addEvent 'domestic_flow' -1 0.5 @{} 'short' ("Yerli fon 4H net çıkışı {0} mlr TL." -f $tf) }
    }

    # 5) global_risk: VIX + DXY birlikte (EM risk istahi).
    $vixPct = & $val 'VIX' 'ChangePct'; $dxyPct = & $val 'DXY' 'ChangePct'
    $globalSig = 0.0
    if ($null -ne $vixPct) { $globalSig -= [Math]::Sign($vixPct) * [Math]::Min(1.0, [Math]::Abs($vixPct) / 5) }
    if ($null -ne $dxyPct) { $globalSig -= [Math]::Sign($dxyPct) * [Math]::Min(1.0, [Math]::Abs($dxyPct) / 1.5) * 0.7 }
    if ($null -ne $vixPct -or $null -ne $dxyPct) {
        if ($globalSig -ge 0.4) { & $addEvent 'global_risk' 1 ([Math]::Min(0.8, $globalSig)) @{ Banka = 0.4; Havacılık = 0.3 } 'short' 'Küresel risk iştahı destekleyici (VIX/DXY geriliyor).' }
        elseif ($globalSig -le -0.4) { & $addEvent 'global_risk' -1 ([Math]::Min(0.8, [Math]::Abs($globalSig))) @{ Banka = -0.4; İhracatçı = 0.2 } 'short' 'Küresel risk iştahı bozuluyor (VIX/DXY yükseliyor).' }
    }

    # 6) commodity_oil: Brent gunluk. Yukselis TR enflasyon/cari icin negatif;
    #    havacilik/petrokimya girdi maliyeti, rafineri urun marji karisik.
    $oilPct = & $val 'BRENT' 'ChangePct'
    if ($null -ne $oilPct) {
        if ($oilPct -ge 1.5) { & $addEvent 'commodity_oil' -1 ([Math]::Min(0.7, 0.3 + $oilPct / 10)) @{ Havacılık = -0.8; Petrokimya = -0.6; Rafineri = 0.3; Enerji = 0.4 } 'medium' ("Brent %{0} yükseldi; enflasyon/cari denge baskısı." -f [Math]::Round($oilPct, 1)) }
        elseif ($oilPct -le -1.5) { & $addEvent 'commodity_oil' 1 0.5 @{ Havacılık = 0.8; Petrokimya = 0.5; Rafineri = -0.2 } 'medium' ("Brent %{0} geriledi; maliyet kanalı rahatlıyor." -f [Math]::Round($oilPct, 1)) }
    }

    # 7) market_trend: BIST100 gunluk yon (zayif teyit sinyali).
    $xuPct = & $val 'XU100' 'ChangePct'
    if ($null -ne $xuPct -and [Math]::Abs($xuPct) -ge 1.0) {
        & $addEvent 'market_trend' ([Math]::Sign($xuPct)) 0.3 @{} 'short' ("BIST100 günlük %{0}." -f [Math]::Round($xuPct, 1))
    }

    # 8) HABER KATMANI (data/macro_news.json — collect_macro_news.py, kural tabanli
    #    siniflandirici). Baslik siniflandirmasi kaba oldugundan: guven dosyadaki
    #    dusuk degerle sinirli, en fazla 4 haber olayi, yalniz son 36 saat.
    #    Ayni tipte veri-turevli olay varsa haber ATLANIR (veri > baslik).
    try {
        if ([string]::IsNullOrWhiteSpace($DataDir)) { $DataDir = Join-Path $PSScriptRoot 'data' }
        $newsPath = Join-Path $DataDir 'macro_news.json'
        if (Test-Path -LiteralPath $newsPath) {
            $newsDoc = Get-Content -LiteralPath $newsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $dataTypes = @{}
            foreach ($e in $events) { $dataTypes[[string]$e.Type] = $true }
            $newsAdded = 0
            foreach ($n in @(Get-ObjectPropertyValue -Object $newsDoc -Name 'items')) {
                if ($newsAdded -ge 4) { break }
                $ntype = [string](Get-ObjectPropertyValue -Object $n -Name 'eventType')
                if (-not $ntype -or $dataTypes.ContainsKey($ntype)) { continue }
                $ndate = $null
                try { $ndate = [datetime]::Parse([string](Get-ObjectPropertyValue -Object $n -Name 'date')) } catch { }
                if ($null -ne $ndate -and ((Get-Date).ToUniversalTime() - $ndate.ToUniversalTime()).TotalHours -gt 36) { continue }
                $ndir = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $n -Name 'direction')
                $nconf = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $n -Name 'confidence')
                if ($null -eq $ndir -or $ndir -eq 0) { continue }
                if ($null -eq $nconf -or $nconf -le 0 -or $nconf -gt 0.5) { $nconf = 0.35 }
                & $addEvent $ntype ([Math]::Sign($ndir)) $nconf @{} 'short' ("Haber: {0}" -f [string](Get-ObjectPropertyValue -Object $n -Name 'title'))
                $dataTypes[$ntype] = $true
                $newsAdded++
            }
        }
    }
    catch { }

    if ($events.Count -eq 0) { return $null }

    # Agirlikli toplam: her olay dir*conf; tip agirliklari esit (taksonomi zaten
    # secici esiklerle tetikleniyor). Skor [-1,1]'e normalize edilir.
    $raw = 0.0
    foreach ($e in $events) { $raw += $e.Direction * $e.Confidence }
    $score = [Math]::Max(-1.0, [Math]::Min(1.0, $raw / [Math]::Max(3.0, $events.Count)))
    $regime = if ($score -ge 0.15) { 'risk-on' } elseif ($score -le -0.15) { 'risk-off' } else { 'neutral' }
    $confidence = [Math]::Min(1.0, ($events | ForEach-Object { $_.Confidence } | Measure-Object -Average).Average * [Math]::Min(1.0, $events.Count / 4.0))

    $tilts = @{}
    foreach ($e in $events) {
        if ($null -eq $e.Sectors) { continue }
        foreach ($k in $e.Sectors.Keys) {
            $cur = if ($tilts.ContainsKey($k)) { [double]$tilts[$k] } else { 0.0 }
            $tilts[$k] = $cur + ([double]$e.Sectors[$k]) * $e.Confidence   # tilt isaretleri olay tanımında zaten yönlü
        }
    }
    $keys = @($tilts.Keys)
    foreach ($k in $keys) { $tilts[$k] = [Math]::Round([Math]::Max(-1.0, [Math]::Min(1.0, [double]$tilts[$k])), 2) }

    return [pscustomobject][ordered]@{
        Regime      = $regime
        Score       = [Math]::Round($score, 3)
        Confidence  = [Math]::Round($confidence, 2)
        Events      = $events.ToArray()
        SectorTilts = $tilts
        Note        = ('{0} olaydan türetildi (deterministik kural motoru; LLM yok).' -f $events.Count)
    }
}

function Add-MacroRegimeData {
    <#
        Rejim ciktisini hisselere SINIRLI skor ayari olarak isler:
        MacroRegimeAdjustment = clamp( 2*sektorTilt*conf + rejimTabani, [-3,+3] ).
        rejimTabani: risk-off'ta -1*conf (genel savunma), risk-on'da +0.5*conf.
        Sektor eslesmesi SectorTR uzerinden ANAHTAR KELIME ile yapilir (banka,
        gyo/gayrimenkul, holding, havacilik/ulastirma, petrokimya, enerji,
        perakende/ticaret). Eslesme yoksa yalniz rejim tabani uygulanir.
        Veri-kapili: $Regime null ise hicbir alan yazilmaz (ayar 0 kalir).
    #>
    [CmdletBinding()]
    param([object[]]$Stocks = @(), $Regime = $null)
    if ($null -eq $Regime) { return @($Stocks) }
    $conf = [double](Get-ObjectPropertyValue -Object $Regime -Name 'Confidence')
    $regimeName = [string](Get-ObjectPropertyValue -Object $Regime -Name 'Regime')
    $base = 0.0
    if ($regimeName -eq 'risk-off') { $base = -1.0 * $conf }
    elseif ($regimeName -eq 'risk-on') { $base = 0.5 * $conf }
    $tilts = Get-ObjectPropertyValue -Object $Regime -Name 'SectorTilts'
    $sectorKeyMap = @(
        @{ Pattern = 'banka|bank'; Key = 'Banka' },
        @{ Pattern = 'gayrimenkul|gyo|real estate'; Key = 'GYO' },
        @{ Pattern = 'holding'; Key = 'Holding' },
        @{ Pattern = 'havacılık|havacilik|ulaştırma|ulastirma|airline|transport'; Key = 'Havacılık' },
        @{ Pattern = 'petrokimya|kimya|chemical'; Key = 'Petrokimya' },
        @{ Pattern = 'enerji|energy|petrol'; Key = 'Enerji' },
        @{ Pattern = 'perakende|ticaret|retail'; Key = 'Perakende' }
    )
    foreach ($stock in $Stocks) {
        if ($null -eq $stock) { continue }
        $sec = ([string](Get-ObjectPropertyValue -Object $stock -Name 'SectorTR')).ToLowerInvariant()
        $tilt = 0.0
        if ($null -ne $tilts -and $sec) {
            foreach ($mapEntry in $sectorKeyMap) {
                if ($sec -match $mapEntry.Pattern -and $tilts.ContainsKey($mapEntry.Key)) { $tilt = [double]$tilts[$mapEntry.Key]; break }
            }
        }
        # Oto-ayar carpani (signal_config; varsayilan 1.0) -> cikis kurali karari.
        $adj = [Math]::Max(-3.0, [Math]::Min(3.0, (2.0 * $tilt * $conf) + $base)) * [double](Get-SignalConfig).MacroRegimeMult
        $adj = [Math]::Max(-3.0, [Math]::Min(3.0, $adj))
        $stock | Add-Member -NotePropertyName 'MacroRegimeAdjustment' -NotePropertyValue ([Math]::Round($adj, 2)) -Force
        $stock | Add-Member -NotePropertyName 'MacroRegimeLabel' -NotePropertyValue $regimeName -Force
    }
    return @($Stocks)
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

    # Eksik temel veri NÖTR degil HAFIF CEZALI (32): bilinmeyen degerleme genelde
    # zarar/aciklanmamis bilanco demektir; "nötr 45" dusuk-aciklamali hisseleri kayirir.
    if ($null -eq $Value) { return 32 }
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

    if ($null -eq $Value) { return 32 }   # eksik temel veri hafif cezali (bkz. F/K)
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

    # Sektor modeli: bankalarda FD/FAVOK tanimsiz, GYO'da yaniltici (NAV esas) ->
    # her ikisinde notr 50; GYO degerlemesi valueScore'da PB-agirlikli okunur.
    # TODO(sektor-modeli): holdingler TradingView'da 'Finance' etiketiyle gelir;
    # NAV-iskonto modeli icin ayri veri gerekir (bilinen sinir).
    if ($Sector -eq 'Finance' -or $Sector -eq 'Real Estate') { return 50 }
    if ($null -eq $Value) { return 32 }   # eksik temel veri hafif cezali (bkz. F/K)
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

    if ($null -eq $Value) { return 32 }   # eksik temel veri hafif cezali (bkz. F/K)
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
    # OLCEK DUZELTMESI: TradingView debt_to_equity_fq ORAN dondurur (0.02-3.7 araligi
    # PIT arsivinden dogrulandi), yuzde DEGIL. Eski esikler (50/100/200/400) yuzde
    # olcegi varsaydigi icin neredeyse tum hisseler 80-85 aliyor, yuksek kaldirac hic
    # cezalanmiyordu. Esikler oran olcegine cekildi: 0.5/1/2/4.
    if ($Value -le 0) { return 80 }
    if ($Value -le 0.5) { return 85 }
    if ($Value -le 1.0) { return 70 }
    if ($Value -le 2.0) { return 50 }
    if ($Value -le 4.0) { return 30 }
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
    param($Value, $ChangePct = $null)

    if ($null -eq $Value) { return 45 }
    # PS 5.1 guvenligi: parametre baglama/tip farklarina karsi acik double donusumu.
    $ChangePct = ConvertTo-DoubleOrNull $ChangePct
    # YON DUYARLILIGI (denetim #4): yuksek hacim yalniz YUKARI gunlerde "talep teyidi"dir.
    # Yuksek hacimli DUSUS dagitim sinyalidir — eskiden 92 puan aliyordu, artik cezali.
    if ($null -ne $ChangePct -and $ChangePct -lt 0) {
        if ($Value -ge 1.5) { return 25 }   # yogun dagitim
        if ($Value -ge 1.2) { return 35 }
        return 45                            # dusuk hacimli dusus: notr
    }
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
        # Yon duyarliligi (denetim #4): dusus gununde yuksek hacim teyit DEGIL, dagitimdir.
        VolumeConfirmed = $null -ne $Stock.RelativeVolume -and $Stock.RelativeVolume -ge 1.0 -and
            ($null -eq (Get-ObjectPropertyValue -Object $Stock -Name 'ChangePct') -or (Get-ObjectPropertyValue -Object $Stock -Name 'ChangePct') -ge 0)
        VolumeStrong = $null -ne $Stock.RelativeVolume -and $Stock.RelativeVolume -ge 1.5 -and
            ($null -eq (Get-ObjectPropertyValue -Object $Stock -Name 'ChangePct') -or (Get-ObjectPropertyValue -Object $Stock -Name 'ChangePct') -ge 0)
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

    $daysToEarnings = Get-ObjectPropertyValue -Object $Stock -Name 'DaysToNextEarnings'
    if ($null -ne $daysToEarnings -and $daysToEarnings -ge 0 -and $daysToEarnings -le 7) {
        [void]$flags.Add("Bilanço açıklamasına $daysToEarnings gün kaldı; olay riski")
    }
    if ([bool](Get-ObjectPropertyValue -Object $Stock -Name 'PreEarningsRunupActive')) {
        [void]$flags.Add('Bilanço öncesi ivme (anticipation): yaklaşan bilanço + güçlenen fiyat/hacim')
    }
    if ([bool](Get-ObjectPropertyValue -Object $Stock -Name 'SellTheNewsRisk')) {
        [void]$flags.Add('Sell-the-news riski: yeni güçlü bilanço sonrası geri verme eğilimi')
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

    # Bilanço olay riski: açıklamaya 0-7 gün kala oynaklık/sürpriz riski yüksek.
    $daysToEarnings = Get-ObjectPropertyValue -Object $Stock -Name 'DaysToNextEarnings'
    if ($null -ne $daysToEarnings -and $daysToEarnings -ge 0 -and $daysToEarnings -le 7) { $penalty += 4 }

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
        # --- Denetim #3 genisletmesi: yeni scanner kolonlari (indeks 54-69) ---
        ATR = ConvertTo-DoubleOrNull $mapped[54]
        ADX = ConvertTo-DoubleOrNull $mapped[55]
        EMA20 = ConvertTo-DoubleOrNull $mapped[56]
        EMA50 = ConvertTo-DoubleOrNull $mapped[57]
        EMA200 = ConvertTo-DoubleOrNull $mapped[58]
        High52W = ConvertTo-DoubleOrNull $mapped[59]
        Low52W = ConvertTo-DoubleOrNull $mapped[60]
        StochK = ConvertTo-DoubleOrNull $mapped[61]
        MFI = ConvertTo-DoubleOrNull $mapped[62]
        BBPower = ConvertTo-DoubleOrNull $mapped[63]
        GapPct = ConvertTo-DoubleOrNull $mapped[64]
        ROA = ConvertTo-DoubleOrNull $mapped[65]
        GrossMargin = ConvertTo-DoubleOrNull $mapped[66]
        OperatingMargin = ConvertTo-DoubleOrNull $mapped[67]
        NetMargin = ConvertTo-DoubleOrNull $mapped[68]
        CurrentRatio = ConvertTo-DoubleOrNull $mapped[69]
        # 52 hafta bandi turevleri (tum evren, sifir ek istek):
        Dist52WHighPct = if ($null -ne (ConvertTo-DoubleOrNull $mapped[2]) -and $null -ne (ConvertTo-DoubleOrNull $mapped[59]) -and (ConvertTo-DoubleOrNull $mapped[59]) -gt 0) { [Math]::Round(((ConvertTo-DoubleOrNull $mapped[2]) / (ConvertTo-DoubleOrNull $mapped[59]) - 1) * 100, 2) } else { $null }
        Range52PositionPct = if ($null -ne (ConvertTo-DoubleOrNull $mapped[2]) -and $null -ne (ConvertTo-DoubleOrNull $mapped[59]) -and $null -ne (ConvertTo-DoubleOrNull $mapped[60]) -and ((ConvertTo-DoubleOrNull $mapped[59]) - (ConvertTo-DoubleOrNull $mapped[60])) -gt 0) { [Math]::Round(((ConvertTo-DoubleOrNull $mapped[2]) - (ConvertTo-DoubleOrNull $mapped[60])) / ((ConvertTo-DoubleOrNull $mapped[59]) - (ConvertTo-DoubleOrNull $mapped[60])) * 100, 1) } else { $null }
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

    $body = $payload | ConvertTo-Json -Depth 8 -Compress
    try {
        $response = Invoke-WithRetry -OperationName 'Canlı BIST taraması' -MaxAttempts 3 -BaseDelaySec 2 -ScriptBlock {
            $result = Invoke-RestMethod `
                -Method Post `
                -Uri $script:TradingViewScannerUrl `
                -ContentType 'application/json' `
                -Headers $headers `
                -Body $body `
                -TimeoutSec $TimeoutSec `
                -ErrorAction Stop
            if ($null -eq $result.data -or $result.data.Count -eq 0) {
                throw 'Canlı BIST sorgusu boş sonuç döndürdü.'
            }
            return $result
        }
    }
    catch {
        throw "Canlı BIST verisi alınamadı: $($_.Exception.Message)"
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

    $usdTryRates = Get-TcmbUsdTryRates -Dates @($quarterEndDates) -TimeoutSec ([Math]::Min(3, $TimeoutSec)) -MaxElapsedSec 20

    # Enflasyon kiyaslamasini EVDS'ten dinamik tazele (anahtar yoksa statik kalir).
    # Bir kez cozulur; Add-QuarterlyFinancials her hisseye $script:InflationBenchmark'i iliştirir.
    $script:InflationBenchmark = Resolve-InflationBenchmark -AsOf (Get-Date) -TimeoutSec ([Math]::Min(8, $TimeoutSec))

    $enrichedStocks = foreach ($stock in $stocks) {
        Add-QuarterlyFinancials -Stock $stock -UsdTryRates $usdTryRates
    }
    $indexSnapshot = Get-BistIndexBenchmarks -TimeoutSec $TimeoutSec
    $macroEnrichedStocks = Add-MacroSectorBenchmarks -Stocks @($enrichedStocks) -IndexSnapshot $indexSnapshot

    # Bilanço zamanlaması (gün sayaçları + sürpriz proxy) ve veri-kalite bayraklari.
    # Skorlamadan once eklenir; DaysToNextEarnings risk cezasina, surpriz PEAD'e girer.
    $now = Get-Date
    $timedStocks = Add-EarningsTiming -Stocks @($macroEnrichedStocks) -AsOf $now
    $qualityStocks = Add-DataQualityAssessment -Stocks @($timedStocks) -AsOf $now

    return @($qualityStocks)
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

    # Holding modeli: config/holdings.json listesindeki hisseler (Add-HoldingFlag)
    # TradingView'da tutarsiz etiketlenir (bazi 'Finance', bazi baska). Bu bayrak
    # onlari TEK TIP ele alir: FD/FAVOK ve borc muaf (yapisal kaldirac normaldir),
    # degerleme PB-agirlikli (konsolide F/K tek-sefer istirak kar/zarariyla carpilir;
    # NAV/defter daha guvenilir). Bilinen sinir: gercek NAV iskontosu icin istirak
    # verisi gerekir (medium-term TODO). Etkin sektor Finance gibi muafiyet alir.
    $isHolding = [bool](Get-ObjectPropertyValue -Object $Stock -Name 'IsHolding')
    $effSector = if ($isHolding) { 'Finance' } else { $Stock.Sector }

    $peScore = Get-PEComponentScore -Value $Stock.PE
    $pbScore = Get-PBComponentScore -Value $Stock.PB
    $evEbitda = Get-ObjectPropertyValue -Object $Stock -Name 'EvEbitda'
    $evEbitdaScore = Get-EvEbitdaComponentScore -Value $evEbitda -Sector $effSector
    $valueScore = if ($isHolding) {
        (0.20 * $peScore) + (0.80 * $pbScore)
    }
    elseif ($Stock.Sector -eq 'Finance') {
        (0.35 * $peScore) + (0.65 * $pbScore)
    }
    elseif ($Stock.Sector -eq 'Real Estate') {
        # GYO sektor modeli: degerleme NAV/defter uzerinden okunur; FD/FAVOK
        # kira/gelistirme karisik yapida yaniltici oldugundan katilmaz.
        (0.20 * $peScore) + (0.80 * $pbScore)
    }
    else {
        (0.45 * $peScore) + (0.25 * $pbScore) + (0.30 * $evEbitdaScore)
    }

    $roeScore = Get-ROEComponentScore -Value $Stock.ROE
    $debtScore = Get-DebtComponentScore -Value $Stock.DebtToEquity -Sector $effSector
    $qualityScore = (0.75 * $roeScore) + (0.25 * $debtScore)
    $earningsScore = Get-EarningsComponentScore -Stock $Stock

    $rsiScore = Get-RSIComponentScore -Value $Stock.RSI
    $weekScore = Get-PerformanceComponentScore -Value $Stock.PerfWeek -Multiplier 3
    $monthScore = Get-PerformanceComponentScore -Value $Stock.PerfMonth -Multiplier 2
    $macdScore = Get-MacdComponentScore -Stock $Stock
    $volumeConfirmationScore = Get-VolumeConfirmationComponentScore -Value $Stock.RelativeVolume -ChangePct (Get-ObjectPropertyValue -Object $Stock -Name 'ChangePct')
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
    # REJIME GORE SINIRLI agirlik modulasyonu: risk-off'ta momentumdan kalite/
    # degere, risk-on'da tersine KUCUK kayma (±0.04; deltalar sifir toplamli,
    # yeniden normalizasyon gerekmez). Buyuk agirlik oynamak backtest kaniti
    # ister; bu kucuk ve simetrik egim savunmaci varsayilan olarak guvenlidir.
    $mrLabelW = [string](Get-ObjectPropertyValue -Object $Stock -Name 'MacroRegimeLabel')
    if ($mrLabelW -in @('risk-on', 'risk-off')) {
        $wShift = if ($mrLabelW -eq 'risk-off') { -0.04 } else { 0.04 }
        $weights = @{
            Trend = $weights.Trend; Value = [Math]::Max(0.0, $weights.Value - $wShift / 2)
            Quality = [Math]::Max(0.0, $weights.Quality - $wShift / 2)
            Earnings = $weights.Earnings; Momentum = [Math]::Max(0.0, $weights.Momentum + $wShift)
            Liquidity = $weights.Liquidity; MacroSector = $weights.MacroSector
        }
    }
    $riskPenalty = Get-RiskPenalty -Stock $Stock
    $rawScore = `
        ($trendScore * $weights.Trend) + `
        ($valueScore * $weights.Value) + `
        ($qualityScore * $weights.Quality) + `
        ($earningsScore * $weights.Earnings) + `
        ($momentumScore * $weights.Momentum) + `
        ($liquidityScore * $weights.Liquidity) + `
        ($macroSectorScore * $weights.MacroSector)

    $earningsTimingAdjustment = Get-EarningsTimingAdjustment -Stock $Stock
    # Akilli para ayari: yabanci saklama degisimi + icsel islem sinyali.
    # Sinirli [-6,+6] ve veri-kapili (alanlar islenmemisse 0 — davranis degismez).
    $smartMoneyAdjustment = Get-SmartMoneyAdjustment -Stock $Stock
    # Makro rejim ayari: Add-MacroRegimeData'nin isledigi sinirli [-3,+3] deger.
    # Alan yoksa 0 (veri-kapili; rejim motoru calismadiysa davranis degismez).
    $macroRegimeAdjustment = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $Stock -Name 'MacroRegimeAdjustment')
    if ($null -eq $macroRegimeAdjustment) { $macroRegimeAdjustment = 0.0 }
    $score = [Math]::Round((Limit-Value -Value ($rawScore - $riskPenalty + $earningsTimingAdjustment + $smartMoneyAdjustment + $macroRegimeAdjustment)), 1)
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
    if ($smartMoneyAdjustment -ne 0) {
        $smDetail = @()
        $smChg = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $Stock -Name 'ForeignChg1wBps')
        if ($null -ne $smChg -and [Math]::Abs($smChg) -ge 0.10) { $smDetail += ('yabancı oran 1H {0}{1} puan' -f $(if ($smChg -gt 0) { '+' } else { '' }), [Math]::Round($smChg, 2)) }
        $smIns = [string](Get-ObjectPropertyValue -Object $Stock -Name 'InsiderSignal')
        if ($smIns -eq '+') { $smDetail += 'içsel işlem: alım' } elseif ($smIns -eq '-') { $smDetail += 'içsel işlem: satım' }
        $explanation += [Environment]::NewLine + ('Akıllı para ayarı: {0}{1} puan ({2}).' -f $(if ($smartMoneyAdjustment -gt 0) { '+' } else { '' }), [Math]::Round($smartMoneyAdjustment, 1), ($smDetail -join '; '))
    }
    if ($macroRegimeAdjustment -ne 0) {
        $mrLabel = [string](Get-ObjectPropertyValue -Object $Stock -Name 'MacroRegimeLabel')
        $explanation += [Environment]::NewLine + ('Makro rejim ayarı: {0}{1} puan (rejim: {2}).' -f $(if ($macroRegimeAdjustment -gt 0) { '+' } else { '' }), [Math]::Round($macroRegimeAdjustment, 1), $mrLabel)
    }

    $properties = [ordered]@{}
    foreach ($property in $Stock.PSObject.Properties) {
        if ($property.Name -notin @(
                'Score', 'Signal', 'RiskLevel', 'RiskFlags', 'Explanation',
                'TrendScore', 'ValueScore', 'QualityScore', 'EarningsScore', 'MomentumScore',
                'LiquidityScore', 'MacroSectorScore', 'ConfirmationLabel', 'ConfirmationScore',
                'TechnicalPassCount', 'TechnicalCheckCount', 'AllTechnicalConfirmed', 'EntryNote',
                'FailedConfirmations', 'RiskPenalty', 'SmartMoneyAdjustment', 'MacroRegimeAdjustment', 'Strategy'
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
    $properties.SmartMoneyAdjustment = [Math]::Round($smartMoneyAdjustment, 1)
    $properties.MacroRegimeAdjustment = [Math]::Round($macroRegimeAdjustment, 1)
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
        $response = Invoke-WithRetry -OperationName 'Yahoo haftalik kapanis' -MaxAttempts 2 -BaseDelaySec 1 -ScriptBlock {
            Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec $TimeoutSec -ErrorAction Stop
        }
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

function Get-YahooDailyCloseSeries {
    <#
        Tarih-hizali gunluk kapanis serisi: {Date, Close} dizisi (eskiden yeniye).
        Olay calismasi (bilanco tarihi etrafindaki pencere) ve ileride gercek
        fiyatli PEAD icin. Kapanisi bos olan gunler atlanir ama tarih hizasi
        timestamp ile korunur. Hata/eksik veride bos dizi doner.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Symbol,
        [string]$Range = '1y',
        [int]$TimeoutSec = 12,
        [switch]$AsRawTicker   # BIST disi makro semboller icin .IS ekleme (USDTRY=X, ^VIX, DX-Y.NYB)
    )

    $ticker = if ($AsRawTicker) { $Symbol } else { Get-YahooFinanceSymbol -Symbol $Symbol }
    if ([string]::IsNullOrWhiteSpace($ticker)) { return @() }

    # Dayaniklilik: kosu-ici bellek cache (ayni sembol+aralik tekrar istenmez) +
    # istekler arasi kucuk throttle (429 riskini dusurur). Runner ephemeral;
    # dogru cache katmani disk degil bellek.
    if (-not (Get-Variable -Name YahooSeriesCache -Scope Script -ErrorAction SilentlyContinue)) { $script:YahooSeriesCache = @{} }
    $cacheKey = "$ticker|$Range"
    if ($script:YahooSeriesCache.ContainsKey($cacheKey)) { return @($script:YahooSeriesCache[$cacheKey]) }
    Start-Sleep -Milliseconds 150

    $url = 'https://query1.finance.yahoo.com/v8/finance/chart/{0}?range={1}&interval=1d' -f ([Uri]::EscapeDataString($ticker)), $Range
    $headers = @{
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        'Accept' = 'application/json'
    }

    try {
        $response = Invoke-WithRetry -OperationName 'Yahoo gunluk kapanis' -MaxAttempts 2 -BaseDelaySec 1 -ScriptBlock {
            Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec $TimeoutSec -ErrorAction Stop
        }
    }
    catch {
        # 429 (rate limit) icin tek ek bekleme + son deneme; digerinde bos don.
        $is429 = ($_.Exception.Message -match '429') -or ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 429)
        if (-not $is429) { return @() }
        Start-Sleep -Seconds 3
        try { $response = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec $TimeoutSec -ErrorAction Stop }
        catch { return @() }
    }

    $chart = Get-ObjectPropertyValue -Object $response -Name 'chart'
    $results = @(Get-ObjectPropertyValue -Object $chart -Name 'result')
    if ($results.Count -eq 0 -or $null -eq $results[0]) { return @() }

    $timestamps = @(Get-ObjectPropertyValue -Object $results[0] -Name 'timestamp')
    $indicators = Get-ObjectPropertyValue -Object $results[0] -Name 'indicators'
    $quotes = @(Get-ObjectPropertyValue -Object $indicators -Name 'quote')
    if ($quotes.Count -eq 0 -or $null -eq $quotes[0]) { return @() }
    $closeValues = @(Get-ObjectPropertyValue -Object $quotes[0] -Name 'close')
    if ($timestamps.Count -eq 0 -or $closeValues.Count -ne $timestamps.Count) { return @() }

    $series = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $timestamps.Count; $i++) {
        $close = ConvertTo-DoubleOrNull $closeValues[$i]
        $date = ConvertFrom-UnixSecondsOrNull $timestamps[$i]
        if ($null -ne $close -and $close -gt 0 -and $null -ne $date) {
            [void]$series.Add([pscustomobject]@{ Date = $date; Close = [double]$close })
        }
    }

    $seriesResult = @($series.ToArray())
    if ($seriesResult.Count -gt 0) { $script:YahooSeriesCache[$cacheKey] = $seriesResult }
    return $seriesResult
}

function Get-YahooDailyOhlcSeries {
    <#
        Tarih-hizali gunluk {Date, Close, Volume} serisi. Geriye-donuk backtest'te
        point-in-time likidite (TL hacim) ve teknik gosterge kurulumu icin.
        Hata/eksik veride bos dizi.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Symbol,
        [string]$Range = '3y',
        [int]$TimeoutSec = 12,
        [switch]$AsRawTicker
    )

    $ticker = if ($AsRawTicker) { $Symbol } else { Get-YahooFinanceSymbol -Symbol $Symbol }
    if ([string]::IsNullOrWhiteSpace($ticker)) { return @() }
    $url = 'https://query1.finance.yahoo.com/v8/finance/chart/{0}?range={1}&interval=1d' -f ([Uri]::EscapeDataString($ticker)), $Range
    $headers = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'; 'Accept' = 'application/json' }

    try {
        $response = Invoke-WithRetry -OperationName 'Yahoo OHLC' -MaxAttempts 2 -BaseDelaySec 1 -ScriptBlock {
            Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec $TimeoutSec -ErrorAction Stop
        }
    }
    catch { return @() }

    $chart = Get-ObjectPropertyValue -Object $response -Name 'chart'
    $results = @(Get-ObjectPropertyValue -Object $chart -Name 'result')
    if ($results.Count -eq 0 -or $null -eq $results[0]) { return @() }
    $timestamps = @(Get-ObjectPropertyValue -Object $results[0] -Name 'timestamp')
    $indicators = Get-ObjectPropertyValue -Object $results[0] -Name 'indicators'
    $quotes = @(Get-ObjectPropertyValue -Object $indicators -Name 'quote')
    if ($quotes.Count -eq 0 -or $null -eq $quotes[0]) { return @() }
    $closeValues = @(Get-ObjectPropertyValue -Object $quotes[0] -Name 'close')
    $volumeValues = @(Get-ObjectPropertyValue -Object $quotes[0] -Name 'volume')
    $highValues = @(Get-ObjectPropertyValue -Object $quotes[0] -Name 'high')
    $lowValues = @(Get-ObjectPropertyValue -Object $quotes[0] -Name 'low')
    if ($timestamps.Count -eq 0 -or $closeValues.Count -ne $timestamps.Count) { return @() }

    $series = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $timestamps.Count; $i++) {
        $close = ConvertTo-DoubleOrNull $closeValues[$i]
        $date = ConvertFrom-UnixSecondsOrNull $timestamps[$i]
        $vol = if ($i -lt $volumeValues.Count) { ConvertTo-DoubleOrNull $volumeValues[$i] } else { $null }
        $hi = if ($i -lt $highValues.Count) { ConvertTo-DoubleOrNull $highValues[$i] } else { $null }
        $lo = if ($i -lt $lowValues.Count) { ConvertTo-DoubleOrNull $lowValues[$i] } else { $null }
        if ($null -ne $close -and $close -gt 0 -and $null -ne $date) {
            # H/L eksikse kapanisa duser (yapi dedektorleri bos deger istemez).
            if ($null -eq $hi -or $hi -le 0) { $hi = $close }
            if ($null -eq $lo -or $lo -le 0) { $lo = $close }
            [void]$series.Add([pscustomobject]@{ Date = $date; Close = [double]$close; High = [double]$hi; Low = [double]$lo; Volume = if ($null -ne $vol) { [double]$vol } else { 0.0 } })
        }
    }

    return @($series.ToArray())
}

function Get-PriceStructureSignal {
    <#
        Fiyat YAPISI dedektoru (Darvas kutusu + basitlestirilmis Wyckoff) — SAF fonksiyon.

        Girdi: eskiden yeniye gunluk {Date, Close, High, Low, Volume} serisi
        (Get-YahooDailyOhlcSeries ciktisi). En az 60 bar ister; yoksa $null.

        DURUSTLUK: Wyckoff tam metodolojisi hacim/yayilim okumasi gerektirir;
        buradaki, uc kosullu (aralik daralmasi + hacim sonmesi + dip bolgesi)
        MUHAFAZAKAR bir 'birikim adayi' sezgiselidir. Karar mantigina girmez;
        yalniz panelde 'Yapisal' sinyal grubunda GOSTERILIR.

        Oncelik sirasi: Darvas kirilimi > Wyckoff spring > Wyckoff birikim >
        Darvas sikismasi. Ilk eslesen doner: {Type, Note}; hicbiri yoksa $null.
    #>
    [CmdletBinding()]
    param([object[]]$Series)

    $s = @($Series | Where-Object { $null -ne $_ })
    if ($s.Count -lt 60) { return $null }
    if ($s.Count -gt 120) { $s = @($s[($s.Count - 120)..($s.Count - 1)]) }
    $n = $s.Count
    $today = $s[$n - 1]

    # --- Darvas kutusu: bugun haric son 25 bar ---
    $boxLen = 25
    $box = @($s[($n - 1 - $boxLen)..($n - 2)])
    $boxTop = ($box | ForEach-Object { $_.High } | Measure-Object -Maximum).Maximum
    $boxBottom = ($box | ForEach-Object { $_.Low } | Measure-Object -Minimum).Minimum
    $boxVolAvg = ($box | ForEach-Object { $_.Volume } | Measure-Object -Average).Average
    $boxWidth = if ($boxBottom -gt 0) { ($boxTop - $boxBottom) / $boxBottom } else { [double]::MaxValue }

    if ($boxWidth -le 0.12 -and $today.Close -gt $boxTop) {
        $volNote = ''
        if ($boxVolAvg -gt 0 -and $today.Volume -ge 1.3 * $boxVolAvg) { $volNote = ', hacim teyitli' }
        return [pscustomobject]@{
            Type = 'Darvas kırılımı'
            Note = ('{0} günlük kutu (%{1} genişlik) yukarı kırıldı{2}' -f $boxLen, [Math]::Round(100 * $boxWidth, 1), $volNote)
        }
    }

    # --- Wyckoff spring: son 5 barda onceki 40-bar dibinin altina sarkip geri kapanis ---
    if ($n -ge 46) {
        $priorWin = @($s[($n - 46)..($n - 6)])
        $priorLow = ($priorWin | ForEach-Object { $_.Low } | Measure-Object -Minimum).Minimum
        $recent5 = @($s[($n - 5)..($n - 1)])
        $recentLow = ($recent5 | ForEach-Object { $_.Low } | Measure-Object -Minimum).Minimum
        if ($priorLow -gt 0 -and $recentLow -lt 0.995 * $priorLow -and $today.Close -gt $priorLow) {
            return [pscustomobject]@{
                Type = 'Wyckoff spring adayı'
                Note = ('Dip {0} altına sarkıp üzerinde kapandı (yanlış kırılım geri alımı)' -f [Math]::Round($priorLow, 2))
            }
        }
    }

    # --- Wyckoff birikim adayi: aralik daralmasi + hacim sonmesi + dip bolgesi ---
    $w = @($s[($n - 60)..($n - 1)])
    $first20 = @($w[0..19]); $last20 = @($w[40..59])
    $r1 = (($first20 | ForEach-Object { $_.High } | Measure-Object -Maximum).Maximum) - (($first20 | ForEach-Object { $_.Low } | Measure-Object -Minimum).Minimum)
    $r2 = (($last20 | ForEach-Object { $_.High } | Measure-Object -Maximum).Maximum) - (($last20 | ForEach-Object { $_.Low } | Measure-Object -Minimum).Minimum)
    $v1 = ($first20 | ForEach-Object { $_.Volume } | Measure-Object -Average).Average
    $v2 = ($last20 | ForEach-Object { $_.Volume } | Measure-Object -Average).Average
    $allHigh = ($s | ForEach-Object { $_.High } | Measure-Object -Maximum).Maximum
    $allLow = ($s | ForEach-Object { $_.Low } | Measure-Object -Minimum).Minimum
    $pos = if (($allHigh - $allLow) -gt 0) { ($today.Close - $allLow) / ($allHigh - $allLow) } else { 1.0 }
    if ($r1 -gt 0 -and $r2 -le 0.6 * $r1 -and $v1 -gt 0 -and $v2 -le 0.75 * $v1 -and $pos -le 0.5) {
        return [pscustomobject]@{
            Type = 'Wyckoff birikim adayı'
            Note = ('Aralık daraldı (%{0}), hacim söndü (%{1}), dip bölgesinde' -f [Math]::Round(100 * $r2 / $r1, 0), [Math]::Round(100 * $v2 / $v1, 0))
        }
    }

    # --- Darvas sikismasi: dar kutu icinde bekleyis (kirilim yok) ---
    if ($boxWidth -le 0.08 -and $today.Close -ge $boxBottom -and $today.Close -le $boxTop) {
        return [pscustomobject]@{
            Type = 'Darvas kutusu'
            Note = ('{0} günlük dar sıkışma (%{1}); kırılım izlenmeli — kutu {2}-{3}' -f $boxLen, [Math]::Round(100 * $boxWidth, 1), [Math]::Round($boxBottom, 2), [Math]::Round($boxTop, 2))
        }
    }

    return $null
}

function Get-PriceStructureSignals {
    <#
        En yuksek skorlu -Top hisse icin Yahoo gunluk H/L serisi cekip yapi
        sinyallerini toplar. Best-effort: veri alinamayan sembol atlanir.
        Cikti: @({Symbol, Type, Note}) — panelde technicalSignals.structures.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Stocks = @(),
        [int]$Top = 20,
        [int]$TimeoutSec = 12
    )
    $results = @()
    $cands = @($Stocks |
        Where-Object { -not [string]::IsNullOrWhiteSpace((Get-ObjectPropertyValue -Object $_ -Name 'Symbol')) } |
        Sort-Object @{ Expression = { $v = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $_ -Name 'Score'); if ($null -ne $v) { $v } else { -1 } }; Descending = $true } |
        Select-Object -First $Top)
    foreach ($stock in $cands) {
        $sym = [string](Get-ObjectPropertyValue -Object $stock -Name 'Symbol')
        try {
            Start-Sleep -Milliseconds 150
            $series = @(Get-YahooDailyOhlcSeries -Symbol $sym -Range '6mo' -TimeoutSec $TimeoutSec)
            $sig = Get-PriceStructureSignal -Series $series
            if ($null -ne $sig) {
                $results += [pscustomobject]@{ Symbol = $sym; Type = [string]$sig.Type; Note = [string]$sig.Note }
            }
        }
        catch { continue }
    }
    return @($results)
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

function Get-InstantEntryExitDecision {
    <#
        Anlik firsat portfoyu pozisyonu icin cikis karari (YALNIZ bu portfoye ozel;
        model portfoyler aylik kalir). Doner: $null = tut; aksi halde Kind/Reason.
        Sira: once zarar-kes (stop), sonra kar-al (take-profit), sonra iz-suren stop
        (trailing — yalniz tepe kazanc TrailingStopPct'i gectiyse devreye girer ve
        tepeden o kadar geri verince satar).
        Rules: StopLossPct (negatif), TakeProfitPct (pozitif), TrailingStopPct (pozitif).
    #>
    param($Holding, $Rules)

    if ($null -eq $Rules) { return $null }
    $gainPct = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $Holding -Name 'UnrealizedGainPct')
    if ($null -eq $gainPct) { return $null }
    $stop = [double]$Rules.StopLossPct
    $take = [double]$Rules.TakeProfitPct
    $trail = [double]$Rules.TrailingStopPct

    if ($gainPct -le $stop) {
        return [pscustomobject]@{ Kind = 'Stop'; Reason = ('Zarar kes: getiri %{0:N1} <= stop %{1:N1}.' -f $gainPct, $stop) }
    }
    if ($gainPct -ge $take) {
        return [pscustomobject]@{ Kind = 'TakeProfit'; Reason = ('Kar al: getiri %{0:N1} >= hedef %{1:N1}.' -f $gainPct, $take) }
    }
    if ($trail -gt 0) {
        $peakGain = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $Holding -Name 'PeakGainPct')
        $currentPrice = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $Holding -Name 'CurrentPrice')
        $peakPrice = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $Holding -Name 'PeakPrice')
        if ($null -ne $peakGain -and $null -ne $currentPrice -and $null -ne $peakPrice -and $peakPrice -gt 0) {
            $dropFromPeak = (($currentPrice - $peakPrice) / $peakPrice) * 100.0
            if ($peakGain -ge $trail -and $dropFromPeak -le (-1.0 * $trail)) {
                return [pscustomobject]@{ Kind = 'Trailing'; Reason = ('Iz-suren stop: tepe kazanc %{0:N1}, tepeden %{1:N1} geri verildi.' -f $peakGain, [Math]::Abs($dropFromPeak)) }
            }
        }
    }
    return $null
}

function Get-InstantEntryCashTL {
    <#
        Anlik firsat portfoyu KAPALI DONGU nakit durumu (100k sermaye + 5k/gun).
        Nakit, degismez islem defterinden TURETILIR (idempotent; ayni gun tekrar
        kosulsa sonuc degismez):
            Nakit = Baslangic sermayesi - kumulatif ALIM(AmountTL) + kumulatif SATIS(AmountTL)
        Satis hasilati (anapara + KAR) nakte doner -> kazanilan karla tekrar girilebilir.
        Nakit 0'a inince yeni alim yapilamaz (100k asilmaz) ta ki bir satis nakti
        serbest birakana kadar. Doner: Cash / TotalBought / TotalSoldProceeds / RealizedNote.
    #>
    [CmdletBinding()]
    param(
        [double]$InitialCapitalTL = 100000,
        [object[]]$Transactions = @()
    )
    $buys = 0.0; $sells = 0.0
    foreach ($t in @($Transactions)) {
        $act = [string](Get-ObjectPropertyValue -Object $t -Name 'Action')
        $amt = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $t -Name 'AmountTL')
        if ($null -eq $amt) { continue }
        if ($act -eq 'AL') { $buys += [double]$amt }
        elseif ($act -eq 'SAT') { $sells += [double]$amt }
    }
    return [pscustomobject][ordered]@{
        CashTL              = [Math]::Round($InitialCapitalTL - $buys + $sells, 2)
        TotalBoughtTL       = [Math]::Round($buys, 2)
        TotalSoldProceedsTL = [Math]::Round($sells, 2)
    }
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
    $definitions = @(
        [pscustomobject][ordered]@{
            Id = 'Dengeli'
            Name = 'Dengeli Model Portföy'
            Strategy = 'Dengeli'
            RankBy = 'Score'
            Description = 'Makro/sektör bağlamı, trend, değerleme, kalite, bilanço, momentum ve likiditeyi dengeli ağırlıklarla bir arada değerlendirir.'
        },
        [pscustomobject][ordered]@{
            Id = 'Deger'
            Name = 'Değer Model Portföyü'
            Strategy = 'Değer'
            RankBy = 'Score'
            Description = 'F/K, PD/DD ve finans dışı hisselerde FD/FAVÖK ağırlıklı değerleme puanını öne çıkarır; kârlılık, makro/sektör bağlamı, likidite ve risk tabanı değer tuzağı riskini azaltmak için korunur.'
        },
        [pscustomobject][ordered]@{
            Id = 'Momentum'
            Name = 'Momentum Model Portföyü'
            Strategy = 'Momentum'
            RankBy = 'Score'
            Description = 'Trend, 200 günlük ortalama, MACD, RSI ve hacim teyidini öne çıkarır; yalnızca ortak kârlılık, büyüklük, makro/sektör, likidite ve risk koşullarını geçen hisseleri kullanır.'
        },
        [pscustomobject][ordered]@{
            Id = 'Kalite'
            Name = 'Kalite Model Portföyü'
            Strategy = 'Kalite'
            RankBy = 'Score'
            Description = 'ROE, bilanço puanı, FAVÖK sürekliliği ve kâr kalitesini öne çıkarır; fiyat, makro/sektör ve likidite koşullarını ortak koruma filtresi olarak uygular.'
        },
        [pscustomobject][ordered]@{
            Id = 'RFS100'
            Name = 'RFS100 Model Portföyü'
            Strategy = 'Dengeli'
            RankBy = 'RawFactorScore100'
            Description = 'Backtest bulgusuna dayanır: temel/likidite uygunluk filtresini geçen hisseleri, Get-BistScore eşik puanlaması yerine ham teknik faktörlerin (RSI, MACD, SMA mesafeleri, momentum, hacim, oynaklık) kesitsel z-skor karışımı olan RawFactorScore100 ile sıralar. Walk-forward testlerde bu sıralama botun skorunun ~2 katı bilgi katsayısı (IC) verdi.'
        },
        [pscustomobject][ordered]@{
            Id = 'RiskDengeli'
            Name = 'Risk Dengeli Model Portföyü'
            Strategy = 'Dengeli'
            RankBy = 'RiskAdjusted'
            WeightingMethod = 'InverseVolatility'
            MinWeightPct = 8.0
            MaxWeightPct = 28.0
            Description = 'Normal model portföyleri bozmadan ayrı izlenen risk dengeli portföydür. Seçim Dengeli skorla yapılır; ağırlıklar günlük oynaklık tersine göre dağıtılır ve tek hisse riski için min/max ağırlık sınırları uygulanır.'
        }
    )

    # VERI-KAPILI 7. portfoy: bot KENDI OGRENDIGI faktor agirliklariyla kurar.
    # Yalniz ogrenilmis agirlik dosyasi (data/learned_factor_weights.json) varken
    # listeye eklenir; yoksa hic olusturulmaz (yeterli PIT verisi birikip ceyreklik
    # oto-kalibrasyon calisana kadar bekler — kullanici istegi: "yeterli veri/ogrenme
    # oldugunda olustur"). RFS100 STATIK temel cizgiyi korur; bu portfoy ogrenilmis
    # agirliklari kullanir, ikisi yan yana izlenerek ogrenmenin katkisi olculur.
    if (Get-LearnedFactorWeights) {
        $definitions += [pscustomobject][ordered]@{
            Id = 'OgrenenAlgoritma'
            Name = 'Öğrenen Algoritma Model Portföyü'
            Strategy = 'Dengeli'
            RankBy = 'LearnedFactorScore100'
            RequiresLearnedWeights = $true
            Description = 'Botun çeyreklik walk-forward IC oto-kalibrasyonuyla KENDİ ÖĞRENDİĞİ faktör ağırlıklarını (data/learned_factor_weights.json) kullanarak kuran 5 hisselik portföy. Yalnızca yeterli PIT verisi birikip öğrenme gerçekleştiğinde oluşturulur. RFS100 statik backtest ağırlıklarını korurken bu portföy öğrenilmiş ağırlıkları uygular; ikisi yan yana izlenerek öğrenmenin gerçek alfa katkısı ölçülebilir. Temel/likidite uygunluk filtresi ve sektör çeşitlendirmesi RFS100 ile aynıdır.'
        }
    }

    return $definitions
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

    # Veri kalitesi kapisi: kritik sorunlu (gecersiz fiyat / cok dusuk likidite)
    # hisseler model portfoye alinmaz. Alan yoksa (eski state) gecirilir.
    $dataQualityOk = Get-ObjectPropertyValue -Object $Stock -Name 'DataQualityOk'
    if ($null -ne $dataQualityOk -and -not [bool]$dataQualityOk) {
        return $false
    }

    # Asiri volatilite kapisi: gunluk oynakligi cok yuksek hisseler tek-isim
    # riskini buyutur; model portfoye alinmaz (risk-bilincli secim).
    $volD = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $Stock -Name 'VolatilityD')
    if ($null -ne $volD -and $volD -gt 8) {
        return $false
    }

    $evEbitda = Get-ObjectPropertyValue -Object $Stock -Name 'EvEbitda'
    $latestEbitda = Get-ObjectPropertyValue -Object $Stock -Name 'LatestEbitdaUSDMn'
    $positiveEbitdaCount = Get-ObjectPropertyValue -Object $Stock -Name 'PositiveEbitdaQuarterCount'
    $macdLine = Get-ObjectPropertyValue -Object $Stock -Name 'MacdLine'
    $macdSignal = Get-ObjectPropertyValue -Object $Stock -Name 'MacdSignal'
    $macdHistogram = Get-ObjectPropertyValue -Object $Stock -Name 'MacdHistogram'

    $roeOk = $null -eq $Stock.ROE -or $Stock.ROE -ge 10
    # GYO/holdingde FD/FAVOK filtre kriteri olarak anlamsiz (banka gibi muaf).
    $isHoldingElig = [bool](Get-ObjectPropertyValue -Object $Stock -Name 'IsHolding')
    $valueOk = $isHoldingElig -or $Stock.Sector -in @('Finance', 'Real Estate') -or $null -eq $evEbitda -or ($evEbitda -gt 0 -and $evEbitda -le 12)
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

function Get-StrategySelectionScore {
    <#
        Portfoy SECIMI icin strateji-spesifik siralama anahtari. Rapordaki genel
        Score'a DOKUNMAZ; yalnizca her stratejiyi KENDI bileseni etrafinda ayristirir.

        Sorun: onceden tum stratejiler dogrudan Score ile siralaniyordu. Score,
        strateji-bagimsiz ve her stratejide yuksek-agirlikli MacroSector + Earnings
        bilesenlerince dominate edildigi icin Dengeli=Momentum ve Deger=Kalite
        portfoyleri ayni hisseleri seciyordu. Bu fonksiyon stratejinin kendi
        eksenine ~%85 agirlik vererek secimi gercekten ayristirir; %15 genel Score
        kalite tabani olarak korunur.
    #>
    param($Stock, [string]$Strategy)
    $get = {
        param($Name)
        $v = Get-ObjectPropertyValue -Object $Stock -Name $Name
        if ($null -eq $v) { 0.0 } else { [double]$v }
    }
    $score = & $get 'Score'
    $trend = & $get 'TrendScore'
    $value = & $get 'ValueScore'
    $quality = & $get 'QualityScore'
    $earnings = & $get 'EarningsScore'
    $momentum = & $get 'MomentumScore'
    switch ($Strategy) {
        'Momentum' { return (0.55 * $momentum) + (0.30 * $trend) + (0.15 * $score) }
        'Değer' { return (0.60 * $value) + (0.25 * $earnings) + (0.15 * $score) }
        'Kalite' { return (0.55 * $quality) + (0.30 * $earnings) + (0.15 * $score) }
        default { return $score }   # Dengeli: dengeli genel skor
    }
}

function Get-AdjustmentImpactLog {
    <#
        OLCUM (karar etkisi YOK): akilli-para + makro-rejim ayarlarinin secimi
        GERCEKTEN degistirip degistirmedigini olcer. Dengeli ekseninde (secim =
        Score, ayarlarin tam kaldiraci burada) ayarli vs AYARSIZ ilk-N secimi
        karsilastirir. Ayarsiz skor stored alanlardan REKONSTRUKTE edilir:
        unadjusted = Score - SmartMoneyAdjustment - MacroRegimeAdjustment
        (yeniden skorlama YOK, tam ve ucuz). Sektor tavani her ikisine uygulanir.

        Doner: { asOf, count, actual[], shadow[], added[], dropped[], changed(bool),
                 detail[] }. added = ayarlarin ekledigi isimler; dropped = ayarlarin
                 disladigi isimler. Bu, IC'den once konusan erken bir isaret verir.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Stocks = @(),
        [int]$Count = 5,
        [int]$MaxPerSector = 2
    )
    $eligible = @($Stocks | Where-Object { Test-ModelPortfolioEligibleStock -Stock $_ })
    if ($eligible.Count -lt $Count) { return $null }

    $greedy = {
        param($ranked)
        $sel = [System.Collections.Generic.List[string]]::new()
        $secCount = @{}
        foreach ($c in $ranked) {
            $sec = [string](Get-ObjectPropertyValue -Object $c -Name 'SectorTR')
            $sc = if ($secCount.ContainsKey($sec)) { [int]$secCount[$sec] } else { 0 }
            if ($sc -ge $MaxPerSector) { continue }
            [void]$sel.Add([string](Get-ObjectPropertyValue -Object $c -Name 'Symbol'))
            $secCount[$sec] = $sc + 1
            if ($sel.Count -ge $Count) { break }
        }
        return @($sel)
    }
    $scoreOf = { param($s, $adjusted)
        $sc = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'Score')
        if ($null -eq $sc) { return -1.0 }
        if ($adjusted) { return $sc }
        $sm = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'SmartMoneyAdjustment')
        $mr = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'MacroRegimeAdjustment')
        return $sc - $(if ($null -ne $sm) { $sm } else { 0.0 }) - $(if ($null -ne $mr) { $mr } else { 0.0 })
    }
    $actualRanked = @($eligible | Sort-Object @{ Expression = { & $scoreOf $_ $true }; Descending = $true })
    $shadowRanked = @($eligible | Sort-Object @{ Expression = { & $scoreOf $_ $false }; Descending = $true })
    $actual = & $greedy $actualRanked
    $shadow = & $greedy $shadowRanked
    $added = @($actual | Where-Object { $shadow -notcontains $_ })
    $dropped = @($shadow | Where-Object { $actual -notcontains $_ })
    $detail = @($eligible | Where-Object { $added -contains (Get-ObjectPropertyValue -Object $_ -Name 'Symbol') -or $dropped -contains (Get-ObjectPropertyValue -Object $_ -Name 'Symbol') } |
        ForEach-Object {
            [pscustomobject]@{
                symbol = [string](Get-ObjectPropertyValue -Object $_ -Name 'Symbol')
                score = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $_ -Name 'Score')
                smartMoney = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $_ -Name 'SmartMoneyAdjustment')
                macroRegime = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $_ -Name 'MacroRegimeAdjustment')
            }
        })
    return [pscustomobject][ordered]@{
        count = $Count
        actual = $actual
        shadow = $shadow
        added = $added
        dropped = $dropped
        changed = ($added.Count -gt 0)
        detail = $detail
    }
}

function Add-JsonlLine {
    <#
        JSONL (satir-basi-JSON) dosyasina TEK satir ekler; olcum loglari icin
        (regime_log, shadow_selection). Best-effort: dizin yoksa olusturur,
        hata olursa sessizce gecer (olcum, raporu ASLA bozmaz).
    #>
    param([string]$Path, $Object)
    try {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $line = ($Object | ConvertTo-Json -Depth 6 -Compress)
        Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
        return $true
    }
    catch { return $false }
}

function Get-ModelPortfolioSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Stocks,

        [ValidateSet('Dengeli', 'Değer', 'Momentum', 'Kalite')]
        [string]$Strategy,

        [int]$Count = 5,

        [int]$MaxPerSector = 2,

        # 'Score' (varsayilan, strateji skoru) veya 'RawFactorScore100' (ham-faktor)
        [string]$RankBy = 'Score'
    )

    $scoredAll = @(Get-BistScores -Stocks $Stocks -Strategy $Strategy)
    if ($RankBy -eq 'RawFactorScore100') {
        # RFS100 (STATIK temel cizgi) tum evren uzerinde kesitsel hesaplanir, sonra uygunlar siralanir.
        $scoredAll = @(Add-RawFactorScore -Stocks $scoredAll)
        $candidates = @(
            $scoredAll |
                Where-Object { Test-ModelPortfolioEligibleStock -Stock $_ } |
                Sort-Object @{ Expression = { [double](Get-ObjectPropertyValue -Object $_ -Name 'RawFactorScore100') }; Descending = $true }
        )
    }
    elseif ($RankBy -eq 'LearnedFactorScore100') {
        # OGRENEN portfoy: botun kendi ogrendigi agirliklarla (Get-LearnedFactorWeights)
        # kesitsel skor. Hem statik RFS100 (karsilastirma icin) hem LearnedFactorScore100
        # hesaplanir; siralama ogrenilmis skora gore. Agirlik yoksa statige duser (guvenli).
        $learnedWeights = Get-LearnedFactorWeights
        $scoredAll = @(Add-RawFactorScore -Stocks $scoredAll)
        $scoredAll = @(Add-RawFactorScore -Stocks $scoredAll -Weights $learnedWeights -ScoreName 'LearnedFactorScore')
        $candidates = @(
            $scoredAll |
                Where-Object { Test-ModelPortfolioEligibleStock -Stock $_ } |
                Sort-Object @{ Expression = { [double](Get-ObjectPropertyValue -Object $_ -Name 'LearnedFactorScore100') }; Descending = $true }
        )
    }
    elseif ($RankBy -eq 'RiskAdjusted') {
        # RISK-AYARLI siralama (RiskDengeli): strateji skoru / gunluk oynaklik.
        # Onceki durumda RiskDengeli, Dengeli ile AYNI anahtar ('Score') ile
        # siralandigi icin SECIM birebir ozdesti (5/5 ortusme); ayrisma yalniz
        # agirliklamadaydi. Bu anahtar dusuk-oynaklikli adaylari one cikararak
        # secimi de gercekten risk-dengeli yapar. Vol verisi yoksa tipik 3.0 kabul.
        $candidates = @(
            $scoredAll |
                Where-Object { Test-ModelPortfolioEligibleStock -Stock $_ } |
                Sort-Object @{ Expression = {
                        $s = Get-StrategySelectionScore -Stock $_ -Strategy $Strategy
                        $v = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $_ -Name 'VolatilityD')
                        if ($null -eq $v -or $v -le 0) { $v = 3.0 }
                        $s / (1.0 + $v)
                    }; Descending = $true }
        )
    }
    else {
        # Strateji-spesifik siralama: her portfoy kendi ekseninde ayrisir
        # (Dengeli=genel Score; Momentum/Deger/Kalite kendi bilesenine agirlikli).
        $candidates = @(
            $scoredAll |
                Where-Object { Test-ModelPortfolioEligibleStock -Stock $_ } |
                Sort-Object @{ Expression = { Get-StrategySelectionScore -Stock $_ -Strategy $Strategy }; Descending = $true }
        )
    }
    # Gozlemlenebilirlik: dar uygun-havuz, "hep ayni hisseler" sikayetinin ana
    # nedenlerinden biridir; her secimde havuz boyutu loglanir.
    Write-Host ("[secim] {0}/{1}: uygun havuz {2}/{3} hisse" -f $Strategy, $RankBy, $candidates.Count, $scoredAll.Count)

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

    $dates = New-Object System.Collections.Generic.List[datetime]

    # 1) Sabit tarihli resmi tatiller (her yil deterministik; BIST tamamen kapali).
    #    Yilbasi, Ulusal Egemenlik, Emek, Genclik, Demokrasi, Zafer, Cumhuriyet.
    foreach ($md in @('01-01', '04-23', '05-01', '05-19', '07-15', '08-30', '10-29')) {
        $p = $md.Split('-')
        [void]$dates.Add([datetime]::new($Year, [int]$p[0], [int]$p[1]))
    }
    # 29 Ekim arifesi (yarim gun degil; BIST geleneksel olarak 28 Ekim ogleden sonra
    # kapanir ama tam kapanis degildir) -> sadece tam kapanis gunleri listelenir.

    # 2) Dini bayramlar (ay takvimine bagli -> her yil BIST resmi tatil takviminden
    #    GUNCELLENMELIDIR). Eksik yil icin yalnizca sabit tatiller + hafta sonu atlanir.
    $religious = @{
        2026 = @('03-20', '03-21', '03-22', '05-27', '05-28', '05-29')
        2027 = @('03-10', '03-11', '03-12', '05-16', '05-17', '05-18', '05-19')
        2028 = @('02-26', '02-27', '02-28', '05-04', '05-05', '05-06', '05-07')
        # 2029-2030 yaklasik (astronomik); BIST resmi tatil takviminden dogrulanmalidir.
        2029 = @('02-14', '02-15', '02-16', '04-23', '04-24', '04-25', '04-26')
        2030 = @('02-04', '02-05', '02-06', '04-13', '04-14', '04-15', '04-16')
    }
    if ($religious.ContainsKey($Year)) {
        foreach ($md in $religious[$Year]) {
            $p = $md.Split('-')
            [void]$dates.Add([datetime]::new($Year, [int]$p[0], [int]$p[1]))
        }
    }

    return ($dates | Sort-Object -Unique)
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

function Get-BistMarketNow {
    <#
        BIST piyasa YEREL saati (Istanbul). Girdi UTC kabul edilir ve sabit +3 saat
        eklenir (Turkiye 2016'dan beri kalici UTC+3; yaz saati YOK). CI runner'i UTC
        oldugu icin ($runAt = Get-Date orada UTC doner) ay-sonu/rebalance kararlari
        yanlis saat diliminde verilirdi; bu yardimci piyasa saatini garanti eder.
        Varsayilan [datetime]::UtcNow kullanir (runner yerel TZ'sinden bagimsiz).
    #>
    param([datetime]$ReferenceUtc = [datetime]::UtcNow)
    return $ReferenceUtc.AddHours(3)
}

function Get-LatestCompletedModelPortfolioPeriodEnd {
    # DIKKAT: $AsOf PIYASA YEREL (Istanbul) saati olmalidir; market-close tamponu
    # (18:10) Istanbul saatine goredir. UTC verilirse ay-sonu gec algilanir
    # (bkz. Get-BistMarketNow — cagiran taraf $runAt'i piyasa saatine cevirir).
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

function Get-ModelPortfolioWeightingMethod {
    param($Object)

    $method = [string](Get-ObjectPropertyValue -Object $Object -Name 'WeightingMethod')
    if ([string]::IsNullOrWhiteSpace($method)) {
        return 'Equal'
    }

    return $method
}

function Get-ModelPortfolioWeightLimit {
    param(
        $Object,
        [string]$Name,
        [double]$Default
    )

    $value = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $Object -Name $Name)
    if ($null -eq $value -or $value -le 0) {
        return $Default
    }

    return [double]$value
}

function Get-ModelPortfolioTargetWeights {
    param(
        [Parameter(Mandatory)]
        [object[]]$Selection,

        [string]$WeightingMethod = 'Equal',

        [double]$MinWeightPct = 8.0,

        [double]$MaxWeightPct = 28.0,

        # Sektor yogunlasma tavani (%). Hicbir sektorun toplam agirligi bunu
        # gecemez (0 = kapali). Hem esit hem ters-oynaklik agirliklarina uygulanir.
        [double]$SectorMaxWeightPct = 35.0
    )

    $count = @($Selection).Count
    if ($count -le 0) {
        throw 'Model portföy ağırlığı için seçim listesi boş.'
    }

    # Sembol -> sektor haritasi (sektor tavani icin). Bilinmeyen/bos sektor her
    # isim icin AYRI tutulur (yanlislikla gruplanip cezalandirilmasin).
    $sectorMap = @{}
    foreach ($stock in $Selection) {
        $sym = [string]$stock.Symbol
        $sec = [string](Get-ObjectPropertyValue -Object $stock -Name 'SectorTR')
        if ([string]::IsNullOrWhiteSpace($sec)) { $sec = "__UNK__$sym" }
        $sectorMap[$sym] = $sec
    }
    $sectorMaxWeight = [double]$SectorMaxWeightPct / 100.0

    $weights = @{}
    if ($WeightingMethod -ne 'InverseVolatility') {
        $equalWeight = 1.0 / $count
        foreach ($stock in $Selection) {
            $weights[[string]$stock.Symbol] = $equalWeight
        }
        return (Get-SectorCappedWeights -Weights $weights -SectorMap $sectorMap -SectorMaxWeight $sectorMaxWeight)
    }

    $minWeight = [Math]::Max(0.0, [double]$MinWeightPct / 100.0)
    $maxWeight = [Math]::Min(1.0, [double]$MaxWeightPct / 100.0)
    if ($minWeight * $count -gt 1.0) { $minWeight = 0.0 }
    if ($maxWeight * $count -lt 1.0) { $maxWeight = 1.0 }

    $raw = @{}
    $rawTotal = 0.0
    foreach ($stock in $Selection) {
        $symbol = [string]$stock.Symbol
        $vol = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $stock -Name 'VolatilityD')
        if ($null -eq $vol -or $vol -le 0) { $vol = 4.0 }
        $score = 1.0 / [Math]::Max([double]$vol, 0.75)
        $raw[$symbol] = $score
        $rawTotal += $score
    }

    foreach ($symbol in $raw.Keys) {
        $weights[$symbol] = if ($rawTotal -gt 0) { [double]$raw[$symbol] / $rawTotal } else { 1.0 / $count }
    }

    for ($pass = 0; $pass -lt 5; $pass++) {
        $fixedTotal = 0.0
        $freeRawTotal = 0.0
        $freeSymbols = [System.Collections.Generic.List[string]]::new()

        foreach ($symbol in $raw.Keys) {
            $w = [double]$weights[$symbol]
            if ($w -lt $minWeight) {
                $weights[$symbol] = $minWeight
                $fixedTotal += $minWeight
            }
            elseif ($w -gt $maxWeight) {
                $weights[$symbol] = $maxWeight
                $fixedTotal += $maxWeight
            }
            else {
                [void]$freeSymbols.Add($symbol)
                $freeRawTotal += [double]$raw[$symbol]
            }
        }

        if ($freeSymbols.Count -eq 0) { break }
        $remaining = [Math]::Max(0.0, 1.0 - $fixedTotal)
        foreach ($symbol in $freeSymbols) {
            $weights[$symbol] = if ($freeRawTotal -gt 0) { $remaining * ([double]$raw[$symbol] / $freeRawTotal) } else { $remaining / $freeSymbols.Count }
        }
    }

    $sum = 0.0
    foreach ($symbol in $weights.Keys) { $sum += [double]$weights[$symbol] }
    if ($sum -gt 0) {
        foreach ($symbol in @($weights.Keys)) {
            $weights[$symbol] = [double]$weights[$symbol] / $sum
        }
    }

    return (Get-SectorCappedWeights -Weights $weights -SectorMap $sectorMap -SectorMaxWeight $sectorMaxWeight)
}

function Get-SectorCappedWeights {
    <#
        Sektor yogunlasma tavani: hicbir sektorun toplam agirligi SectorMaxWeight'i
        (kesir, or. 0.35) gecemez. Asan sektorun isimleri oransal kuculur; serbest
        kalan agirlik tavan-alti isimlere (mevcut agirliklariyla oranli) dagitilir.
        Cok-gecisli (yeniden dagitim baska sektoru asabilir). Toplam agirlik korunur.
    #>
    param(
        [hashtable]$Weights,
        [hashtable]$SectorMap,
        [double]$SectorMaxWeight
    )

    if ($null -eq $Weights -or $Weights.Count -eq 0) { return $Weights }
    # Gecersiz/kapali tavan ya da tek isim varken yapacak bir sey yok.
    if ($SectorMaxWeight -le 0 -or $SectorMaxWeight -ge 1) { return $Weights }

    for ($pass = 0; $pass -lt 8; $pass++) {
        $sectorTotals = @{}
        foreach ($sym in @($Weights.Keys)) {
            $sec = [string]$SectorMap[$sym]
            $cur = if ($sectorTotals.ContainsKey($sec)) { [double]$sectorTotals[$sec] } else { 0.0 }
            $sectorTotals[$sec] = $cur + [double]$Weights[$sym]
        }
        $over = @($sectorTotals.Keys | Where-Object { [double]$sectorTotals[$_] -gt $SectorMaxWeight + 1e-9 })
        if ($over.Count -eq 0) { break }

        $freed = 0.0
        $capped = @{}
        foreach ($sec in $over) {
            $tot = [double]$sectorTotals[$sec]
            $scale = if ($tot -gt 0) { $SectorMaxWeight / $tot } else { 1.0 }
            foreach ($sym in @($Weights.Keys)) {
                if ([string]$SectorMap[$sym] -eq $sec) {
                    $newW = [double]$Weights[$sym] * $scale
                    $freed += ([double]$Weights[$sym] - $newW)
                    $Weights[$sym] = $newW
                    $capped[$sym] = $true
                }
            }
        }

        $freeSyms = @($Weights.Keys | Where-Object { -not $capped.ContainsKey($_) })
        $freeBase = 0.0
        foreach ($sym in $freeSyms) { $freeBase += [double]$Weights[$sym] }
        # Dagitacak tavan-alti isim yoksa (hepsi capli) dur; infeasible.
        if ($freeSyms.Count -eq 0 -or $freeBase -le 0) { break }
        foreach ($sym in $freeSyms) {
            $Weights[$sym] = [double]$Weights[$sym] + $freed * ([double]$Weights[$sym] / $freeBase)
        }
    }

    $sum = 0.0
    foreach ($sym in @($Weights.Keys)) { $sum += [double]$Weights[$sym] }
    if ($sum -gt 0) {
        foreach ($sym in @($Weights.Keys)) { $Weights[$sym] = [double]$Weights[$sym] / $sum }
    }
    return $Weights
}

function Get-ModelPortfolioTargetValues {
    param(
        [Parameter(Mandatory)]
        [object[]]$Selection,

        [double]$TotalValue,

        [string]$WeightingMethod = 'Equal',

        [double]$MinWeightPct = 8.0,

        [double]$MaxWeightPct = 28.0,

        [double]$SectorMaxWeightPct = 35.0
    )

    $weights = Get-ModelPortfolioTargetWeights -Selection $Selection -WeightingMethod $WeightingMethod -MinWeightPct $MinWeightPct -MaxWeightPct $MaxWeightPct -SectorMaxWeightPct $SectorMaxWeightPct
    $targets = @{}
    foreach ($stock in $Selection) {
        $symbol = [string]$stock.Symbol
        $weight = [double]$weights[$symbol]
        $targets[$symbol] = [pscustomobject][ordered]@{
            Weight = $weight
            WeightPct = [Math]::Round($weight * 100.0, 2)
            TargetValue = [Math]::Round($TotalValue * $weight, 2)
        }
    }

    return $targets
}

function New-ModelPortfolioHolding {
    param(
        $Stock,
        [double]$TargetValue,
        [ValidateSet('Dengeli', 'Değer', 'Momentum', 'Kalite')]
        [string]$Strategy,
        [double]$TargetWeightPct = 20.0
    )

    $quantity = $TargetValue / [double]$Stock.Price
    return [pscustomobject][ordered]@{
        Symbol = [string]$Stock.Symbol
        Company = [string]$Stock.Company
        SectorTR = [string]$Stock.SectorTR
        StrategyScore = [Math]::Round([double]$Stock.Score, 1)
        RawFactorScore100 = Get-ObjectPropertyValue -Object $Stock -Name 'RawFactorScore100'
        LearnedFactorScore100 = Get-ObjectPropertyValue -Object $Stock -Name 'LearnedFactorScore100'
        MacroSectorScore = Get-ObjectPropertyValue -Object $Stock -Name 'MacroSectorScore'
        EvEbitda = Get-ObjectPropertyValue -Object $Stock -Name 'EvEbitda'
        VolatilityD = Get-ObjectPropertyValue -Object $Stock -Name 'VolatilityD'
        SelectionReason = Get-ModelPortfolioSelectionReason -Stock $Stock -Strategy $Strategy
        Quantity = [Math]::Round($quantity, 6)
        RebalancePrice = [Math]::Round([double]$Stock.Price, 4)
        CostBasisTL = [Math]::Round($TargetValue, 2)
        CurrentPrice = [Math]::Round([double]$Stock.Price, 4)
        CurrentValueTL = [Math]::Round($TargetValue, 2)
        WeightPct = [Math]::Round($TargetWeightPct, 2)
        GainSinceRebalanceTL = 0.0
        GainSinceRebalancePct = 0.0
        PriceIsFresh = $true
    }
}

function New-SingleModelPortfolio {
    param(
        [Parameter(Mandatory)] $Definition,
        [Parameter(Mandatory)] [object[]]$Stocks,
        [datetime]$AsOf = (Get-Date),
        [double]$InitialCapital = 100000,
        [double]$BenchmarkLevel = 0,
        [double]$CostBps = 0
    )

    $rankBy = Get-ObjectPropertyValue -Object $Definition -Name 'RankBy'
    if ([string]::IsNullOrWhiteSpace([string]$rankBy)) { $rankBy = 'Score' }
    $weightingMethod = Get-ModelPortfolioWeightingMethod -Object $Definition
    $minWeightPct = Get-ModelPortfolioWeightLimit -Object $Definition -Name 'MinWeightPct' -Default 8.0
    $maxWeightPct = Get-ModelPortfolioWeightLimit -Object $Definition -Name 'MaxWeightPct' -Default 28.0
    $sectorMaxWeightPct = Get-ModelPortfolioWeightLimit -Object $Definition -Name 'SectorMaxWeightPct' -Default 35.0
    $selection = @(Get-ModelPortfolioSelection -Stocks $Stocks -Strategy $Definition.Strategy -RankBy $rankBy)
    # Giris maliyeti: tum sermaye alindigi icin sermaye * maliyet orani.
    $entryCost = [Math]::Round($InitialCapital * ([double]$CostBps / 10000.0), 2)
    $investable = $InitialCapital - $entryCost
    $targetValues = Get-ModelPortfolioTargetValues -Selection $selection -TotalValue $investable -WeightingMethod $weightingMethod -MinWeightPct $minWeightPct -MaxWeightPct $maxWeightPct -SectorMaxWeightPct $sectorMaxWeightPct
    $holdings = [System.Collections.Generic.List[object]]::new()
    $transactions = [System.Collections.Generic.List[object]]::new()
    $allocationNote = if ($weightingMethod -eq 'InverseVolatility') {
        'Başlangıç sermayesi günlük oynaklık tersine göre risk dengeli hedef ağırlıklara bölündü.'
    }
    else {
        'Başlangıç sermayesi eşit ağırlıklı hedeflere bölündü.'
    }

    [void]$transactions.Add((New-ModelPortfolioTransaction `
                -Sequence 1 -ExecutionDate $AsOf -Action 'İLK KURULUM' -Symbol 'PORTFÖY' `
                -Company $Definition.Name -Price $null -Quantity $null -AmountTL $InitialCapital `
                -Note ('{0} Hisse sayısı {1}; yatırım tutarı {2:N2} TL.' -f $allocationNote, $selection.Count, $investable)))

    $sequence = 2
    foreach ($stock in $selection) {
        $symbol = [string]$stock.Symbol
        $target = $targetValues[$symbol]
        $targetValue = [double]$target.TargetValue
        $targetWeightPct = [double]$target.WeightPct
        $holding = New-ModelPortfolioHolding -Stock $stock -TargetValue $targetValue -Strategy $Definition.Strategy -TargetWeightPct $targetWeightPct
        [void]$holdings.Add($holding)
        [void]$transactions.Add((New-ModelPortfolioTransaction `
                    -Sequence $sequence -ExecutionDate $AsOf -Action 'AL' -Symbol $holding.Symbol `
                    -Company $holding.Company -Price $holding.CurrentPrice -Quantity $holding.Quantity -AmountTL $targetValue `
                    -Note ('İlk kurulum: hedef ağırlık %{0}. {1}' -f $targetWeightPct, $holding.SelectionReason)))
        $sequence++
    }

    if ($entryCost -gt 0) {
        [void]$transactions.Add((New-ModelPortfolioTransaction `
                    -Sequence $sequence -ExecutionDate $AsOf -Action 'MALİYET' -Symbol 'KOMİSYON' `
                    -Company $Definition.Name -Price $null -Quantity $null -AmountTL (- $entryCost) `
                    -Note ('Giriş işlem maliyeti + kayma (~{0} bps).' -f $CostBps)))
        $sequence++
    }

    return [pscustomobject][ordered]@{
        Id = $Definition.Id
        Name = $Definition.Name
        Strategy = $Definition.Strategy
        RankBy = $rankBy
        WeightingMethod = $weightingMethod
        MinWeightPct = if ($weightingMethod -eq 'InverseVolatility') { [Math]::Round($minWeightPct, 2) } else { $null }
        MaxWeightPct = if ($weightingMethod -eq 'InverseVolatility') { [Math]::Round($maxWeightPct, 2) } else { $null }
        Description = $Definition.Description
        StartDate = $AsOf.ToString('o')
        StartDateText = $AsOf.ToString('dd.MM.yyyy HH:mm')
        InitialCapitalTL = [Math]::Round($InitialCapital, 2)
        CurrentValueTL = [Math]::Round($investable, 2)
        TotalGainTL = [Math]::Round($investable - $InitialCapital, 2)
        TotalReturnPct = if ($InitialCapital -ne 0) { [Math]::Round((($investable - $InitialCapital) / $InitialCapital) * 100, 2) } else { 0.0 }
        CumulativeModelCostsTL = $entryCost
        PeakValueTL = [Math]::Round($investable, 2)
        CurrentDrawdownPct = 0.0
        MaxDrawdownPct = 0.0
        LastValuationAt = $AsOf.ToString('o')
        LastValuationAtText = $AsOf.ToString('dd.MM.yyyy HH:mm')
        LastRebalanceDate = $AsOf.ToString('o')
        LastRebalanceDateText = $AsOf.ToString('dd.MM.yyyy HH:mm')
        LastRebalancePeriodEnd = $AsOf.Date.ToString('yyyy-MM-dd')
        NextRebalanceDate = (Get-NextModelPortfolioRebalanceDate -LastRebalancePeriodEnd $AsOf.Date -AsOf $AsOf).ToString('yyyy-MM-dd')
        BenchmarkStartLevel = if ($BenchmarkLevel -gt 0) { [Math]::Round($BenchmarkLevel, 2) } else { $null }
        BenchmarkCurrentLevel = if ($BenchmarkLevel -gt 0) { [Math]::Round($BenchmarkLevel, 2) } else { $null }
        BenchmarkReturnPct = if ($BenchmarkLevel -gt 0) { 0.0 } else { $null }
        AlphaPct = if ($BenchmarkLevel -gt 0) { 0.0 } else { $null }
        StatusNote = 'İlk model işlem canlı tarama fiyatlarıyla oluşturuldu.'
        Holdings = $holdings.ToArray()
        Transactions = $transactions.ToArray()
    }
}

function New-ModelPortfolioSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Stocks,

        [datetime]$AsOf = (Get-Date),

        [double]$InitialCapital = 100000,

        [double]$BenchmarkLevel = 0,

        [double]$CostBps = 0
    )

    $portfolios = [System.Collections.Generic.List[object]]::new()
    foreach ($definition in Get-ModelPortfolioDefinitions) {
        [void]$portfolios.Add((New-SingleModelPortfolio -Definition $definition -Stocks $Stocks -AsOf $AsOf -InitialCapital $InitialCapital -BenchmarkLevel $BenchmarkLevel -CostBps $CostBps))
    }

    return [pscustomobject][ordered]@{
        Version = 1
        CreatedAt = $AsOf.ToString('o')
        UpdatedAt = $AsOf.ToString('o')
        InitialCapitalPerPortfolioTL = [Math]::Round($InitialCapital, 2)
        Notes = 'Fiyat bazlı teorik modeldir. Kesirli adet kullanır; işlem maliyeti + kayma modellenir (varsayılan ~20 bps); vergi, temettü ve bedelli/bedelsiz sermaye hareketleri hesaba katılmaz.'
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
        [datetime]$AsOf,
        [double]$BenchmarkLevel = 0   # guncel BIST100 seviyesi (alfa icin); 0 = bilinmiyor
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
                RawFactorScore100 = Get-ObjectPropertyValue -Object $holding -Name 'RawFactorScore100'
                LearnedFactorScore100 = Get-ObjectPropertyValue -Object $holding -Name 'LearnedFactorScore100'
                MacroSectorScore = Get-ObjectPropertyValue -Object $holding -Name 'MacroSectorScore'
                EvEbitda = Get-ObjectPropertyValue -Object $holding -Name 'EvEbitda'
                VolatilityD = Get-ObjectPropertyValue -Object $holding -Name 'VolatilityD'
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

    # BIST100 alfa: kurulustan beri portfoy getirisi - BIST100 getirisi.
    # BenchmarkStartLevel bir kez (kurulusta) saklanir; eski portfoylerde yoksa
    # ve guncel seviye varsa simdiden baslatilir (alfa bu noktadan ileriye olcer).
    $benchStart = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $Portfolio -Name 'BenchmarkStartLevel')
    if (($null -eq $benchStart -or $benchStart -le 0) -and $BenchmarkLevel -gt 0) { $benchStart = $BenchmarkLevel }
    $benchCurrent = if ($BenchmarkLevel -gt 0) { $BenchmarkLevel } else { ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $Portfolio -Name 'BenchmarkCurrentLevel') }
    $benchReturn = if ($null -ne $benchStart -and $benchStart -gt 0 -and $null -ne $benchCurrent -and $benchCurrent -gt 0) {
        (($benchCurrent / $benchStart) - 1.0) * 100.0
    }
    else { $null }
    $alpha = if ($null -ne $benchReturn) { $totalReturnPct - $benchReturn } else { $null }

    # Maksimum dusus (drawdown): zirve degere gore guncel dusus ve gorulen en kotu dusus.
    $priorPeak = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $Portfolio -Name 'PeakValueTL')
    if ($null -eq $priorPeak -or $priorPeak -le 0) { $priorPeak = $initialCapital }
    $peak = [Math]::Max([double]$priorPeak, $totalValue)
    $currentDrawdown = if ($peak -gt 0) { (($totalValue / $peak) - 1.0) * 100.0 } else { 0.0 }
    $priorMaxDd = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $Portfolio -Name 'MaxDrawdownPct')
    if ($null -eq $priorMaxDd) { $priorMaxDd = 0.0 }
    $maxDrawdown = [Math]::Min([double]$priorMaxDd, $currentDrawdown)

    $properties = [ordered]@{}
    foreach ($property in $Portfolio.PSObject.Properties) {
        if ($property.Name -notin @(
                'CurrentValueTL', 'TotalGainTL', 'TotalReturnPct', 'LastValuationAt',
                'LastValuationAtText', 'NextRebalanceDate', 'Holdings',
                'BenchmarkStartLevel', 'BenchmarkCurrentLevel', 'BenchmarkReturnPct', 'AlphaPct',
                'PeakValueTL', 'CurrentDrawdownPct', 'MaxDrawdownPct'
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
    $properties.BenchmarkStartLevel = if ($null -ne $benchStart) { [Math]::Round([double]$benchStart, 2) } else { $null }
    $properties.BenchmarkCurrentLevel = if ($null -ne $benchCurrent) { [Math]::Round([double]$benchCurrent, 2) } else { $null }
    $properties.BenchmarkReturnPct = if ($null -ne $benchReturn) { [Math]::Round($benchReturn, 2) } else { $null }
    $properties.AlphaPct = if ($null -ne $alpha) { [Math]::Round($alpha, 2) } else { $null }
    $properties.PeakValueTL = [Math]::Round($peak, 2)
    $properties.CurrentDrawdownPct = [Math]::Round($currentDrawdown, 2)
    $properties.MaxDrawdownPct = [Math]::Round($maxDrawdown, 2)
    $properties.Holdings = $holdings.ToArray()

    return [pscustomobject]$properties
}

function Invoke-ModelPortfolioRebalance {
    param(
        $Portfolio,
        [object[]]$Stocks,
        [hashtable]$StockMap,
        [datetime]$AsOf,
        [datetime]$PeriodEnd,
        [double]$BenchmarkLevel = 0,
        [double]$CostBps = 0
    )

    $valuedPortfolio = Update-ModelPortfolioValuation -Portfolio $Portfolio -StockMap $StockMap -AsOf $AsOf -BenchmarkLevel $BenchmarkLevel
    $missingLivePrices = @(
        $valuedPortfolio.Holdings |
            Where-Object { -not $_.PriceIsFresh } |
            Select-Object -ExpandProperty Symbol
    )
    if ($missingLivePrices.Count -gt 0) {
        $valuedPortfolio.StatusNote = 'Ay sonu işlemi ertelendi; canlı fiyatı bulunmayan hisseler: ' + ($missingLivePrices -join ', ')
        return $valuedPortfolio
    }

    $rebalanceRankBy = Get-ObjectPropertyValue -Object $valuedPortfolio -Name 'RankBy'
    if ([string]::IsNullOrWhiteSpace([string]$rebalanceRankBy)) { $rebalanceRankBy = 'Score' }
    $weightingMethod = Get-ModelPortfolioWeightingMethod -Object $valuedPortfolio
    $minWeightPct = Get-ModelPortfolioWeightLimit -Object $valuedPortfolio -Name 'MinWeightPct' -Default 8.0
    $maxWeightPct = Get-ModelPortfolioWeightLimit -Object $valuedPortfolio -Name 'MaxWeightPct' -Default 28.0
    $sectorMaxWeightPct = Get-ModelPortfolioWeightLimit -Object $valuedPortfolio -Name 'SectorMaxWeightPct' -Default 35.0
    $selection = @(Get-ModelPortfolioSelection -Stocks $Stocks -Strategy $valuedPortfolio.Strategy -RankBy $rebalanceRankBy)
    $totalValue = [double]$valuedPortfolio.CurrentValueTL
    $targetValuesPreCost = Get-ModelPortfolioTargetValues -Selection $selection -TotalValue $totalValue -WeightingMethod $weightingMethod -MinWeightPct $minWeightPct -MaxWeightPct $maxWeightPct -SectorMaxWeightPct $sectorMaxWeightPct
    $oldHoldings = @{}
    foreach ($holding in @($valuedPortfolio.Holdings)) {
        $oldHoldings[[string]$holding.Symbol] = $holding
    }

    $newSymbols = @($selection | Select-Object -ExpandProperty Symbol)
    $oldSymbols = @($valuedPortfolio.Holdings | Select-Object -ExpandProperty Symbol)
    $removedSymbols = @($oldSymbols | Where-Object { $_ -notin $newSymbols })
    $addedSymbols = @($newSymbols | Where-Object { $_ -notin $oldSymbols })
    $keptSymbols = @($newSymbols | Where-Object { $_ -in $oldSymbols })

    # Islem maliyeti + kayma: ciro (satilan + alinan + esitleme deltalari) uzerinden.
    $costRate = [double]$CostBps / 10000.0
    $turnover = 0.0
    foreach ($s in $removedSymbols) { $turnover += [double]$oldHoldings[$s].CurrentValueTL }
    foreach ($s in $addedSymbols) { $turnover += [double]$targetValuesPreCost[$s].TargetValue }
    foreach ($s in $keptSymbols) { $turnover += [Math]::Abs([double]$targetValuesPreCost[$s].TargetValue - [double]$oldHoldings[$s].CurrentValueTL) }
    $rebalanceCost = [Math]::Round($turnover * $costRate, 2)
    if ($rebalanceCost -lt 0) { $rebalanceCost = 0 }
    # Maliyeti dus: net deger ve hedef agirliklar yeniden hesaplanir.
    $totalValue = $totalValue - $rebalanceCost
    $targetValues = Get-ModelPortfolioTargetValues -Selection $selection -TotalValue $totalValue -WeightingMethod $weightingMethod -MinWeightPct $minWeightPct -MaxWeightPct $maxWeightPct -SectorMaxWeightPct $sectorMaxWeightPct

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
    $targetSummary = (@($selection | ForEach-Object {
                $s = [string]$_.Symbol
                '{0} %{1:N1}' -f $s, ([double]$targetValues[$s].WeightPct)
            }) -join ', ')
    $allocationText = if ($weightingMethod -eq 'InverseVolatility') { 'risk dengeli hedef ağırlıklara' } else { 'eşit ağırlıklı hedeflere' }
    $summaryNote = 'Portföy {0:N2} TL olarak {1} bölündü. Hedefler: {2}. Çıkan: {3}. Giren: {4}. Kalan: {5}.{6}' -f `
        $totalValue, `
        $allocationText, `
        $targetSummary, `
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
        $target = $targetValues[$symbol]
        $targetValue = [double]$target.TargetValue
        $targetWeightPct = [double]$target.WeightPct
        $newHolding = New-ModelPortfolioHolding -Stock $stock -TargetValue $targetValue -Strategy $valuedPortfolio.Strategy -TargetWeightPct $targetWeightPct
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
                            -Note ('Ay sonu hedef ağırlık %{0}; işlem öncesi değer {1:N2} TL, işlem sonrası hedef {2:N2} TL.' -f $targetWeightPct, $oldHolding.CurrentValueTL, $targetValue)))
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
                        -Note ("$PeriodEnd ay sonu strateji sıralamasında portföye girdi; hedef ağırlık %$targetWeightPct. $($newHolding.SelectionReason)")))
            $sequence++
        }
    }

    if ($rebalanceCost -gt 0) {
        [void]$transactions.Add((New-ModelPortfolioTransaction `
                    -Sequence $sequence `
                    -ExecutionDate $AsOf `
                    -Action 'MALİYET' `
                    -Symbol 'KOMİSYON' `
                    -Company $valuedPortfolio.Name `
                    -Price $null `
                    -Quantity $null `
                    -AmountTL (- $rebalanceCost) `
                    -Note ('İşlem maliyeti + kayma (~{0} bps; ciro {1:N0} TL).' -f $CostBps, $turnover)))
        $sequence++
    }
    $priorCosts = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $valuedPortfolio -Name 'CumulativeModelCostsTL')
    if ($null -eq $priorCosts) { $priorCosts = 0.0 }

    $properties = [ordered]@{}
    foreach ($property in $valuedPortfolio.PSObject.Properties) {
        if ($property.Name -notin @(
                'CurrentValueTL', 'TotalGainTL', 'TotalReturnPct', 'LastRebalanceDate',
                'LastRebalanceDateText', 'LastRebalancePeriodEnd', 'NextRebalanceDate',
                'StatusNote', 'Holdings', 'Transactions', 'CumulativeModelCostsTL'
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
    $properties.CumulativeModelCostsTL = [Math]::Round($priorCosts + $rebalanceCost, 2)
    $properties.Holdings = $newHoldings.ToArray()
    $properties.Transactions = $transactions.ToArray()

    return [pscustomobject]$properties
}

function Optimize-ModelPortfolioSetRisk {
    <#
        Ay sonu yeniden dengelemede tum SET'e uygulanan GERCEKCILIK kisiti: TAM LOT.
        BIST tam adet isler; her holding'in adedi tam sayiya (asagi) yuvarlanir,
        deger = adet * fiyat; kucuk artik nakit (gercekci) portfoy degerinden dusulur.
        Portfoy toplam degeri, agirliklar ve getiri yeniden hesaplanir.

        NOT — portfoyler-arasi sabit TAVAN burada UYGULANMAZ: 6 portfoy buyuk olcude
        ayni isimleri tuttugundan, secimi koruyan bir agirlik-dagitimi matematiksel
        olarak yakinsamiyor (asan ismin agirligi yine paylasilan diger isimlere gidip
        yogunlasmayi tekrar uretiyor) ya da agir nakit birakiyor. Gercek/saglikli tek
        cozum SECIMI degistirmektir (ayri bir karar). Bu yuzden burada yalniz IZLEME
        yapilir (rapordaki 'Portfoyler-Arasi Yogunlasma' tablosu); bkz. README.
        MaxBookPct simdilik yalniz bu pasin calisip calismayacagini ACAR (>0).
    #>
    param([object[]]$Portfolios, [double]$MaxBookPct = 15.0)

    if ($null -eq $Portfolios -or @($Portfolios).Count -eq 0) { return $Portfolios }
    if ($MaxBookPct -le 0) { return $Portfolios }

    # --- Tam lot + portfoy toplam/agirlik/getiri yeniden hesabi ---
    foreach ($p in $Portfolios) {
        $holds = @(Get-ObjectPropertyValue -Object $p -Name 'Holdings')
        $portVal = 0.0
        foreach ($h in $holds) {
            $price = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $h -Name 'CurrentPrice')
            if ($null -eq $price) { $price = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $h -Name 'RebalancePrice') }
            $val = [double](ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $h -Name 'CurrentValueTL'))
            if ($null -ne $price -and $price -gt 0) {
                $qty = [Math]::Floor($val / $price)
                if ($qty -lt 0) { $qty = 0 }
                $val = $qty * $price
                $h.Quantity = $qty
                $h.CostBasisTL = [Math]::Round($val, 2)
                $h.CurrentValueTL = [Math]::Round($val, 2)
            }
            $portVal += $val
        }
        foreach ($h in $holds) {
            $h.WeightPct = if ($portVal -gt 0) { [Math]::Round(([double]$h.CurrentValueTL / $portVal) * 100.0, 2) } else { 0.0 }
        }
        $initial = [double](ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $p -Name 'InitialCapitalTL'))
        $p | Add-Member -NotePropertyName 'CurrentValueTL' -NotePropertyValue ([Math]::Round($portVal, 2)) -Force
        if ($null -ne $initial -and $initial -gt 0) {
            $p | Add-Member -NotePropertyName 'TotalGainTL' -NotePropertyValue ([Math]::Round($portVal - $initial, 2)) -Force
            $p | Add-Member -NotePropertyName 'TotalReturnPct' -NotePropertyValue ([Math]::Round((($portVal - $initial) / $initial) * 100.0, 2)) -Force
        }
    }
    return $Portfolios
}

function Update-ModelPortfolioSet {
    [CmdletBinding()]
    param(
        $PortfolioSet,

        [Parameter(Mandatory)]
        [object[]]$Stocks,

        [datetime]$AsOf = (Get-Date),

        [switch]$AllowRebalance,

        [double]$BenchmarkLevel = 0,

        [double]$CostBps = 0,

        [double]$MaxBookPct = 0
    )

    if ($null -eq $PortfolioSet -or $null -eq (Get-ObjectPropertyValue -Object $PortfolioSet -Name 'Portfolios')) {
        if ($AllowRebalance) {
            $fresh = New-ModelPortfolioSet -Stocks $Stocks -AsOf $AsOf -BenchmarkLevel $BenchmarkLevel -CostBps $CostBps
            if ($MaxBookPct -gt 0 -and $null -ne $fresh) {
                $fresh.Portfolios = Optimize-ModelPortfolioSetRisk -Portfolios @($fresh.Portfolios) -MaxBookPct $MaxBookPct
            }
            return $fresh
        }
        return $null
    }

    $stockMap = Get-ModelPortfolioStockMap -Stocks $Stocks
    $latestCompletedPeriodEnd = Get-LatestCompletedModelPortfolioPeriodEnd -AsOf $AsOf
    $rebalancedAny = $false
    $portfolios = [System.Collections.Generic.List[object]]::new()
    foreach ($portfolio in @(Get-ObjectPropertyValue -Object $PortfolioSet -Name 'Portfolios')) {
        $valuedPortfolio = Update-ModelPortfolioValuation -Portfolio $portfolio -StockMap $stockMap -AsOf $AsOf -BenchmarkLevel $BenchmarkLevel
        $lastPeriodValue = Get-ObjectPropertyValue -Object $valuedPortfolio -Name 'LastRebalancePeriodEnd'
        $lastPeriodEnd = if ($null -ne $lastPeriodValue -and -not [string]::IsNullOrWhiteSpace([string]$lastPeriodValue)) {
            [datetime]$lastPeriodValue
        }
        else {
            [datetime]::MinValue
        }

        if ($AllowRebalance -and $lastPeriodEnd.Date -lt $latestCompletedPeriodEnd.Date) {
            $rebalancedAny = $true
            [void]$portfolios.Add((Invoke-ModelPortfolioRebalance `
                        -Portfolio $valuedPortfolio `
                        -Stocks $Stocks `
                        -StockMap $stockMap `
                        -AsOf $AsOf `
                        -PeriodEnd $latestCompletedPeriodEnd `
                        -BenchmarkLevel $BenchmarkLevel `
                        -CostBps $CostBps))
        }
        else {
            [void]$portfolios.Add($valuedPortfolio)
        }
    }

    # Migration: tanimlarda olup state'te olmayan portfoyleri (or. RFS100) olustur.
    if ($AllowRebalance) {
        $existingIds = @($portfolios | ForEach-Object { [string]$_.Id })
        $initCap = [double](Get-ObjectPropertyValue -Object $PortfolioSet -Name 'InitialCapitalPerPortfolioTL')
        if ($initCap -le 0) { $initCap = 100000 }
        foreach ($definition in Get-ModelPortfolioDefinitions) {
            if ([string]$definition.Id -notin $existingIds) {
                try {
                    [void]$portfolios.Add((New-SingleModelPortfolio -Definition $definition -Stocks $Stocks -AsOf $AsOf -InitialCapital $initCap -BenchmarkLevel $BenchmarkLevel -CostBps $CostBps))
                    $rebalancedAny = $true
                }
                catch {
                    # Uygun hisse yetersizse sessizce atla; sonraki çalışmada tekrar denenir.
                }
            }
        }
    }

    # Yeniden dengeleme olduysa SET'e portfoyler-arasi tavan + tam-lot uygula (aylik).
    $portfolioArray = $portfolios.ToArray()
    if ($AllowRebalance -and $rebalancedAny -and $MaxBookPct -gt 0) {
        $portfolioArray = Optimize-ModelPortfolioSetRisk -Portfolios $portfolioArray -MaxBookPct $MaxBookPct
    }

    $properties = [ordered]@{}
    foreach ($property in $PortfolioSet.PSObject.Properties) {
        if ($property.Name -notin @('UpdatedAt', 'Portfolios')) {
            $properties[$property.Name] = $property.Value
        }
    }
    $properties.UpdatedAt = $AsOf.ToString('o')
    $properties.Portfolios = $portfolioArray

    return [pscustomobject]$properties
}

# ============================================================================
# RawFactorScore: kesitsel ham-faktor skoru (backtest bulgusu).
# Get-BistScore'un ayrik RSI/MACD/SMA puanlamasi OOS'ta bilgi yok ediyordu; ham
# faktorlerin kesitsel z-skor + lineer karisimi botun skorunun ~2 kati IC verdi
# (bkz. backtest/README.md). Bu fonksiyon mevcut skoru DEGISTIRMEZ; her hisseye
# RawFactorScore + RawFactorScore100 (0-100 gun-ici yuzdelik) ekler.
# Agirliklar BIST100 walk-forward ortalamalaridir; yon kritik (RSI negatif!).
# ============================================================================

function Get-RfNumber {
    param($Value)
    if ($null -eq $Value) { return $null }
    return ($Value -as [double])
}

function Get-RawFactorVector {
    param($Stock)
    $price = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'Price')
    $rsi = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'RSI')
    $mh = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'MacdHistogram')
    $wmh = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'MacdHistogramWeekly')
    $sma20 = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'SMA20')
    $sma50 = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'SMA50')
    $sma200 = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'SMA200')
    $p1m = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'PerfMonth')
    $p3m = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'Perf3Month')
    $relv = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'RelativeVolume')
    $rvol = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'VolatilityD')
    # Yabanci akis faktoru (2026-07-03'ten itibaren PIT'te arsivlenir). IC olcumunde
    # uc degerler baskin olmasin diye [-3,+3] puana kirpilir; eski snapshot'larda
    # alan yok -> null -> o gozlem bu faktor icin atlanir (IC hesabi bozulmaz).
    $fflow = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'ForeignChg1wBps')
    if ($null -ne $fflow) { $fflow = [Math]::Max(-3.0, [Math]::Min(3.0, [double]$fflow)) }
    [ordered]@{
        RSI     = $rsi
        MACDh   = if ($null -ne $mh -and $null -ne $price -and $price -gt 0) { ($mh / $price) * 100 } else { $null }
        WMACDh  = if ($null -ne $wmh -and $null -ne $price -and $price -gt 0) { ($wmh / $price) * 100 } else { $null }
        dSMA20  = if ($null -ne $price -and $null -ne $sma20 -and $sma20 -gt 0) { ($price / $sma20 - 1) * 100 } else { $null }
        dSMA50  = if ($null -ne $price -and $null -ne $sma50 -and $sma50 -gt 0) { ($price / $sma50 - 1) * 100 } else { $null }
        dSMA200 = if ($null -ne $price -and $null -ne $sma200 -and $sma200 -gt 0) { ($price / $sma200 - 1) * 100 } else { $null }
        Perf1M  = $p1m
        Perf3M  = $p3m
        RelVol  = $relv
        RVol    = $rvol
        FFlow   = $fflow
    }
}

function Get-StaticFactorWeights {
    # BIST100 walk-forward (4-hafta tutus) ortalama agirliklari; kesit z-skoru basina.
    # RFS100'un STATIK temel cizgisi (backtest). Ogrenme bunu DEGISTIRMEZ; ayri
    # 'OgrenenAlgoritma' portfoyu ogrenilmis agirliklari kullanir (yan yana izlenir).
    return @{
        RSI = -1.49; MACDh = 0.69; WMACDh = 0.35; dSMA20 = -0.13; dSMA50 = 0.82
        dSMA200 = 1.58; Perf1M = 0.86; Perf3M = -1.29; RelVol = -0.40; RVol = -0.62
        # FFlow (yabanci akis): prior 0 -> skoru BUGUN etkilemez; PIT'te veri
        # biriktikce oto-kalibrasyon IC olcup agirligi veriye gore verir.
        FFlow = 0.0
    }
}

function Add-RawFactorScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Stocks,
        [hashtable]$Weights,
        # Yazilacak ozellik adi: '<ScoreName>' (ham) + '<ScoreName>100' (0-100 yuzdelik).
        # Varsayilan RawFactorScore/RawFactorScore100 (RFS100 statik temel cizgisi).
        # Ogrenilmis portfoy 'LearnedFactorScore' adiyla ayri bir alana yazar.
        [string]$ScoreName = 'RawFactorScore'
    )
    if (-not $Weights) {
        # Varsayilan: STATIK backtest agirliklari (RFS100 temel cizgisi). Ogrenilmis
        # agirliklari kullanmak isteyen cagiran -Weights (Get-LearnedFactorWeights) verir.
        $Weights = Get-StaticFactorWeights
    }
    $factorNames = @($Weights.Keys)
    $facList = New-Object System.Collections.Generic.List[object]
    foreach ($s in $Stocks) { $facList.Add((Get-RawFactorVector -Stock $s)) }

    $stats = @{}
    foreach ($fn in $factorNames) {
        $vals = New-Object System.Collections.Generic.List[double]
        foreach ($f in $facList) { if ($null -ne $f[$fn]) { $vals.Add([double]$f[$fn]) } }
        if ($vals.Count -ge 3) {
            $mean = ($vals | Measure-Object -Average).Average
            $var = 0.0; foreach ($v in $vals) { $var += ($v - $mean) * ($v - $mean) }
            $std = [Math]::Sqrt($var / $vals.Count)
        }
        else { $mean = 0.0; $std = 0.0 }
        $stats[$fn] = [pscustomobject]@{ Mean = $mean; Std = $std }
    }

    $blends = New-Object double[] $Stocks.Count
    for ($i = 0; $i -lt $Stocks.Count; $i++) {
        $f = $facList[$i]; $blend = 0.0
        foreach ($fn in $factorNames) {
            $st = $stats[$fn]
            if ($st.Std -gt 1e-9 -and $null -ne $f[$fn]) {
                $z = ([double]$f[$fn] - $st.Mean) / $st.Std
                $blend += [double]$Weights[$fn] * $z
            }
        }
        $blends[$i] = $blend
    }
    $order = 0..($Stocks.Count - 1) | Sort-Object { $blends[$_] }
    $pct = New-Object double[] $Stocks.Count
    $n = $Stocks.Count
    for ($rank = 0; $rank -lt $n; $rank++) {
        $idx = $order[$rank]
        $pct[$idx] = if ($n -gt 1) { [Math]::Round(($rank / ($n - 1.0)) * 100, 1) } else { 50 }
    }
    for ($i = 0; $i -lt $Stocks.Count; $i++) {
        $Stocks[$i] | Add-Member -NotePropertyName $ScoreName -NotePropertyValue ([Math]::Round($blends[$i], 4)) -Force
        $Stocks[$i] | Add-Member -NotePropertyName ($ScoreName + '100') -NotePropertyValue $pct[$i] -Force
    }
    return $Stocks
}

function Get-LearnedFactorWeights {
    <#
        Oto-kalibrasyonun yazdigi ogrenilmis RFS faktor agirliklarini okur
        (data/learned_factor_weights.json -> .Weights). Yoksa/bozuksa $null.
        Varligi 'OgrenenAlgoritma' portfoyunu aktive eder ve onun seciminde kullanilir;
        RFS100 ve diger portfoyler STATIK agirligi korur (yan yana karsilastirma).
    #>
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $root = if ($PSScriptRoot) { $PSScriptRoot } else { '.' }
        $Path = Join-Path $root 'data/learned_factor_weights.json'
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $obj = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $w = Get-ObjectPropertyValue -Object $obj -Name 'Weights'
        if ($null -eq $w) { return $null }
        $h = @{}
        foreach ($p in $w.PSObject.Properties) {
            $d = ConvertTo-DoubleOrNull $p.Value
            if ($null -ne $d) { $h[$p.Name] = $d }
        }
        if ($h.Count -eq 0) { return $null }
        return $h
    }
    catch { return $null }
}

function Get-PearsonCorrelation {
    param([double[]]$X, [double[]]$Y)
    $n = [Math]::Min($X.Count, $Y.Count)
    if ($n -lt 3) { return $null }
    $mx = 0.0; $my = 0.0
    for ($i = 0; $i -lt $n; $i++) { $mx += $X[$i]; $my += $Y[$i] }
    $mx /= $n; $my /= $n
    $sxy = 0.0; $sxx = 0.0; $syy = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $dx = $X[$i] - $mx; $dy = $Y[$i] - $my
        $sxy += $dx * $dy; $sxx += $dx * $dx; $syy += $dy * $dy
    }
    if ($sxx -le 1e-12 -or $syy -le 1e-12) { return $null }
    return $sxy / [Math]::Sqrt($sxx * $syy)
}

function Get-WalkForwardFactorWeights {
    <#
        KENDI KENDINE OGRENME cekirdegi (asiri-uyuma karsi korumali). Girdi: walk-forward
        DONEMLER; her donem = o gun gozlenen hisselerin faktor vektoru + ILERI getirisi.
        Yontem: cok-degiskenli regresyon (multikolinearite/overfit riski) YERINE faktor
        basina kesitsel IC (Pearson korelasyon, faktor<->ileri getiri); donemler arasi
        ortalanir. IC vektoru, mevcut (prior) agirliklarin L2 normuna olceklenir, sonra
        prior'a dogru BUZULTULUR (shrinkage, lambda) — boylece agirliklar yavas/dengeli
        degisir. Yetersiz veride ($MinPeriods altinda) prior aynen korunur.
        Doner: @{ Weights=...; Diagnostics=... }.
    #>
    param(
        [Parameter(Mandatory)][object[]]$Periods,   # her oge: object[] gozlem (@{Factors=@{};FwdRet=d})
        [Parameter(Mandatory)][hashtable]$PriorWeights,
        [int]$MinPeriods = 8,
        [int]$MinObsPerPeriod = 10,
        [double]$Lambda = 0.30,
        [double]$Bound = 3.0
    )
    $factorNames = @($PriorWeights.Keys)
    $valid = @($Periods | Where-Object { @($_).Count -ge $MinObsPerPeriod })
    $diag = [ordered]@{ PeriodsGiven = @($Periods).Count; PeriodsUsed = $valid.Count; MeanIC = @{}; TStat = @{}; Applied = $false }

    # HIJYEN #1 (denetim #5): ileri getirileri donem icinde WINSORIZE et (p05/p95).
    # Tek bir tavan/taban ucu (spekulatif +%100 gunler) IC'yi domine edemesin.
    $prepped = @(foreach ($period in $valid) {
            $rets = @(@($period) | ForEach-Object { ConvertTo-DoubleOrNull $_.FwdRet } | Where-Object { $null -ne $_ } | Sort-Object)
            if ($rets.Count -lt 3) { , @($period); continue }
            $lo = [double]$rets[[Math]::Floor(0.05 * ($rets.Count - 1))]
            $hi = [double]$rets[[Math]::Ceiling(0.95 * ($rets.Count - 1))]
            , @(@($period) | ForEach-Object {
                    $r = ConvertTo-DoubleOrNull $_.FwdRet
                    if ($null -ne $r) { if ($r -lt $lo) { $r = $lo } elseif ($r -gt $hi) { $r = $hi } }
                    [pscustomobject]@{ Factors = $_.Factors; FwdRet = $r }
                })
        })
    $valid = $prepped

    if ($valid.Count -lt $MinPeriods) {
        $diag.Reason = "Yetersiz donem ($($valid.Count) < $MinPeriods); prior korundu."
        return [pscustomobject]@{ Weights = $PriorWeights.Clone(); Diagnostics = [pscustomobject]$diag }
    }

    # Faktor basina ortalama IC.
    $meanIC = @{}
    foreach ($fn in $factorNames) {
        $ics = New-Object System.Collections.Generic.List[double]
        foreach ($period in $valid) {
            $fx = New-Object System.Collections.Generic.List[double]
            $ry = New-Object System.Collections.Generic.List[double]
            foreach ($obs in @($period)) {
                $facs = $obs.Factors; $ret = ConvertTo-DoubleOrNull $obs.FwdRet
                if ($null -eq $facs -or $null -eq $ret) { continue }
                $fv = if ($facs.ContainsKey($fn)) { ConvertTo-DoubleOrNull $facs[$fn] } else { $null }
                if ($null -eq $fv) { continue }
                $fx.Add([double]$fv); $ry.Add([double]$ret)
            }
            $ic = Get-PearsonCorrelation -X $fx.ToArray() -Y $ry.ToArray()
            if ($null -ne $ic) { [void]$ics.Add([double]$ic) }
        }
        $meanIC[$fn] = if ($ics.Count -gt 0) { ($ics | Measure-Object -Average).Average } else { 0.0 }
        # HIJYEN #2 (denetim #5): IC ANLAMLILIK KAPISI — donemler arasi t-istatistigi
        # zayifsa (|t|<2) o faktorun IC'si orantili sondurulur (damp=|t|/2, en cok 1).
        # Boylece gurultuyle "ogrenilmis" gibi gorunen faktorler agirligi suruklemez.
        $tStat = 0.0
        if ($ics.Count -ge 2) {
            $icMean = [double]$meanIC[$fn]
            $icVar = 0.0; foreach ($ic in $ics) { $icVar += ($ic - $icMean) * ($ic - $icMean) }
            $icSd = [Math]::Sqrt($icVar / ($ics.Count - 1))
            $tStat = if ($icSd -gt 1e-12) { $icMean / ($icSd / [Math]::Sqrt($ics.Count)) } else { [Math]::Sign($icMean) * 99.0 }
            $damp = [Math]::Min(1.0, [Math]::Abs($tStat) / 2.0)
            $meanIC[$fn] = $icMean * $damp
        }
        $diag.MeanIC[$fn] = [Math]::Round([double]$meanIC[$fn], 4)
        $diag.TStat[$fn] = [Math]::Round([double]$tStat, 2)
    }

    # IC vektorunu prior'un L2 normuna olcekle (bot skor olcegiyle uyum).
    $priorNorm = 0.0; foreach ($fn in $factorNames) { $priorNorm += [double]$PriorWeights[$fn] * [double]$PriorWeights[$fn] }
    $priorNorm = [Math]::Sqrt($priorNorm)
    $icNorm = 0.0; foreach ($fn in $factorNames) { $icNorm += [double]$meanIC[$fn] * [double]$meanIC[$fn] }
    $icNorm = [Math]::Sqrt($icNorm)
    $scale = if ($icNorm -gt 1e-9 -and $priorNorm -gt 1e-9) { $priorNorm / $icNorm } else { 0.0 }

    $newW = @{}
    foreach ($fn in $factorNames) {
        $scaled = [double]$meanIC[$fn] * $scale
        $blended = (1.0 - $Lambda) * [double]$PriorWeights[$fn] + $Lambda * $scaled
        if ($blended -gt $Bound) { $blended = $Bound }
        elseif ($blended -lt (-1 * $Bound)) { $blended = -1 * $Bound }
        $newW[$fn] = [Math]::Round($blended, 4)
    }
    $diag.Applied = $true
    return [pscustomobject]@{ Weights = $newW; Diagnostics = [pscustomobject]$diag }
}


# Literatur temelli, uzun-yonlu faktor karisimi:
#   - Momentum 12-1 (Jegadeesh & Titman 1993): son 1 ay atlanarak 12 aylik
#     getiri; kisa vadeli ters donusten arindirilir.
#   - Kalite (Novy-Marx 2013; Fama-French RMW): ROE +, borc/ozkaynak -,
#     FAVOK ardisik artisi +.
#   - Deger (Fama-French HML): dusuk FD/FAVOK, dusuk PD/DD, dusuk F/K.
#   - Dusuk volatilite (Frazzini & Pedersen 2014; Ang ve ark. 2006):
#     dusuk gunluk volatilite primi.
#   - Boyut (Fama-French SMB): kucuk piyasa degeri hafif prim.
# Mevcut Score'u ve RawFactorScore'u DEGISTIRMEZ; bagimsiz bir siralama
# sinyali olarak AcademicFactorScore (ham) + AcademicFactorScore100 (0-100)
# ve yardimci metrikler (Momentum12_1Pct, AnnualizedVolatilityPct,
# RiskAdjustedMomentum) ekler.
# ============================================================================

function Get-Momentum12_1Pct {
    param($Stock)
    $py = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'PerfYear')
    $pm = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'PerfMonth')
    if ($null -eq $py) { return $null }
    $yearFactor = 1.0 + ($py / 100.0)
    $monthFactor = if ($null -ne $pm) { 1.0 + ($pm / 100.0) } else { 1.0 }
    if ($yearFactor -le 0 -or $monthFactor -le 0) { return $null }
    # Son ayi disla: (1+12ay)/(1+1ay) - 1
    return (($yearFactor / $monthFactor) - 1.0) * 100.0
}

function Get-AcademicFactorVector {
    param($Stock)

    $evEbitda = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'EvEbitda')
    $pb = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'PB')
    $pe = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'PE')
    $roe = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'ROE')
    $de = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'DebtToEquity')
    $ebTrend = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'EbitdaSequentialIncreaseCount')
    $volD = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'VolatilityD')
    $mcap = Get-RfNumber (Get-ObjectPropertyValue -Object $Stock -Name 'MarketCap')
    $mom = Get-Momentum12_1Pct -Stock $Stock

    # Deger: ucuz = yuksek skor. Negatif/sifir carpanlar anlamsiz -> null.
    $valEvEbitda = if ($null -ne $evEbitda -and $evEbitda -gt 0) { - $evEbitda } else { $null }
    $valPb = if ($null -ne $pb -and $pb -gt 0) { - $pb } else { $null }
    $valPe = if ($null -ne $pe -and $pe -gt 0) { - $pe } else { $null }

    # Kalite: yuksek ROE, dusuk borc, FAVOK ardisik artisi.
    $qualRoe = $roe
    $qualDebt = if ($null -ne $de) { - $de } else { $null }
    $qualEbTrend = $ebTrend

    # Dusuk volatilite primi: dusuk gunluk vol = yuksek skor.
    $lowVol = if ($null -ne $volD) { - $volD } else { $null }

    # Boyut: kucuk = hafif prim. log ile sikistir.
    $size = if ($null -ne $mcap -and $mcap -gt 0) { - [Math]::Log10($mcap) } else { $null }

    [ordered]@{
        ValEvEbitda = $valEvEbitda
        ValPb = $valPb
        ValPe = $valPe
        QualRoe = $qualRoe
        QualDebt = $qualDebt
        QualEbTrend = $qualEbTrend
        Mom = $mom
        LowVol = $lowVol
        Size = $size
    }
}

function Add-AcademicFactorScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Stocks,
        [hashtable]$CategoryWeights
    )

    if ($Stocks.Count -eq 0) { return $Stocks }

    if (-not $CategoryWeights) {
        # Uzun-yonlu, gelismekte olan piyasa egilimli literatur agirliklari.
        $CategoryWeights = @{
            Momentum = 0.30
            Quality = 0.25
            Value = 0.20
            LowVol = 0.20
            Size = 0.05
        }
    }

    # Her kategorinin alt-faktorleri (esit agirlikli ortalama).
    $categoryFactors = [ordered]@{
        Value = @('ValEvEbitda', 'ValPb', 'ValPe')
        Quality = @('QualRoe', 'QualDebt', 'QualEbTrend')
        Momentum = @('Mom')
        LowVol = @('LowVol')
        Size = @('Size')
    }
    $allFactorNames = @($categoryFactors.Values | ForEach-Object { $_ })

    $vectors = New-Object System.Collections.Generic.List[object]
    foreach ($s in $Stocks) { $vectors.Add((Get-AcademicFactorVector -Stock $s)) }

    # Kesitsel ortalama/standart sapma (populasyon).
    $stats = @{}
    foreach ($fn in $allFactorNames) {
        $vals = New-Object System.Collections.Generic.List[double]
        foreach ($v in $vectors) { if ($null -ne $v[$fn]) { $vals.Add([double]$v[$fn]) } }
        if ($vals.Count -ge 3) {
            $mean = ($vals | Measure-Object -Average).Average
            $var = 0.0; foreach ($x in $vals) { $var += ($x - $mean) * ($x - $mean) }
            $std = [Math]::Sqrt($var / $vals.Count)
        }
        else { $mean = 0.0; $std = 0.0 }
        $stats[$fn] = [pscustomobject]@{ Mean = $mean; Std = $std }
    }

    $composite = New-Object double[] $Stocks.Count
    for ($i = 0; $i -lt $Stocks.Count; $i++) {
        $v = $vectors[$i]
        $score = 0.0
        $weightUsed = 0.0
        foreach ($cat in $categoryFactors.Keys) {
            $zSum = 0.0; $zCount = 0
            foreach ($fn in $categoryFactors[$cat]) {
                $st = $stats[$fn]
                if ($st.Std -gt 1e-9 -and $null -ne $v[$fn]) {
                    $z = ([double]$v[$fn] - $st.Mean) / $st.Std
                    if ($z -gt 3) { $z = 3 } elseif ($z -lt -3) { $z = -3 }  # winsorize
                    $zSum += $z; $zCount++
                }
            }
            if ($zCount -gt 0) {
                $catZ = $zSum / $zCount
                $w = [double]$CategoryWeights[$cat]
                $score += $w * $catZ
                $weightUsed += $w
            }
        }
        # Eksik kategorileri telafi et (kullanilan agirliga normalize).
        $composite[$i] = if ($weightUsed -gt 1e-9) { $score / $weightUsed } else { 0.0 }
    }

    # Yuzdelik (0-100) sirala.
    $order = 0..($Stocks.Count - 1) | Sort-Object { $composite[$_] }
    $pct = New-Object double[] $Stocks.Count
    $n = $Stocks.Count
    for ($rank = 0; $rank -lt $n; $rank++) {
        $idx = $order[$rank]
        $pct[$idx] = if ($n -gt 1) { [Math]::Round(($rank / ($n - 1.0)) * 100, 1) } else { 50 }
    }

    for ($i = 0; $i -lt $Stocks.Count; $i++) {
        $mom = $vectors[$i]['Mom']
        $volD = Get-RfNumber (Get-ObjectPropertyValue -Object $Stocks[$i] -Name 'VolatilityD')
        $annVol = if ($null -ne $volD) { [double]$volD * [Math]::Sqrt(252.0) } else { $null }
        $riskAdjMom = if ($null -ne $mom -and $null -ne $annVol -and $annVol -gt 1e-9) {
            [Math]::Round([double]$mom / $annVol, 3)
        }
        else { $null }

        $Stocks[$i] | Add-Member -NotePropertyName AcademicFactorScore -NotePropertyValue ([Math]::Round($composite[$i], 4)) -Force
        $Stocks[$i] | Add-Member -NotePropertyName AcademicFactorScore100 -NotePropertyValue $pct[$i] -Force
        $Stocks[$i] | Add-Member -NotePropertyName Momentum12_1Pct -NotePropertyValue $(if ($null -ne $mom) { [Math]::Round([double]$mom, 2) } else { $null }) -Force
        $Stocks[$i] | Add-Member -NotePropertyName AnnualizedVolatilityPct -NotePropertyValue $(if ($null -ne $annVol) { [Math]::Round([double]$annVol, 2) } else { $null }) -Force
        $Stocks[$i] | Add-Member -NotePropertyName RiskAdjustedMomentum -NotePropertyValue $riskAdjMom -Force
    }

    return $Stocks
}

# ============================================================================
# Bilanço zamanlaması, veri kalitesi, bilanço sürprizi (PEAD) ve KAP.
# ============================================================================

function Add-EarningsTiming {
    <#
        Her hisseye bilanco zamanlama alanlari ekler:
        DaysToNextEarnings, DaysSinceLastReport, EarningsSurpriseScore.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Stocks,
        [datetime]$AsOf = (Get-Date)
    )

    foreach ($s in $Stocks) {
        $next = Get-ObjectPropertyValue -Object $s -Name 'NextEarningsDate'
        $last = Get-ObjectPropertyValue -Object $s -Name 'LatestReportDate'
        $dNext = if ($next -is [datetime]) { [int][Math]::Ceiling(($next.Date - $AsOf.Date).TotalDays) } else { $null }
        $dLast = if ($last -is [datetime]) { [int][Math]::Floor(($AsOf.Date - $last.Date).TotalDays) } else { $null }
        $surprise = Get-EarningsSurpriseScore -Stock $s
        $s | Add-Member -NotePropertyName DaysToNextEarnings -NotePropertyValue $dNext -Force
        $s | Add-Member -NotePropertyName DaysSinceLastReport -NotePropertyValue $dLast -Force
        $s | Add-Member -NotePropertyName EarningsSurpriseScore -NotePropertyValue $surprise -Force

        # Bilanço öncesi run-up (öncü sinyal): olay çalışmasinda iyi bilanço
        # aciklama oncesi fiyat yukselisiyle haber veriyordu (r~0.26). 8-25 gun
        # kala + guclenen fiyat/hacim.
        $price = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'Price')
        $sma20 = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'SMA20')
        $sma50 = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'SMA50')
        $relVol = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'RelativeVolume')
        $perfMonth = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'PerfMonth')
        $macdHist = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'MacdHistogram')
        $rsi = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'RSI')

        $preRunup = $false
        if ($null -ne $dNext -and $dNext -ge 8 -and $dNext -le 25 -and
            $null -ne $price -and $null -ne $sma20 -and $sma20 -gt 0 -and $price -ge $sma20 -and
            $null -ne $sma50 -and $sma50 -gt 0 -and $sma20 -ge $sma50 -and
            $null -ne $relVol -and $relVol -ge 1.1 -and
            (($null -ne $perfMonth -and $perfMonth -gt 0) -or ($null -ne $macdHist -and $macdHist -ge 0))) {
            $preRunup = $true
        }

        # Açıklama sonrası "sell-the-news" riski: olay çalismasinda pozitif
        # surprizliler ~1 ay sonra geri veriyordu (-%4.9). Yeni aciklamis +
        # pozitif surpriz + asiri uzamis/asiri alim.
        $sellTheNews = $false
        if ($null -ne $dLast -and $dLast -ge 0 -and $dLast -le 15 -and
            $null -ne $surprise -and $surprise -ge 60 -and
            ((($null -ne $price -and $null -ne $sma20 -and $sma20 -gt 0) -and (($price / $sma20) - 1.0) -gt 0.10) -or
             ($null -ne $rsi -and $rsi -gt 65))) {
            $sellTheNews = $true
        }

        $s | Add-Member -NotePropertyName PreEarningsRunupActive -NotePropertyValue $preRunup -Force
        $s | Add-Member -NotePropertyName SellTheNewsRisk -NotePropertyValue $sellTheNews -Force
    }

    return $Stocks
}

function Get-SignalCalibration {
    <#
        Aktif sinyal kalibrasyonunu doner. Set-SignalCalibration ile yuklenmemisse
        guvenli varsayilanlar (tarihsel olay calismasi: sell-the-news = -5).
    #>
    if ($null -ne $script:SignalCalibration) { return $script:SignalCalibration }
    return [pscustomobject][ordered]@{
        UpdatedAt = $null
        PreEarningsRunupBonus = 3.0
        PostEarningsAdjustment = -3.0
        Calibrated = $false
        SampleCount = 0
        Note = 'Varsayilan degerler (henuz kalibre edilmedi).'
    }
}

function Set-SignalCalibration {
    param($Calibration)
    $script:SignalCalibration = $Calibration
}

function Get-SignalConfig {
    <#
        KENDI KENDINE AYAR config'i (sinyal basina buyukluk carpani). Invoke-
        SignalEvaluation, onceden-taahhut cikis kuralindan (Get-SignalVerdict)
        bu dosyayi OTOMATIK yazar; GunlukRapor yukler; akilli-para ve makro-rejim
        ayarlari carpaniyla olceklenir. Yuklenmemisse VARSAYILAN 1.0 (davranis
        degismez). Bu, 'yeterli veri birikince otomatik uygula, yoksa bekle'
        dongusunun (auto-calibrate deseni) yeni sinyallere genislemesidir.
    #>
    if ($null -ne $script:SignalConfig) { return $script:SignalConfig }
    return [pscustomobject][ordered]@{
        UpdatedAt = $null
        SmartMoneyMult = 1.0
        MacroRegimeMult = 1.0
        Note = 'Varsayilan (henuz oto-ayar yok; tam olcek).'
    }
}

function Set-SignalConfig {
    <#
        Config'i NORMALIZE ederek yukler: carpanlar [0,1] araligina kirpilir.
        Guvenlik: bozuk/elle-duzenlenmis dosyadaki negatif carpan sinyali TERS
        cevirir, >1 carpan tavan tasarimini asar — ikisi de engellenir.
    #>
    param($Config)
    if ($null -eq $Config) { $script:SignalConfig = $null; return }
    $clamp01 = { param($v) $d = ConvertTo-DoubleOrNull $v; if ($null -eq $d) { 1.0 } else { [Math]::Max(0.0, [Math]::Min(1.0, $d)) } }
    $script:SignalConfig = [pscustomobject][ordered]@{
        UpdatedAt = [string](Get-ObjectPropertyValue -Object $Config -Name 'UpdatedAt')
        SmartMoneyMult = & $clamp01 (Get-ObjectPropertyValue -Object $Config -Name 'SmartMoneyMult')
        MacroRegimeMult = & $clamp01 (Get-ObjectPropertyValue -Object $Config -Name 'MacroRegimeMult')
        Note = [string](Get-ObjectPropertyValue -Object $Config -Name 'Note')
    }
}

function Get-MacroSnapshotMetric {
    <#
        Makro snapshot'tan Id ile TEK metrigi ceker (XU100 vb.). Ayni arama
        kalibi 3 yerde tekrarlaniyordu (PIT kaydi, nakit-hedefi, devre kesici) —
        tek yardimciya indirildi. Bulunamazsa $null.
    #>
    param($Snapshot, [string]$Id)
    return @(Get-ObjectPropertyValue -Object $Snapshot -Name 'Metrics') |
        Where-Object { [string](Get-ObjectPropertyValue -Object $_ -Name 'Id') -eq $Id } |
        Select-Object -First 1
}

function Get-EarningsTimingAdjustment {
    <#
        Bilanço zamanlamasina dayali imzali skor ayari. Buyukluk/yon kalibrasyon
        state'inden gelir (kendini ogrenen): bilanço oncesi run-up bonusu ve
        bilanço sonrasi ayar (sell-the-news cezasi <-> PEAD bonusu). Kalibrasyon
        yoksa tarihsel olay calismasi varsayilanlari kullanilir. Sinirli kalir.
    #>
    param($Stock)

    $cal = Get-SignalCalibration
    $adj = 0.0
    if ([bool](Get-ObjectPropertyValue -Object $Stock -Name 'PreEarningsRunupActive')) {
        $adj += [double]$cal.PreEarningsRunupBonus
    }
    if ([bool](Get-ObjectPropertyValue -Object $Stock -Name 'SellTheNewsRisk')) {
        $adj += [double]$cal.PostEarningsAdjustment
    }
    return $adj
}

function Get-CircuitBreakerState {
    <#
        DEVRE KESICI (SAF): portfoyun KENDI drawdown'i savunmayi tetikler; BIST100'un
        SMA50'ye gore konumu KURTARMA kapisidir (piyasa donunce freni gevset).
        Simetrik whipsaw korumasi: dusuktesin ama piyasa toparliyorsa fren hafifler.

        Esikler: >-15% NORMAL | -15..-20% UYARI (yeni alim dur, en zayifi kirp) |
                 <-20% DERISK (yari nakit). Piyasa SMA50 ustundeyse bir kademe hafifler.

        Bugun GOLGE: durum loglanir + panelde gosterilir; canli de-risk YURUTMESI
        config bayragi (BIST_CIRCUIT_BREAKER_LIVE) arkasinda, VARSAYILAN KAPALI.
        Kurtarma kapisi whipsaw'i azaltir ama tarihsel kanit birikene kadar canli DEGIL.

        Doner: { state; action; targetCashPct; note }.
    #>
    param(
        [double]$DrawdownPct,               # negatif (or. -18.5)
        $Bist100AboveSma50 = $null          # $true/$false/$null
    )
    $marketUp = ($Bist100AboveSma50 -eq $true)
    if ($DrawdownPct -le -20) {
        if ($marketUp) { return [pscustomobject]@{ state = 'RECOVER'; action = 'kademeli geri giris'; targetCashPct = 25; note = "Drawdown %$([Math]::Round($DrawdownPct,1)) ama BIST SMA50 üstü — fren gevşiyor." } }
        return [pscustomobject]@{ state = 'DERISK'; action = 'yarı nakde geç'; targetCashPct = 50; note = "Drawdown %$([Math]::Round($DrawdownPct,1)); piyasa zayıf — savunma." }
    }
    if ($DrawdownPct -le -15) {
        if ($marketUp) { return [pscustomobject]@{ state = 'NORMAL'; action = 'değişiklik yok'; targetCashPct = 0; note = "Drawdown %$([Math]::Round($DrawdownPct,1)) ama BIST SMA50 üstü — fren yok." } }
        return [pscustomobject]@{ state = 'UYARI'; action = 'yeni alım dur, en zayıfı kırp'; targetCashPct = 15; note = "Drawdown %$([Math]::Round($DrawdownPct,1)); yeni risk alma." }
    }
    return [pscustomobject]@{ state = 'NORMAL'; action = 'değişiklik yok'; targetCashPct = 0; note = 'Drawdown sınırlar içinde.' }
}

function Get-RegimeCashTarget {
    <#
        REJIM-GUDUMLU NAKIT HEDEFI (SAF). Rejim etiketi + BIST100'un SMA200'e gore
        konumundan savunmaci nakit orani uretir (0.0 - 0.40). Iki bagimsiz savunma
        sinyali (risk-off VE trend-altı) tam savunmayi tetikler; tek sinyal yarim.

        Bugun YALNIZ OLCUM: regime_log'a ve PIT'e yazilir, ileri-getiri ile faydasi
        signal-eval'de olculur. CANLI TAHSISI DEGISTIRMEZ (once kanit, sonra pilot).

        Doner: 0.40 (risk-off + trend-alti) | 0.20 (tek savunma) | 0.10 (notr) |
               0.0 (risk-on + trend-ustu). Veri eksikse notr 0.10 tabani.
    #>
    param(
        [string]$RegimeLabel,
        $Bist100BelowSma200   # $true / $false / $null (bilinmiyor)
    )
    $riskOff = $RegimeLabel -eq 'risk-off'
    $riskOn = $RegimeLabel -eq 'risk-on'
    $below = ($Bist100BelowSma200 -eq $true)
    $aboveKnown = ($Bist100BelowSma200 -eq $false)
    if ($riskOff -and $below) { return 0.40 }
    if ($riskOff -or $below) { return 0.20 }
    if ($riskOn -and $aboveKnown) { return 0.0 }
    return 0.10
}

function Get-SignalVerdict {
    <#
        ONCEDEN TAAHHUT EDILMIS cikis kurali (SAF): bir ayarin ileri-getiri IC'si
        ve donemler-arasi t-istatistiginden karar uretir. Amac: karar gununde
        "biraz daha bekleyelim" onyargisini onlemek — kural simdi yazili.

        - Yetersiz ornek (Samples < MinSamples): 'YETERSIZ' (karar yok, veri bekle)
        - meanIC < 0 ve |t| >= 1.5      : 'KAPAT'   (ayar 0'a cekilmeli — zararli)
        - |t| < 2 (zayif kanit)          : 'ZAYIFLAT' (buyukluk yariya)
        - meanIC > 0 ve t >= 2           : 'KORU'    (kanitli; buyukluk korunur)
        - diger                          : 'IZLE'    (notr; degisiklik yok)
    #>
    param(
        [double]$MeanIC,
        [double]$TStat,
        [int]$Samples,
        [int]$MinSamples = 6
    )
    if ($Samples -lt $MinSamples) { return [pscustomobject]@{ verdict = 'YETERSIZ'; action = 'veri bekle'; reason = "yalniz $Samples donem (>= $MinSamples gerekli)" } }
    if ($MeanIC -lt 0 -and [Math]::Abs($TStat) -ge 1.5) { return [pscustomobject]@{ verdict = 'KAPAT'; action = 'buyukluk 0'; reason = "negatif IC ($([Math]::Round($MeanIC,3))), |t|=$([Math]::Round([Math]::Abs($TStat),2))" } }
    if ([Math]::Abs($TStat) -lt 2.0) { return [pscustomobject]@{ verdict = 'ZAYIFLAT'; action = 'buyukluk x0.5'; reason = "zayif kanit |t|=$([Math]::Round([Math]::Abs($TStat),2)) < 2" } }
    if ($MeanIC -gt 0 -and $TStat -ge 2.0) { return [pscustomobject]@{ verdict = 'KORU'; action = 'degisiklik yok'; reason = "kanitli pozitif IC ($([Math]::Round($MeanIC,3))), t=$([Math]::Round($TStat,2))" } }
    return [pscustomobject]@{ verdict = 'IZLE'; action = 'degisiklik yok'; reason = 'notr' }
}

function Add-HoldingFlag {
    <#
        config/holdings.json statik listesindeki hisselere IsHolding=$true isler.
        Holdingler TradingView'da tutarsiz etiketlendigi icin (bazi 'Finance')
        bu bayrak Get-BistScore'da TEK TIP muamele (PB-agirlikli deger, FD/FAVOK+
        borc muaf) saglar. Best-effort: dosya yoksa hicbir hisse isaretlenmez.
    #>
    [CmdletBinding()]
    param([object[]]$Stocks = @(), [string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Join-Path $PSScriptRoot 'config\holdings.json' }
    $set = @{}
    try {
        if (Test-Path -LiteralPath $Path) {
            $doc = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($s in @(Get-ObjectPropertyValue -Object $doc -Name 'symbols')) {
                $u = ([string]$s).Trim().ToUpperInvariant()
                if ($u) { $set[$u] = $true }
            }
        }
    }
    catch { $set = @{} }
    if ($set.Count -eq 0) { return @($Stocks) }
    foreach ($stock in $Stocks) {
        if ($null -eq $stock) { continue }
        $sym = ([string](Get-ObjectPropertyValue -Object $stock -Name 'Symbol')).Trim().ToUpperInvariant()
        if ($sym -and $set.ContainsKey($sym)) {
            $stock | Add-Member -NotePropertyName 'IsHolding' -NotePropertyValue $true -Force
        }
    }
    return @($Stocks)
}

function Add-ForeignOwnershipData {
    <#
        data/mkk_foreign.json'daki (haftalik MKK collector) hisse bazli yabanci
        saklama oranini tarama evrenine isler: her hisseye ForeignPct,
        ForeignChg1wBps, ForeignChg1mBps alanlari eklenir. Dosya yoksa/bozuksa
        hisseler DEGISMEDEN doner (veri-kapili; skor ayari 0 kalir).
    #>
    [CmdletBinding()]
    param(
        [object[]]$Stocks = @(),
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Join-Path $PSScriptRoot 'data\mkk_foreign.json' }
    $items = $null
    try {
        if (Test-Path -LiteralPath $Path) {
            $ff = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            $items = Get-ObjectPropertyValue -Object $ff -Name 'items'
        }
    }
    catch { $items = $null }
    if ($null -eq $items) { return @($Stocks) }
    foreach ($stock in $Stocks) {
        if ($null -eq $stock) { continue }
        $sym = [string](Get-ObjectPropertyValue -Object $stock -Name 'Symbol')
        if ([string]::IsNullOrWhiteSpace($sym)) { continue }
        $rec = Get-ObjectPropertyValue -Object $items -Name $sym.ToUpperInvariant()
        if ($null -eq $rec) { continue }
        $stock | Add-Member -NotePropertyName 'ForeignPct' -NotePropertyValue (ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $rec -Name 'foreignPct')) -Force
        $stock | Add-Member -NotePropertyName 'ForeignChg1wBps' -NotePropertyValue (ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $rec -Name 'chg1wBps')) -Force
        $stock | Add-Member -NotePropertyName 'ForeignChg1mBps' -NotePropertyValue (ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $rec -Name 'chg1mBps')) -Force
    }
    return @($Stocks)
}

function Add-InsiderSignalData {
    <#
        data/kap_enrichment.json'daki icsel islem (insider) bildirimlerinden son
        -MaxAgeDays gun icin hisse bazli yonlu sinyal isler: InsiderSignal '+'
        (net alim) / '-' (net satim). Ayni hissede iki yon varsa yeni tarihli
        kazanir. Kategori/onem alaninda 'insider' aranir; LLM yonu
        (directionRefined) esas, yoksa directionHint. Veri-kapili: dosya yoksa
        veya insider kaydi yoksa hicbir alan eklenmez (ayar 0 kalir).
    #>
    [CmdletBinding()]
    param(
        [object[]]$Stocks = @(),
        [string]$Path,
        [datetime]$AsOf = (Get-Date),
        [int]$MaxAgeDays = 7
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Join-Path $PSScriptRoot 'data\kap_enrichment.json' }
    $bySym = @{}
    try {
        if (Test-Path -LiteralPath $Path) {
            $enr = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            $items = Get-ObjectPropertyValue -Object $enr -Name 'items'
            if ($null -ne $items) {
                foreach ($prop in $items.PSObject.Properties) {
                    $it = $prop.Value
                    $catImp = ('{0} {1}' -f [string](Get-ObjectPropertyValue -Object $it -Name 'category'), [string](Get-ObjectPropertyValue -Object $it -Name 'importance')).ToLowerInvariant()
                    if ($catImp -notmatch 'insider|icsel|içsel') { continue }
                    $sym = ([string](Get-ObjectPropertyValue -Object $it -Name 'symbol')).Trim().ToUpperInvariant()
                    if (-not $sym) { continue }
                    $dir = [string](Get-ObjectPropertyValue -Object $it -Name 'directionRefined')
                    if ($dir -notin @('+', '-')) { $dir = [string](Get-ObjectPropertyValue -Object $it -Name 'directionHint') }
                    if ($dir -notin @('+', '-')) { continue }
                    $dt = $null
                    try { $dt = [datetime]::ParseExact([string](Get-ObjectPropertyValue -Object $it -Name 'date'), 'dd.MM.yyyy HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture) } catch { continue }
                    if (($AsOf - $dt).TotalDays -gt $MaxAgeDays -or $dt -gt $AsOf.AddDays(1)) { continue }
                    if (-not $bySym.ContainsKey($sym) -or $dt -gt $bySym[$sym].Date) {
                        $bySym[$sym] = [pscustomobject]@{ Direction = $dir; Date = $dt }
                    }
                }
            }
        }
    }
    catch { $bySym = @{} }
    if ($bySym.Count -eq 0) { return @($Stocks) }
    foreach ($stock in $Stocks) {
        if ($null -eq $stock) { continue }
        $sym = ([string](Get-ObjectPropertyValue -Object $stock -Name 'Symbol')).Trim().ToUpperInvariant()
        if ($sym -and $bySym.ContainsKey($sym)) {
            $stock | Add-Member -NotePropertyName 'InsiderSignal' -NotePropertyValue ([string]$bySym[$sym].Direction) -Force
        }
    }
    return @($Stocks)
}

function Get-SmartMoneyAdjustment {
    <#
        "Akilli para" imzali skor ayari — SINIRLI [-6, +6] ve VERI-KAPILI.

        Girdiler (Add-ForeignOwnershipData / Add-InsiderSignalData isledigi alanlar):
          - ForeignChg1wBps: yabanci saklama oraninin 1 haftalik degisimi (puan).
            EM literatüründe yabanci akis momentumu kisa vadeli pozitif ongorucudur
            (Froot-O'Connell-Seasholes 2001; BIST calismalari ayni yonde).
            Basamaklar: >=+0.75 -> +4 | +0.30..0.75 -> +2.5 | +0.10..0.30 -> +1
                        <=-0.75 -> -4 | -0.30..-0.75 -> -2.5 | -0.10..-0.30 -> -1
          - ForeignChg1mBps: ayni yonde >=|0.5| ise +-1 teyit.
          - InsiderSignal: son 7 gunde icsel islem bildirimi ('+' alim -> +2,
            '-' satim -> -2). Icsel alimlarin pozitif anormal getirisi genis
            literaturle desteklenir (Lakonishok-Lee 2001 vb.).

        Veri yoksa 0 doner (mevcut davranis birebir korunur). Buyukluk sinirli
        tutulur: kanit PIT arsivinde biriktikce esikler kalibre edilebilir.
    #>
    param($Stock)

    $adj = 0.0
    $chg1w = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $Stock -Name 'ForeignChg1wBps')
    if ($null -ne $chg1w) {
        if ($chg1w -ge 0.75) { $adj += 4.0 }
        elseif ($chg1w -ge 0.30) { $adj += 2.5 }
        elseif ($chg1w -ge 0.10) { $adj += 1.0 }
        elseif ($chg1w -le -0.75) { $adj -= 4.0 }
        elseif ($chg1w -le -0.30) { $adj -= 2.5 }
        elseif ($chg1w -le -0.10) { $adj -= 1.0 }
        $chg1m = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $Stock -Name 'ForeignChg1mBps')
        if ($null -ne $chg1m -and [Math]::Abs($chg1m) -ge 0.5 -and ($chg1m * $chg1w) -gt 0) {
            $adj += ([Math]::Sign($chg1w) * 1.0)
        }
    }
    $insider = [string](Get-ObjectPropertyValue -Object $Stock -Name 'InsiderSignal')
    if ($insider -eq '+') { $adj += 2.0 }
    elseif ($insider -eq '-') { $adj -= 2.0 }

    # Oto-ayar carpani (signal_config; varsayilan 1.0). Cikis kurali KAPAT
    # verdiyse 0, ZAYIFLAT verdiyse 0.5 olur -> sinyal veriye gore olceklenir.
    $adj *= [double](Get-SignalConfig).SmartMoneyMult

    if ($adj -gt 6.0) { $adj = 6.0 }
    elseif ($adj -lt -6.0) { $adj = -6.0 }
    return $adj
}

function Update-SignalCalibration {
    <#
        Kendini ogrenen kalibrasyon. Canli PEAD takipcisinin (earnings_reactions)
        TAMAMLANMIS yonlu orneklerinden, pozitif surprizli hisselerin bilanço
        sonrasi ortalama suruklenmesini olcer ve bilanço sonrasi skor ayarini
        (sell-the-news cezasi <-> PEAD bonusu) VERIYE GORE gunceller. Yeterli
        ornek yoksa guvenli varsayilana duser. Buyukluk sinirlidir [-8, +6].
    #>
    [CmdletBinding()]
    param(
        $Reactions,
        [datetime]$AsOf = (Get-Date),
        [int]$MinSamples = 30,
        [int]$MinPositive = 10,
        [double]$Scale = 0.6
    )

    $bonus = 3.0
    $postAdj = -3.0
    $calibrated = $false
    $meanPos = $null
    $hitPos = $null

    $completed = @(Get-ObjectPropertyValue -Object $Reactions -Name 'Completed')
    $directional = @($completed | Where-Object { [bool](Get-ObjectPropertyValue -Object $_ -Name 'Directional') })
    $n = $directional.Count

    $posDrifts = @($directional | Where-Object {
            $sp = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $_ -Name 'SurpriseScore')
            $null -ne $sp -and $sp -ge 55
        } | ForEach-Object { [double](Get-ObjectPropertyValue -Object $_ -Name 'DriftPct') })

    if ($n -ge $MinSamples -and $posDrifts.Count -ge $MinPositive) {
        $meanPos = [Math]::Round((($posDrifts | Measure-Object -Average).Average), 2)
        $hitPos = [Math]::Round((@($posDrifts | Where-Object { $_ -gt 0 }).Count / [double]$posDrifts.Count) * 100, 1)
        $postAdj = [Math]::Round([Math]::Max(-8.0, [Math]::Min(6.0, [double]$meanPos * $Scale)), 2)
        $calibrated = $true
    }

    $note = if ($calibrated) {
        "Kalibre edildi: n=$n yönlü örnek, pozitif sürpriz ort. drift %$meanPos (isabet %$hitPos) -> bilanço sonrası ayar $postAdj."
    }
    else {
        "Yetersiz örnek (yönlü=$n/$MinSamples, pozitif=$($posDrifts.Count)/$MinPositive); varsayılan ayar -3 kullanılıyor."
    }

    return [pscustomobject][ordered]@{
        UpdatedAt = $AsOf.ToString('o')
        PreEarningsRunupBonus = $bonus
        PostEarningsAdjustment = $postAdj
        Calibrated = $calibrated
        SampleCount = $n
        PositiveSampleCount = $posDrifts.Count
        PositiveMeanDriftPct = $meanPos
        PositiveDriftHitRatePct = $hitPos
        Note = $note
    }
}

function Get-EarningsSurpriseScore {
    <#
        Bilanco "surpriz/kalite" proxy'si (0-100, 50 notr). Gercek konsensus
        tahmini ucretsiz yok; USD net kar Y/Y, USD FAVOK Y/Y, FAVOK ardisik
        artis ve pozitif ceyrek sayisindan bilesik bir vekil uretir. PEAD
        (bilanco sonrasi suruklenme) takibinde "surpriz yonu" olarak kullanilir.
    #>
    param($Stock)

    $ni = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $Stock -Name 'NetIncomeUsdYoYPct')
    $eb = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $Stock -Name 'EbitdaUsdYoYPct')
    $seq = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $Stock -Name 'EbitdaSequentialIncreaseCount')
    $posq = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $Stock -Name 'PositiveQuarterCount')

    if ($null -eq $ni -and $null -eq $eb) { return $null }

    $score = 0.0
    if ($null -ne $ni) { $score += [Math]::Max(-40, [Math]::Min(40, $ni * 0.4)) }
    if ($null -ne $eb) { $score += [Math]::Max(-30, [Math]::Min(30, $eb * 0.3)) }
    if ($null -ne $seq) { $score += [Math]::Min(20, $seq * 5) }
    if ($null -ne $posq) { $score += [Math]::Min(10, $posq * 2) }

    return [Math]::Round([Math]::Max(0, [Math]::Min(100, 50 + $score)), 1)
}

function Add-DataQualityAssessment {
    <#
        Her hisseye veri-kalite bayraklari (DataQualityFlags) ve DataQualityOk
        (kritik sorun yoksa $true) ekler. Bayat bilanco, eksik kritik alan,
        gecersiz fiyat ve dusuk likiditeyi yakalar. Skoru DEGISTIRMEZ; portfoy
        uygunlugu ve raporda seffaflik icin kullanilir.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Stocks,
        [datetime]$AsOf = (Get-Date),
        [int]$StaleReportDays = 135
    )

    foreach ($s in $Stocks) {
        $flags = [System.Collections.Generic.List[string]]::new()
        $critical = $false

        $price = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'Price')
        if ($null -eq $price -or $price -le 0) { [void]$flags.Add('Geçersiz/eksik fiyat'); $critical = $true }

        $pe = Get-ObjectPropertyValue -Object $s -Name 'PE'
        $pb = Get-ObjectPropertyValue -Object $s -Name 'PB'
        $roe = Get-ObjectPropertyValue -Object $s -Name 'ROE'
        if ($null -eq $pe -and $null -eq $pb -and $null -eq $roe) { [void]$flags.Add('Temel veriler eksik') }

        $dLast = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'DaysSinceLastReport')
        if ($null -ne $dLast -and $dLast -gt $StaleReportDays) {
            [void]$flags.Add("Bilanço bayat olabilir ($([int]$dLast) gün)")
        }

        $avgVol = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'AverageVolume10D')
        if ($null -ne $avgVol -and $avgVol -lt 50000) { [void]$flags.Add('Çok düşük likidite'); $critical = $true }
        elseif ($null -ne $avgVol -and $avgVol -lt 150000) { [void]$flags.Add('Düşük likidite') }

        $s | Add-Member -NotePropertyName DataQualityFlags -NotePropertyValue ($flags.ToArray()) -Force
        $s | Add-Member -NotePropertyName DataQualityOk -NotePropertyValue (-not $critical) -Force
    }

    return $Stocks
}

function Update-EarningsReactions {
    <#
        PEAD (Post-Earnings Announcement Drift) takibi. Yeni bilanco aciklamis
        hisseleri (DaysSinceLastReport kucuk) tespit anindaki fiyat + surpriz
        skoruyla kaydeder; drift penceresi (varsayilan ~20 islem gunu ~ 28
        takvim gunu) dolunca tespit fiyatina gore getiriyi (drift) hesaplar ve
        "pozitif surpriz -> pozitif drift" isabet oranini biriktirir.
        State JSON ile saklanir (cache yerine git'te kalici).
    #>
    [CmdletBinding()]
    param(
        $Previous,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Stocks,
        [datetime]$AsOf = (Get-Date),
        [int]$DetectWithinDays = 4,
        [int]$DriftWindowDays = 28,
        [int]$MaxCompleted = 200
    )

    $priceMap = @{}
    $surpriseMap = @{}
    $sinceMap = @{}
    foreach ($s in $Stocks) {
        $sym = [string](Get-ObjectPropertyValue -Object $s -Name 'Symbol')
        if ([string]::IsNullOrWhiteSpace($sym)) { continue }
        $p = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'Price')
        if ($null -ne $p -and $p -gt 0 -and -not $priceMap.ContainsKey($sym)) {
            $priceMap[$sym] = [double]$p
            $surpriseMap[$sym] = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'EarningsSurpriseScore')
            $sinceMap[$sym] = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'DaysSinceLastReport')
        }
    }

    $tracked = [System.Collections.Generic.List[object]]::new()
    $completed = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Previous) {
        foreach ($t in @(Get-ObjectPropertyValue -Object $Previous -Name 'Tracked')) { if ($null -ne $t) { [void]$tracked.Add($t) } }
        foreach ($c in @(Get-ObjectPropertyValue -Object $Previous -Name 'Completed')) { if ($null -ne $c) { [void]$completed.Add($c) } }
    }

    $trackedKeys = @{}
    foreach ($t in $tracked) {
        $k = '{0}|{1}' -f [string](Get-ObjectPropertyValue -Object $t -Name 'Symbol'), [string](Get-ObjectPropertyValue -Object $t -Name 'ReportDate')
        $trackedKeys[$k] = $true
    }

    # 1) Yeni aciklamis hisseleri izlemeye al.
    foreach ($s in $Stocks) {
        $sym = [string](Get-ObjectPropertyValue -Object $s -Name 'Symbol')
        if ([string]::IsNullOrWhiteSpace($sym)) { continue }
        $since = $sinceMap[$sym]
        $reportDate = Get-ObjectPropertyValue -Object $s -Name 'LatestReportDate'
        $surprise = $surpriseMap[$sym]
        if ($null -eq $since -or $since -lt 0 -or $since -gt $DetectWithinDays) { continue }
        if (-not $priceMap.ContainsKey($sym) -or $null -eq $surprise) { continue }
        $rdText = if ($reportDate -is [datetime]) { $reportDate.ToString('yyyy-MM-dd') } else { [string]$reportDate }
        $k = '{0}|{1}' -f $sym, $rdText
        if ($trackedKeys.ContainsKey($k)) { continue }
        $trackedKeys[$k] = $true
        [void]$tracked.Add([pscustomobject][ordered]@{
                Symbol = $sym
                ReportDate = $rdText
                DetectedAt = $AsOf.ToString('o')
                EntryPrice = $priceMap[$sym]
                SurpriseScore = $surprise
            })
    }

    # 2) Drift penceresi dolanlari tamamla.
    $stillTracked = [System.Collections.Generic.List[object]]::new()
    $newlyCompleted = $null
    foreach ($t in $tracked) {
        $sym = [string](Get-ObjectPropertyValue -Object $t -Name 'Symbol')
        $detectedAtRaw = [string](Get-ObjectPropertyValue -Object $t -Name 'DetectedAt')
        $entry = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $t -Name 'EntryPrice')
        $detectedAt = $null
        try { $detectedAt = [datetime]::Parse($detectedAtRaw, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) } catch { $detectedAt = $null }
        $elapsed = if ($null -ne $detectedAt) { ($AsOf.Date - $detectedAt.Date).TotalDays } else { $null }

        if ($null -ne $elapsed -and $elapsed -ge $DriftWindowDays -and $priceMap.ContainsKey($sym) -and $null -ne $entry -and $entry -gt 0) {
            $drift = (($priceMap[$sym] / $entry) - 1.0) * 100.0
            $surprise = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $t -Name 'SurpriseScore')
            $positiveSurprise = ($null -ne $surprise -and $surprise -ge 55)
            $negativeSurprise = ($null -ne $surprise -and $surprise -le 45)
            $hit = ($positiveSurprise -and $drift -gt 0) -or ($negativeSurprise -and $drift -lt 0)
            [void]$completed.Add([pscustomobject][ordered]@{
                    Symbol = $sym
                    ReportDate = [string](Get-ObjectPropertyValue -Object $t -Name 'ReportDate')
                    CompletedAt = $AsOf.ToString('o')
                    SurpriseScore = $surprise
                    DriftPct = [Math]::Round($drift, 2)
                    DirectionalHit = $hit
                    Directional = ($positiveSurprise -or $negativeSurprise)
                })
        }
        else {
            [void]$stillTracked.Add($t)
        }
    }

    while ($completed.Count -gt $MaxCompleted) { $completed.RemoveAt(0) }

    # Ozet: yonlu (belirgin surprizli) tamamlanmislarda isabet orani + ortalama drift.
    $directional = @($completed | Where-Object { [bool](Get-ObjectPropertyValue -Object $_ -Name 'Directional') })
    $hits = @($directional | Where-Object { [bool](Get-ObjectPropertyValue -Object $_ -Name 'DirectionalHit') }).Count
    $peadHitRate = if ($directional.Count -gt 0) { [Math]::Round(($hits / [double]$directional.Count) * 100.0, 1) } else { $null }
    $posDrift = @($completed | Where-Object { $s2 = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $_ -Name 'SurpriseScore'); $null -ne $s2 -and $s2 -ge 55 } | ForEach-Object { [double](Get-ObjectPropertyValue -Object $_ -Name 'DriftPct') })
    $avgPosDrift = if ($posDrift.Count -gt 0) { [Math]::Round((($posDrift | Measure-Object -Average).Average), 2) } else { $null }

    return [pscustomobject][ordered]@{
        UpdatedAt = $AsOf.ToString('o')
        Summary = [pscustomobject][ordered]@{
            TrackedCount = $stillTracked.Count
            CompletedCount = $completed.Count
            DirectionalCount = $directional.Count
            PeadHitRatePct = $peadHitRate
            AvgPositiveSurpriseDriftPct = $avgPosDrift
        }
        Tracked = $stillTracked.ToArray()
        Completed = $completed.ToArray()
    }
}

function Get-KapDisclosures {
    <#
        KAP (Kamuyu Aydinlatma Platformu) son bildirimleri - BEST EFFORT.
        KAP'in resmi ucretsiz API'si yoktur; SPA ic ucu tarayici benzeri
        header'larla denenir. Her tur hata sessizce yutulur ve BOS dizi doner;
        boylece rapor akisi asla bozulmaz (deneysel ozellik).
        Donen kayitlar normalize edilir: Symbol, Title, Kind, Date.
    #>
    [CmdletBinding()]
    param(
        [int]$TimeoutSec = 6,
        [int]$Limit = 40
    )

    $headers = @{
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
        'Accept' = 'application/json, text/plain, */*'
        'Accept-Language' = 'tr-TR,tr;q=0.9'
        'Referer' = 'https://www.kap.org.tr/tr/bildirim-sorgu'
    }
    $endpoints = @(
        'https://www.kap.org.tr/tr/api/disclosures',
        'https://www.kap.org.tr/tr/api/memberDisclosureQuery'
    )

    $raw = $null
    foreach ($url in $endpoints) {
        try {
            $raw = Invoke-WithRetry -OperationName "KAP $url" -MaxAttempts 1 -BaseDelaySec 1 -ScriptBlock {
                Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec $TimeoutSec -ErrorAction Stop
            }
            if ($null -ne $raw) { break }
        }
        catch { $raw = $null }
    }
    if ($null -eq $raw) { return @() }

    # Donen yapi bilinmeyebilir; toleransli alan eslemesi yapilir.
    $items = $raw
    if ($null -ne (Get-ObjectPropertyValue -Object $raw -Name 'disclosures')) { $items = Get-ObjectPropertyValue -Object $raw -Name 'disclosures' }
    elseif ($null -ne (Get-ObjectPropertyValue -Object $raw -Name 'value')) { $items = Get-ObjectPropertyValue -Object $raw -Name 'value' }

    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($it in @($items)) {
        if ($null -eq $it) { continue }
        $sym = [string](Get-ObjectPropertyValue -Object $it -Name 'stockCodes')
        if ([string]::IsNullOrWhiteSpace($sym)) { $sym = [string](Get-ObjectPropertyValue -Object $it -Name 'ticker') }
        if ([string]::IsNullOrWhiteSpace($sym)) { $sym = [string](Get-ObjectPropertyValue -Object $it -Name 'companyName') }
        $title = [string](Get-ObjectPropertyValue -Object $it -Name 'title')
        if ([string]::IsNullOrWhiteSpace($title)) { $title = [string](Get-ObjectPropertyValue -Object $it -Name 'summary') }
        $kind = [string](Get-ObjectPropertyValue -Object $it -Name 'disclosureCategory')
        if ([string]::IsNullOrWhiteSpace($kind)) { $kind = [string](Get-ObjectPropertyValue -Object $it -Name 'type') }
        $date = [string](Get-ObjectPropertyValue -Object $it -Name 'publishDate')
        if ([string]::IsNullOrWhiteSpace($date)) { $date = [string](Get-ObjectPropertyValue -Object $it -Name 'date') }
        if ([string]::IsNullOrWhiteSpace($sym) -and [string]::IsNullOrWhiteSpace($title)) { continue }
        [void]$out.Add([pscustomobject][ordered]@{ Symbol = $sym; Title = $title; Kind = $kind; Date = $date })
        if ($out.Count -ge $Limit) { break }
    }
    return $out.ToArray()
}

function Get-StoredKapDisclosures {
    <#
        data/kap_disclosures.json dosyasini BEST-EFFORT okur. Bu dosyayi ayri bir
        is (kap-collector.yml, borsapy/Python) uretip repoya commit eder; ana
        PowerShell rapor sadece OKUR. Dosya yoksa/bozuksa BOS dizi doner ve rapor
        akisi bozulmaz (gozlem modu — karar etkisi YOK).

        Doner: her kayit { Symbol, Date, Title, Category, Importance, Direction,
        DisclosureId, Url }. -Symbols verilirse yalniz o hisseler; -OnlyImportant
        ile yalniz onem='high'/'insider'/'earnings' (gurultu haric) dondurulur.
        Sonuc tarihe gore (yeni -> eski) siralanir.
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [string[]]$Symbols,
        [switch]$OnlyImportant,
        [int]$MaxAgeDays = 0,        # 0 = yas filtresi yok
        [int]$Limit = 0,            # 0 = sinirsiz
        [string]$EnrichmentPath     # kap_enrichment.json (LLM yorumlari); bos = otomatik yan dosya
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path $PSScriptRoot 'data/kap_disclosures.json'
    }
    if (-not (Test-Path -LiteralPath $Path)) { return @() }

    # LLM icerik yorumlari (varsa) disclosureId ile baglanir (best-effort).
    if ([string]::IsNullOrWhiteSpace($EnrichmentPath)) {
        $EnrichmentPath = Join-Path (Split-Path -Parent $Path) 'kap_enrichment.json'
    }
    $enrichItems = $null
    if (Test-Path -LiteralPath $EnrichmentPath) {
        try {
            $enrichData = (Get-Content -LiteralPath $EnrichmentPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
            $enrichItems = Get-ObjectPropertyValue -Object $enrichData -Name 'items'
        }
        catch { $enrichItems = $null }
    }

    try {
        $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop
        $data = $json | ConvertFrom-Json -ErrorAction Stop
    }
    catch { return @() }

    $stocksObj = Get-ObjectPropertyValue -Object $data -Name 'stocks'
    if ($null -eq $stocksObj) { return @() }

    $wanted = $null
    if ($Symbols -and $Symbols.Count -gt 0) {
        $wanted = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]@($Symbols | ForEach-Object { ([string]$_).Trim().ToUpperInvariant() }),
            [System.StringComparer]::OrdinalIgnoreCase)
    }
    $importantSet = @('high', 'insider', 'earnings')
    $cutoff = $null
    if ($MaxAgeDays -gt 0) { $cutoff = (Get-Date).AddDays(-$MaxAgeDays) }

    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($prop in $stocksObj.PSObject.Properties) {
        $sym = [string]$prop.Name
        if ($wanted -and -not $wanted.Contains($sym)) { continue }
        foreach ($rec in @($prop.Value)) {
            if ($null -eq $rec) { continue }
            $imp = [string](Get-ObjectPropertyValue -Object $rec -Name 'importance')
            if ($OnlyImportant -and ($importantSet -notcontains $imp)) { continue }
            $dateStr = [string](Get-ObjectPropertyValue -Object $rec -Name 'date')
            $dt = $null
            if (-not [string]::IsNullOrWhiteSpace($dateStr)) {
                # borsapy 'dd.MM.yyyy' (ops. saat) verir. Runner kulturune bagli
                # yanlis ayristirmayi onlemek icin once InvariantCulture ParseExact;
                # sonra genel TryParse. Cozulemezse $dt=$null (yas filtresinde tutulur).
                $parsed = [datetime]::MinValue
                [string[]]$kapFormats = @('dd.MM.yyyy HH:mm:ss', 'dd.MM.yyyy HH:mm', 'dd.MM.yyyy',
                    'yyyy-MM-ddTHH:mm:ss', 'yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd')
                if ([datetime]::TryParseExact($dateStr.Trim(), $kapFormats,
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
                    $dt = $parsed
                }
                elseif ([datetime]::TryParse($dateStr, [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
                    $dt = $parsed
                }
            }
            if ($cutoff -and $dt -and $dt -lt $cutoff) { continue }
            $did = [string](Get-ObjectPropertyValue -Object $rec -Name 'disclosureId')
            $direction = [string](Get-ObjectPropertyValue -Object $rec -Name 'direction')
            $summary = ''
            $impact = $null
            $rationale = ''
            if ($null -ne $enrichItems -and -not [string]::IsNullOrWhiteSpace($did)) {
                $en = Get-ObjectPropertyValue -Object $enrichItems -Name $did
                if ($null -ne $en) {
                    $summary = [string](Get-ObjectPropertyValue -Object $en -Name 'summary')
                    $impact = Get-ObjectPropertyValue -Object $en -Name 'impact'
                    $rationale = [string](Get-ObjectPropertyValue -Object $en -Name 'rationale')
                    $enDir = [string](Get-ObjectPropertyValue -Object $en -Name 'directionRefined')
                    if (-not [string]::IsNullOrWhiteSpace($enDir)) { $direction = $enDir }
                }
            }
            [void]$out.Add([pscustomobject][ordered]@{
                Symbol       = $sym
                Date         = $dateStr
                DateParsed   = $dt
                Title        = [string](Get-ObjectPropertyValue -Object $rec -Name 'title')
                Category     = [string](Get-ObjectPropertyValue -Object $rec -Name 'category')
                Importance   = $imp
                Direction    = $direction
                DisclosureId = $did
                Url          = [string](Get-ObjectPropertyValue -Object $rec -Name 'url')
                Summary      = $summary
                Impact       = $impact
                Rationale    = $rationale
            })
        }
    }

    $sorted = $out | Sort-Object -Property @{ Expression = { if ($_.DateParsed) { $_.DateParsed } else { [datetime]::MinValue } }; Descending = $true }
    $arr = @($sorted)
    if ($Limit -gt 0 -and $arr.Count -gt $Limit) { $arr = $arr[0..($Limit - 1)] }
    return $arr
}

# ============================================================================
# TCMB EVDS (Elektronik Veri Dagitim Sistemi) entegrasyonu.
# API anahtari ASLA kodda saklanmaz; $env:BIST_EVDS_API_KEY'den okunur
# (bulutta GitHub Secret, yerelde ortam degiskeni). Anahtar yoksa sessizce
# atlanir (mevcut makro akisi bozulmaz).
# ============================================================================

function Get-EvdsSeries {
    param(
        [Parameter(Mandatory)][string]$Series,        # or. 'TP.DK.USD.A.YTL'
        [datetime]$StartDate = (Get-Date).AddDays(-45),
        [datetime]$EndDate = (Get-Date),
        [int]$Frequency = 1,                            # 1=gunluk,5=aylik
        [string]$Aggregation = 'last',
        [int]$TimeoutSec = 10
    )
    $apiKey = $env:BIST_EVDS_API_KEY
    if ([string]::IsNullOrWhiteSpace($apiKey)) { return $null }
    # EVDS gec-2025'te evds3.tcmb.gov.tr/igmevdsms-dis'e tasindi; evds2 uclari
    # SPA HTML donduruyor (sessiz kirilma). Once evds3, olmadi evds2 denenir.
    $qs = 'series={0}&startDate={1}&endDate={2}&type=json&frequency={3}&aggregationTypes={4}&formulas=0' -f `
        $Series, $StartDate.ToString('dd-MM-yyyy'), $EndDate.ToString('dd-MM-yyyy'), $Frequency, $Aggregation
    $evdsHeaders = @{
        key = $apiKey
        'User-Agent' = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36'
        Accept = 'application/json, text/plain, */*'
        Origin = 'https://evds3.tcmb.gov.tr'
        Referer = 'https://evds3.tcmb.gov.tr/tumSeriler'
    }
    $items = $null
    foreach ($endpointBase in @('https://evds3.tcmb.gov.tr/igmevdsms-dis/', 'https://evds2.tcmb.gov.tr/service/evds/')) {
        $url = $endpointBase + $qs
        try {
            $resp = Invoke-WithRetry -OperationName "EVDS $Series" -MaxAttempts 2 -BaseDelaySec 1 -ScriptBlock {
                Invoke-RestMethod -Uri $url -Headers $evdsHeaders -TimeoutSec $TimeoutSec -ErrorAction Stop
            }
        }
        catch { continue }
        # SPA HTML'i Invoke-RestMethod'da string olarak gelir — JSON nesnesi degilse atla.
        if ($resp -is [string]) { continue }
        $items = Get-ObjectPropertyValue -Object $resp -Name 'items'
        if ($null -ne $items) { break }
    }
    if ($null -eq $items) { return $null }
    $col = ($Series -replace '[\.\-]', '_')
    $points = New-Object System.Collections.Generic.List[object]
    foreach ($it in @($items)) {
        $raw = Get-ObjectPropertyValue -Object $it -Name $col
        $val = ConvertFrom-InvestingNumberText $raw
        if ($null -ne $val) {
            $points.Add([pscustomobject]@{ Date = [string](Get-ObjectPropertyValue -Object $it -Name 'Tarih'); Value = [double]$val })
        }
    }
    if ($points.Count -eq 0) { return $null }
    $last = $points[$points.Count - 1]
    $prev = if ($points.Count -ge 2) { $points[$points.Count - 2] } else { $null }
    return [pscustomobject]@{
        Series = $Series
        Value = $last.Value
        Date = $last.Date
        Previous = if ($prev) { $prev.Value } else { $null }
        Points = $points.ToArray()
    }
}

function Get-FlowRegimeStatus {
    <#
        Akis degerini makro rejim etiketine cevirir (SAF): esik ustunde
        'Destekleyici', altinda 'Baskı', arada 'Nötr', veri yoksa 'Veri Yok'.
        Etiketler Get-MacroSnapshot'in sayac regex'leriyle uyumludur.
    #>
    param(
        $Value,
        [double]$SupportiveMin,
        [double]$PressureMax
    )
    $v = ConvertTo-DoubleOrNull $Value
    if ($null -eq $v) { return 'Veri Yok' }
    if ($v -ge $SupportiveMin) { return 'Destekleyici' }
    if ($v -le $PressureMax) { return 'Baskı' }
    return 'Nötr'
}

function Get-FlowMacroMetrics {
    <#
        Makro tabloya akis metrikleri uretir (best-effort; veri yoksa bos dizi):
          1) Yabanci net hisse alimi — TCMB EVDS TP.MKNETHAR.M7, 4 haftalik toplam
             (mn USD). Esik: +-100 mn $ (tipik haftalik akislarin ~1 std sapmasi).
          2) Yerli hisse fonu akisi — data/tefas_flows.json flow4wTL (yoksa flow1wTL).
             Esik: +-1 milyar TL. Ilk kosuda akis null -> metrik atlanir.
    #>
    [CmdletBinding()]
    param([int]$TimeoutSec = 10)
    $out = @()
    try {
        $ff = Get-EvdsForeignEquityFlow -TimeoutSec $TimeoutSec
        if ($null -ne $ff -and $null -ne $ff.sum4wUsdMn) {
            $out += [pscustomobject][ordered]@{
                Id = 'FOREIGN_EQ_FLOW'; Name = 'Yabancı net hisse alımı (4H)'
                Value = [double]$ff.sum4wUsdMn; Change = $null; ChangePct = $null
                Unit = 'mn $'
                Status = Get-FlowRegimeStatus -Value $ff.sum4wUsdMn -SupportiveMin 100 -PressureMax (-100)
                Source = 'TCMB EVDS (TP.MKNETHAR.M7)'
                Url = 'https://evds3.tcmb.gov.tr'
                Note = ('Son hafta: {0} mn $ ({1}).' -f $ff.netUsdMn, $ff.date)
            }
        }
    }
    catch { }
    try {
        $tefasPath = Join-Path $PSScriptRoot 'data\tefas_flows.json'
        if (Test-Path -LiteralPath $tefasPath) {
            $tf = Get-Content -LiteralPath $tefasPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $flowTl = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $tf -Name 'flow4wTL')
            $flowLabel = '4H'
            if ($null -eq $flowTl) { $flowTl = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $tf -Name 'flow1wTL'); $flowLabel = '1H' }
            if ($null -ne $flowTl) {
                $out += [pscustomobject][ordered]@{
                    Id = 'TEFAS_EQ_FLOW'; Name = ('Yerli hisse fonu akışı ({0})' -f $flowLabel)
                    Value = [Math]::Round($flowTl / 1e9, 2); Change = $null; ChangePct = $null
                    Unit = 'mlr TL'
                    Status = Get-FlowRegimeStatus -Value $flowTl -SupportiveMin 1e9 -PressureMax (-1e9)
                    Source = 'TEFAS (pay bazlı, fiyat etkisiz)'
                    Url = 'https://www.tefas.gov.tr'
                    Note = ('Veri: {0}; {1} hisse fonu.' -f [string](Get-ObjectPropertyValue -Object $tf -Name 'asOf'), [string](Get-ObjectPropertyValue -Object $tf -Name 'equityFundCount'))
                }
            }
        }
    }
    catch { }
    return @($out)
}

function Get-EvdsForeignEquityFlow {
    <#
        Yurt disi yerlesiklerin HAFTALIK net hisse senedi islemleri (mn USD).
        Kaynak: TCMB EVDS bie_mknethar grubu, seri TP.MKNETHAR.M7
        ("2.1.1. Hisse Senedi Net Degisim", HAFTALIK CUMA, agg=sum; veri
        TCMB/Takasbank/MKK derlemesi). Piyasa GENELI yabanci akis gostergesi —
        hisse bazli degil; panel foreignFlow kartinin ust seridini besler.
        Anahtar yoksa/veri alinamazsa $null (cagiran best-effort kullanir).
    #>
    [CmdletBinding()]
    param(
        [int]$WeeksBack = 10,
        [int]$TimeoutSec = 10
    )
    if ([string]::IsNullOrWhiteSpace($env:BIST_EVDS_API_KEY)) { return $null }
    $series = Get-EvdsSeries -Series 'TP.MKNETHAR.M7' -Frequency 3 -Aggregation 'sum' `
        -StartDate (Get-Date).AddDays(-7 * ($WeeksBack + 2)) -EndDate (Get-Date) -TimeoutSec $TimeoutSec
    if ($null -eq $series) { return $null }
    $pts = @(Get-ObjectPropertyValue -Object $series -Name 'Points')
    if ($pts.Count -eq 0) { return $null }
    $last = $pts[$pts.Count - 1]
    $tailCount = [Math]::Min(4, $pts.Count)
    $sum4 = 0.0
    for ($i = $pts.Count - $tailCount; $i -lt $pts.Count; $i++) { $sum4 += [double]$pts[$i].Value }
    $recent = @($pts | Select-Object -Last 8 | ForEach-Object { [pscustomobject]@{ t = [string]$_.Date; v = [Math]::Round([double]$_.Value, 1) } })
    return [pscustomobject]@{
        netUsdMn   = [Math]::Round([double]$last.Value, 1)
        date       = [string]$last.Date
        prevUsdMn  = if ($null -ne $series.Previous) { [Math]::Round([double]$series.Previous, 1) } else { $null }
        sum4wUsdMn = [Math]::Round($sum4, 1)
        unit       = 'milyon $'
        source     = 'TCMB EVDS (TP.MKNETHAR.M7, haftalık Cuma)'
        points     = $recent
    }
}

function Get-EvdsInflationBenchmark {
    <#
        TCMB EVDS TUFE endeksinden (TP.FG.J0, 2003=100) 1Y/3Y/5Y birikimli
        enflasyonu dinamik hesaplar. Anahtar yoksa/veri yetersizse $null doner
        (cagiran statik degere duser). Boylece "Nisan 2026" gibi sabit deger
        her ay otomatik guncellenir.
    #>
    param(
        [datetime]$AsOf = (Get-Date),
        [int]$TimeoutSec = 8
    )

    if ([string]::IsNullOrWhiteSpace($env:BIST_EVDS_API_KEY)) { return $null }

    $series = Get-EvdsSeries -Series 'TP.FG.J0' -Frequency 5 -Aggregation 'last' `
        -StartDate $AsOf.AddMonths(-66) -EndDate $AsOf -TimeoutSec $TimeoutSec
    if ($null -eq $series) { return $null }

    return Get-CumulativeInflationFromIndexPoints -Points @($series.Points) -AsOfText ([string]$series.Date)
}

function Get-CumulativeInflationFromIndexPoints {
    <#
        Aylik TUFE endeks noktalarindan (eskiden yeniye sirali) 1Y/3Y/5Y
        birikimli enflasyonu hesaplar. Saf fonksiyon (ag yok) -> test edilebilir.
    #>
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Points,
        [string]$AsOfText = ''
    )

    $pts = @($Points)
    if ($pts.Count -lt 13) { return $null }

    $lastIdx = $pts.Count - 1
    $last = [double](Get-ObjectPropertyValue -Object $pts[$lastIdx] -Name 'Value')

    $valueMonthsAgo = {
        param([int]$n)
        $idx = $lastIdx - $n
        if ($idx -ge 0) { [double](Get-ObjectPropertyValue -Object $pts[$idx] -Name 'Value') } else { $null }
    }

    $v12 = & $valueMonthsAgo 12
    $v36 = & $valueMonthsAgo 36
    $v60 = & $valueMonthsAgo 60

    $infl1 = if ($null -ne $v12 -and $v12 -gt 0) { (($last / $v12) - 1.0) * 100.0 } else { $null }
    if ($null -eq $infl1) { return $null }
    $infl3 = if ($null -ne $v36 -and $v36 -gt 0) { (($last / $v36) - 1.0) * 100.0 } else { $null }
    $infl5 = if ($null -ne $v60 -and $v60 -gt 0) { (($last / $v60) - 1.0) * 100.0 } else { $null }

    return [pscustomobject][ordered]@{
        AsOf = $AsOfText
        Inflation1YPct = [Math]::Round($infl1, 2)
        Inflation3YPct = if ($null -ne $infl3) { [Math]::Round($infl3, 1) } else { $null }
        Inflation5YPct = if ($null -ne $infl5) { [Math]::Round($infl5, 1) } else { $null }
        SourceNote = "TCMB EVDS TÜFE endeksi (2003=100) ile dinamik hesaplandı; 1Y/3Y/5Y birikimli enflasyon. Son endeks tarihi: $AsOfText."
    }
}

function Resolve-InflationBenchmark {
    <#
        Dinamik (EVDS) enflasyon kiyaslamasini dener; basarisizsa modulun
        statik $script:InflationBenchmark degerine duser. Dinamik 3Y/5Y
        uretilmezse o alanlar statik degerle tamamlanir.
    #>
    param(
        [datetime]$AsOf = (Get-Date),
        [int]$TimeoutSec = 8
    )

    $dynamic = $null
    try { $dynamic = Get-EvdsInflationBenchmark -AsOf $AsOf -TimeoutSec $TimeoutSec }
    catch { $dynamic = $null }

    if ($null -eq $dynamic -or $null -eq $dynamic.Inflation1YPct) {
        return $script:InflationBenchmark
    }

    $infl3 = if ($null -ne $dynamic.Inflation3YPct) { $dynamic.Inflation3YPct } else { $script:InflationBenchmark.Inflation3YPct }
    $infl5 = if ($null -ne $dynamic.Inflation5YPct) { $dynamic.Inflation5YPct } else { $script:InflationBenchmark.Inflation5YPct }

    return [pscustomobject][ordered]@{
        AsOf = $dynamic.AsOf
        Inflation1YPct = $dynamic.Inflation1YPct
        Inflation3YPct = $infl3
        Inflation5YPct = $infl5
        SourceNote = $dynamic.SourceNote
    }
}

function Get-EvdsRateSnapshot {
    <#
        EVDS veri ucundan (kanitli; header key) bir faiz/oran serisini makro
        metrige cevirir. Seri kodu bos veya veri yoksa $null. TR10Y gibi
        metrikler icin seri kodu disaridan (env/config) verilir.
    #>
    param(
        [string]$Series,
        [string]$Id,
        [string]$Name,
        [string]$Unit = '%',
        [int]$TimeoutSec = 8
    )

    if ([string]::IsNullOrWhiteSpace($Series)) { return $null }
    $s = Get-EvdsSeries -Series $Series -Frequency 1 -StartDate ((Get-Date).AddDays(-25)) -TimeoutSec $TimeoutSec
    if ($null -eq $s -or $null -eq $s.Value) { return $null }

    $chg = if ($null -ne $s.Previous) { [double]$s.Value - [double]$s.Previous } else { $null }
    $chgPct = if ($null -ne $s.Previous -and [double]$s.Previous -ne 0) { (([double]$s.Value / [double]$s.Previous) - 1.0) * 100.0 } else { $null }

    return [pscustomobject][ordered]@{
        Id = $Id
        Name = $Name
        Value = [Math]::Round([double]$s.Value, 2)
        Change = if ($null -ne $chg) { [Math]::Round($chg, 2) } else { $null }
        ChangePct = if ($null -ne $chgPct) { [Math]::Round($chgPct, 2) } else { $null }
        Unit = $Unit
        Status = 'Veri Yok'
        Source = 'TCMB EVDS'
        Url = 'https://evds2.tcmb.gov.tr/'
        Note = "EVDS seri: $Series ($($s.Date))"
    }
}

function Get-EvdsMacroMetrics {
    # Anahtar yoksa bos donerek mevcut akisi bozmaz. Seri kodlari EVDS'de
    # dogrulanmalidir; yanlis kod sessizce atlanir.
    param([int]$TimeoutSec = 8)
    if ([string]::IsNullOrWhiteSpace($env:BIST_EVDS_API_KEY)) { return @() }

    $metrics = [System.Collections.Generic.List[object]]::new()

    # Politika/fonlama faizi (TCMB agirlikli ortalama fonlama maliyeti)
    $rate = Get-EvdsSeries -Series 'TP.APIFON4' -Frequency 1 -TimeoutSec $TimeoutSec
    if ($null -ne $rate) {
        $chg = if ($null -ne $rate.Previous) { $rate.Value - $rate.Previous } else { $null }
        [void]$metrics.Add([pscustomobject][ordered]@{
                Id = 'TR_FUNDING'; Name = 'TCMB Fonlama Faizi'; Value = [Math]::Round($rate.Value, 2)
                Change = if ($null -ne $chg) { [Math]::Round($chg, 2) } else { $null }; ChangePct = $null; Unit = '%'
                Status = if ($null -ne $chg -and $chg -lt 0) { 'Faiz düşüyor' } elseif ($null -ne $chg -and $chg -gt 0) { 'Faiz artıyor' } else { 'Sabit' }
                Source = 'TCMB EVDS'; Url = 'https://evds2.tcmb.gov.tr/'; Note = "Tarih: $($rate.Date)"
            })
    }

    # TUFE (yillik enflasyon + YON: bir onceki ayin yillik degeriyle fark).
    # Yon, rejim motoru icin kritiktir: dusen yillik enflasyon = faiz indirimi
    # beklentisi kanali (deterministik 'beklentiden dusuk' vekili).
    $cpi = Get-EvdsSeries -Series 'TP.FG.J0' -Frequency 5 -StartDate ((Get-Date).AddMonths(-16)) -TimeoutSec $TimeoutSec
    if ($null -ne $cpi -and $cpi.Points.Count -ge 13) {
        $pts = $cpi.Points; $latest = $pts[$pts.Count - 1].Value; $yearAgo = $pts[$pts.Count - 13].Value
        if ($yearAgo -gt 0) {
            $yoy = (($latest / $yearAgo) - 1) * 100
            $yoyChange = $null
            if ($pts.Count -ge 14) {
                $prevLatest = $pts[$pts.Count - 2].Value; $prevYearAgo = $pts[$pts.Count - 14].Value
                if ($prevYearAgo -gt 0) { $yoyChange = [Math]::Round($yoy - ((($prevLatest / $prevYearAgo) - 1) * 100), 1) }
            }
            [void]$metrics.Add([pscustomobject][ordered]@{
                    Id = 'TR_CPI_YOY'; Name = 'TÜFE (yıllık)'; Value = [Math]::Round($yoy, 1); Change = $yoyChange; ChangePct = $null; Unit = '%'
                    Status = if ($null -ne $yoyChange -and $yoyChange -lt -0.2) { 'Enflasyon düşüyor' }
                    elseif ($null -ne $yoyChange -and $yoyChange -gt 0.2) { 'Enflasyon artıyor' }
                    elseif ($yoy -lt 40) { 'Enflasyon ılımlı' } else { 'Enflasyon yüksek' }
                    Source = 'TCMB EVDS'; Url = 'https://evds2.tcmb.gov.tr/'; Note = "Son endeks tarihi: $($pts[$pts.Count-1].Date)"
                })
        }
    }
    return $metrics.ToArray()
}

function Update-SignalPerformance {
    <#
        Kendi kendini degerlendiren geri-besleme dongusu.
        Onceki kosuda kaydedilen yuksek-skorlu seciler ile bugunku fiyatlari
        karsilastirir; secilerin ortalama getirisini tum evrenin ortalamasiyla
        kiyaslayarak skorun "isabet" edip etmedigini olcer ve yuvarlanan bir
        isabet orani (hit-rate) + ortalama getiri avantaji (edge) biriktirir.
    #>
    [CmdletBinding()]
    param(
        $Previous,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$ScoredStocks,
        [datetime]$AsOf = (Get-Date),
        [int]$TopCount = 20,
        [int]$MaxHistory = 60
    )

    $priceMap = @{}
    foreach ($stock in @($ScoredStocks)) {
        $symbol = [string](Get-ObjectPropertyValue -Object $stock -Name 'Symbol')
        if ([string]::IsNullOrWhiteSpace($symbol)) { continue }
        $price = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $stock -Name 'Price')
        if ($null -ne $price -and $price -gt 0 -and -not $priceMap.ContainsKey($symbol)) {
            $priceMap[$symbol] = [double]$price
        }
    }

    $evaluations = [System.Collections.Generic.List[object]]::new()
    $previousPending = $null
    if ($null -ne $Previous) {
        foreach ($existing in @(Get-ObjectPropertyValue -Object $Previous -Name 'Evaluations')) {
            if ($null -ne $existing) { [void]$evaluations.Add($existing) }
        }
        $previousPending = Get-ObjectPropertyValue -Object $Previous -Name 'PendingPicks'
    }

    $newEvaluation = $null
    $pendingItems = @(Get-ObjectPropertyValue -Object $previousPending -Name 'Picks')
    if ($pendingItems.Count -gt 0) {
        # Evrenin tamami icin getiri (benchmark) ve seciler icin getiri.
        $pickReturns = [System.Collections.Generic.List[double]]::new()
        $benchReturns = [System.Collections.Generic.List[double]]::new()
        $pendingMap = @{}
        foreach ($pick in $pendingItems) {
            $sym = [string](Get-ObjectPropertyValue -Object $pick -Name 'Symbol')
            $entryPrice = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $pick -Name 'Price')
            if ([string]::IsNullOrWhiteSpace($sym) -or $null -eq $entryPrice -or $entryPrice -le 0) { continue }
            $pendingMap[$sym] = [double]$entryPrice
        }

        # Bencmark: onceki kosuda kaydedilen evren fiyatlarinin getirisi.
        $universeItems = @(Get-ObjectPropertyValue -Object $previousPending -Name 'Universe')
        foreach ($u in $universeItems) {
            $sym = [string](Get-ObjectPropertyValue -Object $u -Name 'Symbol')
            $oldPrice = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $u -Name 'Price')
            if ([string]::IsNullOrWhiteSpace($sym) -or $null -eq $oldPrice -or $oldPrice -le 0) { continue }
            if (-not $priceMap.ContainsKey($sym)) { continue }
            $ret = (($priceMap[$sym] / [double]$oldPrice) - 1.0) * 100.0
            [void]$benchReturns.Add($ret)
            if ($pendingMap.ContainsKey($sym)) { [void]$pickReturns.Add($ret) }
        }

        if ($pickReturns.Count -gt 0 -and $benchReturns.Count -gt 0) {
            $pickMean = ($pickReturns | Measure-Object -Average).Average
            $benchMean = ($benchReturns | Measure-Object -Average).Average
            $edge = $pickMean - $benchMean
            $recordedAt = [string](Get-ObjectPropertyValue -Object $previousPending -Name 'AsOf')
            $newEvaluation = [pscustomobject][ordered]@{
                PicksAsOf = $recordedAt
                EvaluatedAt = $AsOf.ToString('o')
                PickCount = $pickReturns.Count
                UniverseCount = $benchReturns.Count
                PickMeanReturnPct = [Math]::Round($pickMean, 3)
                UniverseMeanReturnPct = [Math]::Round($benchMean, 3)
                EdgePct = [Math]::Round($edge, 3)
                Win = ($edge -gt 0)
            }
            [void]$evaluations.Add($newEvaluation)
        }
    }

    # Tarihçeyi sinirla (en yeni MaxHistory degerlendirme).
    while ($evaluations.Count -gt $MaxHistory) {
        $evaluations.RemoveAt(0)
    }

    # Bugunku secileri ve evreni sonraki kosu icin kaydet.
    $orderedScored = @($ScoredStocks | Sort-Object @{ Expression = { ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $_ -Name 'Score') }; Descending = $true })
    $topPicks = [System.Collections.Generic.List[object]]::new()
    foreach ($stock in @($orderedScored | Select-Object -First $TopCount)) {
        $sym = [string](Get-ObjectPropertyValue -Object $stock -Name 'Symbol')
        if ([string]::IsNullOrWhiteSpace($sym) -or -not $priceMap.ContainsKey($sym)) { continue }
        [void]$topPicks.Add([pscustomobject][ordered]@{
                Symbol = $sym
                Score = [Math]::Round([double](ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $stock -Name 'Score')), 2)
                Price = $priceMap[$sym]
            })
    }
    $universe = [System.Collections.Generic.List[object]]::new()
    foreach ($sym in $priceMap.Keys) {
        [void]$universe.Add([pscustomobject][ordered]@{ Symbol = $sym; Price = $priceMap[$sym] })
    }

    # Yuvarlanan ozet.
    $winCount = @($evaluations | Where-Object { [bool](Get-ObjectPropertyValue -Object $_ -Name 'Win') }).Count
    $sampleCount = $evaluations.Count
    $hitRate = if ($sampleCount -gt 0) { [Math]::Round(($winCount / [double]$sampleCount) * 100.0, 1) } else { $null }
    $avgEdge = if ($sampleCount -gt 0) {
        [Math]::Round((@($evaluations | ForEach-Object { [double](Get-ObjectPropertyValue -Object $_ -Name 'EdgePct') }) | Measure-Object -Average).Average, 3)
    } else { $null }

    $summary = [pscustomobject][ordered]@{
        SampleCount = $sampleCount
        HitRatePct = $hitRate
        AvgEdgePct = $avgEdge
        LastEdgePct = if ($null -ne $newEvaluation) { $newEvaluation.EdgePct } else { $null }
        LastPickReturnPct = if ($null -ne $newEvaluation) { $newEvaluation.PickMeanReturnPct } else { $null }
        HasEvaluationToday = ($null -ne $newEvaluation)
    }

    return [pscustomobject][ordered]@{
        UpdatedAt = $AsOf.ToString('o')
        Summary = $summary
        Evaluations = $evaluations.ToArray()
        PendingPicks = [pscustomobject][ordered]@{
            AsOf = $AsOf.ToString('o')
            Picks = $topPicks.ToArray()
            Universe = $universe.ToArray()
        }
    }
}

function Save-PitSnapshot {
    <#
        Point-in-time (PIT) anlik goruntu deposu — KURUMSAL altyapi.

        Gecmis "as-reported" temel veri ve delist-dahil bilesen listesi ucretsiz
        kaynaklarda YOKTUR; bu yuzden gecmise donuk PIT uretilemez. Bunun yerine bu
        fonksiyon, her kosuda O GUN GOZLENEN evreni + temel/teknik alanlari tarihli
        JSON olarak biriktirir. Zamanla, ileri-bakis (look-ahead) iceremeyen GERCEK
        bir PIT arsivi olusur; backtest'ler bu arsivden as-observed temel veriyle
        beslenebilir hale gelir.

        Cikti: data/pit/YYYY-MM-DD.json  (gunde tek dosya; idempotent).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Stocks,
        [string]$Directory = 'data/pit',
        [Nullable[datetime]]$AsOf = $null,
        [object]$Macro = $null
    )

    $stamp = if ($AsOf) { ([datetime]$AsOf) } else { Get-Date }
    $dateKey = $stamp.ToString('yyyy-MM-dd')
    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }
    $path = Join-Path $Directory ("$dateKey.json")

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($s in $Stocks) {
        if ($null -eq $s) { continue }
        $sym = Get-ObjectPropertyValue -Object $s -Name 'Symbol'
        if ([string]::IsNullOrWhiteSpace($sym)) { continue }
        # Yalniz o gun gozlenen alanlar — ileri-bakis yok.
        [void]$rows.Add([pscustomobject][ordered]@{
                Symbol           = [string]$sym
                Price            = Get-ObjectPropertyValue -Object $s -Name 'Price'
                MarketCap        = Get-ObjectPropertyValue -Object $s -Name 'MarketCap'
                PE               = Get-ObjectPropertyValue -Object $s -Name 'PE'
                PB               = Get-ObjectPropertyValue -Object $s -Name 'PB'
                ROE              = Get-ObjectPropertyValue -Object $s -Name 'ROE'
                DebtToEquity     = Get-ObjectPropertyValue -Object $s -Name 'DebtToEquity'
                DividendYield    = Get-ObjectPropertyValue -Object $s -Name 'DividendYield'
                Sector           = Get-ObjectPropertyValue -Object $s -Name 'Sector'
                VolatilityD      = Get-ObjectPropertyValue -Object $s -Name 'VolatilityD'
                AverageVolume10D = Get-ObjectPropertyValue -Object $s -Name 'AverageVolume10D'
                # RFS faktor girdileri — oto-kalibrasyon (walk-forward IC) icin arsivlenir.
                SMA20            = Get-ObjectPropertyValue -Object $s -Name 'SMA20'
                SMA50            = Get-ObjectPropertyValue -Object $s -Name 'SMA50'
                SMA200           = Get-ObjectPropertyValue -Object $s -Name 'SMA200'
                RSI              = Get-ObjectPropertyValue -Object $s -Name 'RSI'
                MacdHistogram    = Get-ObjectPropertyValue -Object $s -Name 'MacdHistogram'
                MacdHistogramWeekly = Get-ObjectPropertyValue -Object $s -Name 'MacdHistogramWeekly'
                PerfMonth        = Get-ObjectPropertyValue -Object $s -Name 'PerfMonth'
                Perf3Month       = Get-ObjectPropertyValue -Object $s -Name 'Perf3Month'
                RelativeVolume   = Get-ObjectPropertyValue -Object $s -Name 'RelativeVolume'
                Volume           = Get-ObjectPropertyValue -Object $s -Name 'Volume'
                # Akilli-para/rejim alanlari — ayarlarin GERCEK ongoruculugunun
                # (IC) ileride olculebilmesi icin as-observed arsivlenir.
                ForeignPct       = Get-ObjectPropertyValue -Object $s -Name 'ForeignPct'
                ForeignChg1wBps  = Get-ObjectPropertyValue -Object $s -Name 'ForeignChg1wBps'
                InsiderSignal    = Get-ObjectPropertyValue -Object $s -Name 'InsiderSignal'
                MacroRegimeAdjustment = Get-ObjectPropertyValue -Object $s -Name 'MacroRegimeAdjustment'
                LatestReportDate = (Get-ObjectPropertyValue -Object $s -Name 'LatestReportDate')
                NextEarningsDate = (Get-ObjectPropertyValue -Object $s -Name 'NextEarningsDate')
                FiscalPeriodEnd  = (Get-ObjectPropertyValue -Object $s -Name 'FiscalPeriodEnd')
            })
    }

    $macroNote = $null
    if ($null -ne $Macro) {
        # Get-MacroSnapshot degerleri Metrics[] icinde Id ile tasir; duz alanli
        # (UsdTry/Tr10Y/...) obje de desteklenir. Onceki surum yalniz duz alan
        # okudugu icin Macro dugumu hep null yaziliyordu (2026-07-02 arsivinde goruldu).
        $metricList = @(Get-ObjectPropertyValue -Object $Macro -Name 'Metrics')
        $metricById = @{}
        foreach ($mm in $metricList) {
            $mid = [string](Get-ObjectPropertyValue -Object $mm -Name 'Id')
            if ($mid -and -not $metricById.ContainsKey($mid)) { $metricById[$mid] = Get-ObjectPropertyValue -Object $mm -Name 'Value' }
        }
        $pickMacro = {
            param($flatName, $metricId)
            $v = Get-ObjectPropertyValue -Object $Macro -Name $flatName
            if ($null -ne $v) { return $v }
            if ($metricById.ContainsKey($metricId)) { return $metricById[$metricId] }
            return $null
        }
        # Rejim arsivi: gunluk rejim etiketi/skoru PIT'e yazilir ki ileride
        # "rejim -> 1 ay ileri getiri" ve "nakit hedefi -> ileri getiri" olculebilsin.
        $regimeObj = Get-ObjectPropertyValue -Object $Macro -Name 'Regime'
        $regimeLabelPit = [string](Get-ObjectPropertyValue -Object $regimeObj -Name 'Regime')
        # Nakit hedefi (golge): XU100 Value/Sma200'den trend kapisi + rejim.
        $belowSmaPit = $null
        $xuPit = Get-MacroSnapshotMetric -Snapshot $Macro -Id 'XU100'
        $xuPricePit = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $xuPit -Name 'Value')
        $xuSmaPit = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $xuPit -Name 'Sma200')
        if ($null -ne $xuPricePit -and $null -ne $xuSmaPit -and $xuSmaPit -gt 0) { $belowSmaPit = ($xuPricePit -lt $xuSmaPit) }
        $cashTargetPit = Get-RegimeCashTarget -RegimeLabel $regimeLabelPit -Bist100BelowSma200 $belowSmaPit
        $macroNote = [pscustomobject][ordered]@{
            UsdTry  = & $pickMacro 'UsdTry' 'USDTRY_Tcmb'
            Tr10Y   = & $pickMacro 'Tr10Y' 'TR_10Y'
            Dxy     = & $pickMacro 'Dxy' 'DXY'
            Vix     = & $pickMacro 'Vix' 'VIX'
            Cds5Y   = & $pickMacro 'Cds5Y' 'TR_CDS_5Y'
            Bist100 = & $pickMacro 'Bist100' 'XU100'
            Status  = [string](Get-ObjectPropertyValue -Object $Macro -Name 'Status')
            RegimeLabel = $regimeLabelPit
            RegimeScore = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $regimeObj -Name 'Score')
            RegimeConfidence = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $regimeObj -Name 'Confidence')
            BelowSma200 = $belowSmaPit
            CashTargetPct = [Math]::Round($cashTargetPit * 100, 0)
        }
    }

    $snapshot = [pscustomobject][ordered]@{
        AsOf          = $stamp.ToString('o')
        CapturedUtc   = (Get-Date).ToUniversalTime().ToString('o')
        UniverseCount = $rows.Count
        Macro         = $macroNote
        Constituents  = $rows.ToArray()
    }
    $snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Get-PitSnapshot {
    <#
        PIT arsivinden bir gunun (veya en yakin oncesinin) anlik goruntusunu okur.
        Yoksa $null. Backtest'lerin as-observed temel veriyle beslenmesi icindir.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][datetime]$Date,
        [string]$Directory = 'data/pit',
        [switch]$OnOrBefore
    )
    if (-not (Test-Path -LiteralPath $Directory)) { return $null }
    $target = $Date.ToString('yyyy-MM-dd')
    $exact = Join-Path $Directory ("$target.json")
    if (Test-Path -LiteralPath $exact) { return (Get-Content -LiteralPath $exact -Raw | ConvertFrom-Json) }
    if (-not $OnOrBefore) { return $null }
    $candidate = @(Get-ChildItem -LiteralPath $Directory -Filter '*.json' -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -le $target } | Sort-Object Name)
    if ($candidate.Count -eq 0) { return $null }
    return (Get-Content -LiteralPath $candidate[-1].FullName -Raw | ConvertFrom-Json)
}

# ===========================================================================
#  Performans karsilastirma grafigi: model portfoyler + benchmark'lar (TRY %)
# ===========================================================================

function Get-PerfPointOnOrBefore {
    # Artan tarihli {Date, ...} dizisinde, verilen tarihe esit/onceki son noktayi dondurur.
    param([object[]]$Points, [datetime]$Date)
    $found = $null
    foreach ($pt in $Points) {
        if ([datetime]$pt.Date -le $Date) { $found = $pt } else { break }
    }
    return $found
}

function Get-StrategyPerformanceSeries {
    <#
        Her model portfoyun kurulustan bugune gun gun TRY % getiri serisini, islem
        gecmisi (Transactions) + Yahoo gunluk kapanis ile YENIDEN KURAR (point-in-time).
        deger(t) = Σ holding_qty(t) × kapanis(symbol, t)  (tam yatirim, nakit ~0).
        Rebalance'lar Transactions'tan turetildigi icin ileride de dogru kalir.
        Donus: [{ Name, Points: [{Date, ReturnPct}] }]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$PortfolioSet,
        [int]$TimeoutSec = 10,
        [hashtable]$PriceCache = $null
    )

    $portfolios = @(Get-ObjectPropertyValue -Object $PortfolioSet -Name 'Portfolios')
    if ($portfolios.Count -eq 0) { return @() }
    if ($null -eq $PriceCache) { $PriceCache = @{} }

    # Benzersiz semboller -> Yahoo gunluk kapanis (bir kez cek, cache'le)
    $symbols = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($p in $portfolios) {
        foreach ($tx in @(Get-ObjectPropertyValue -Object $p -Name 'Transactions')) {
            $s = [string](Get-ObjectPropertyValue -Object $tx -Name 'Symbol')
            if (-not [string]::IsNullOrWhiteSpace($s)) { [void]$symbols.Add($s) }
        }
    }
    foreach ($sym in $symbols) {
        if (-not $PriceCache.ContainsKey($sym)) {
            $PriceCache[$sym] = @(Get-YahooDailyCloseSeries -Symbol $sym -Range '1y' -TimeoutSec $TimeoutSec)
        }
    }

    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $portfolios) {
        $name = [string](Get-ObjectPropertyValue -Object $p -Name 'Name')
        $initial = [double](Get-ObjectPropertyValue -Object $p -Name 'InitialCapitalTL')
        if ($initial -le 0) { $initial = 100000.0 }
        $startRaw = Get-ObjectPropertyValue -Object $p -Name 'StartDate'
        $start = if ($startRaw) { [datetime]$startRaw } else { (Get-Date).AddMonths(-1) }

        $txList = @(Get-ObjectPropertyValue -Object $p -Name 'Transactions' |
                Sort-Object @{ Expression = { [datetime](Get-ObjectPropertyValue -Object $_ -Name 'ExecutionDate') } })
        if ($txList.Count -eq 0) { continue }

        # Bu portfoyun sembollerinin tarih birlesimi (StartDate sonrasi) -> ortak eksen
        $dateSet = @{}
        foreach ($tx in $txList) {
            $s = [string](Get-ObjectPropertyValue -Object $tx -Name 'Symbol')
            foreach ($pt in @($PriceCache[$s])) {
                $d = ([datetime]$pt.Date).Date
                if ($d -ge $start.Date) { $dateSet[$d] = $true }
            }
        }
        $axis = @($dateSet.Keys | Sort-Object)
        if ($axis.Count -eq 0) { continue }

        $points = [System.Collections.Generic.List[object]]::new()
        foreach ($day in $axis) {
            # O gune kadar gerceklesen islemlerden holding seti
            $holdings = @{}
            foreach ($tx in $txList) {
                $txDate = [datetime](Get-ObjectPropertyValue -Object $tx -Name 'ExecutionDate')
                if ($txDate.Date -gt $day) { break }
                $s = [string](Get-ObjectPropertyValue -Object $tx -Name 'Symbol')
                $qty = [double](Get-ObjectPropertyValue -Object $tx -Name 'Quantity')
                $act = [string](Get-ObjectPropertyValue -Object $tx -Name 'Action')
                $delta = if ($act -match 'SAT') { - $qty } else { $qty }
                if ($holdings.ContainsKey($s)) { $holdings[$s] += $delta } else { $holdings[$s] = $delta }
            }
            $value = 0.0; $priced = $true
            foreach ($s in @($holdings.Keys)) {
                $q = [double]$holdings[$s]
                if ([Math]::Abs($q) -lt 1e-9) { continue }
                $pt = Get-PerfPointOnOrBefore -Points @($PriceCache[$s]) -Date $day
                if ($null -eq $pt) { $priced = $false; break }
                $value += $q * [double]$pt.Close
            }
            if ($priced -and $value -gt 0) {
                [void]$points.Add([pscustomobject]@{ Date = $day; ReturnPct = [Math]::Round((($value / $initial) - 1.0) * 100.0, 2) })
            }
        }
        if ($points.Count -gt 0) {
            [void]$result.Add([pscustomobject]@{ Name = $name; Points = $points.ToArray() })
        }
    }
    return @($result.ToArray())
}

function Get-BenchmarkPerformanceSeries {
    <#
        BIST100, Altin, Mevduat, Nasdaq, S&P500'un StartDate'ten bugune TRY bazinda
        gun gun % getiri serisi. Yabanci varliklar (altin/Nasdaq/S&P500) USD/TRY ile
        TRY'ye cevrilir. Mevduat EVDS APIFON serisinden bilesik birikimle yaklasiktir.
        Tum seriler StartDate'te %0'dan baslar. Erisilemeyen kaynak atlanir.
        Donus: [{ Name, Points: [{Date, ReturnPct}] }]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][datetime]$StartDate,
        [int]$TimeoutSec = 10
    )

    $start = $StartDate.Date
    $usdtry = @(Get-YahooDailyCloseSeries -Symbol 'USDTRY=X' -Range '1y' -TimeoutSec $TimeoutSec -AsRawTicker)
    $bist = @(Get-YahooDailyCloseSeries -Symbol 'XU100' -Range '1y' -TimeoutSec $TimeoutSec)
    $gold = @(Get-YahooDailyCloseSeries -Symbol 'GC=F' -Range '1y' -TimeoutSec $TimeoutSec -AsRawTicker)
    $nasdaq = @(Get-YahooDailyCloseSeries -Symbol '^IXIC' -Range '1y' -TimeoutSec $TimeoutSec -AsRawTicker)
    $sp500 = @(Get-YahooDailyCloseSeries -Symbol '^GSPC' -Range '1y' -TimeoutSec $TimeoutSec -AsRawTicker)

    # Ortak tarih ekseni: BIST islem gunleri (StartDate sonrasi). XU100 fetch'i
    # duserse eksen USD/TRY -> altin -> Nasdaq'a DUSER (tek kaynak hicbir zaman tum
    # benchmark blogunu birden dusurmesin; eskiden yalniz BIST'e bagliydi -> XU100
    # aksarsa Altin/USD/S&P cizgileri de yok oluyordu).
    $axisSource = if (@($bist).Count -ge 2) { $bist }
        elseif (@($usdtry).Count -ge 2) { $usdtry }
        elseif (@($gold).Count -ge 2) { $gold }
        elseif (@($nasdaq).Count -ge 2) { $nasdaq }
        else { @() }
    $axis = @($axisSource | Where-Object { ([datetime]$_.Date).Date -ge $start } | ForEach-Object { ([datetime]$_.Date).Date } | Sort-Object -Unique)
    if ($axis.Count -lt 2) { return @() }

    # TRY seviyesi ureten yardimci (yabanci varlik × USD/TRY)
    $tryLevel = {
        param($Series, $Day, $Fx)
        $p = Get-PerfPointOnOrBefore -Points @($Series) -Date $Day
        if ($null -eq $p) { return $null }
        if ($Fx) {
            $f = Get-PerfPointOnOrBefore -Points @($Fx) -Date $Day
            if ($null -eq $f) { return $null }
            return [double]$p.Close * [double]$f.Close
        }
        return [double]$p.Close
    }

    $defs = @(
        @{ Name = 'BIST100'; Series = $bist; Fx = $null }
        # USD/TRY: TR'de temel kiyas — 'dolari yendik mi?'. USD/TRY zaten TRY
        # seviyesidir (Fx=null). Portfoy USD-reel getirisi de bu seriden turetilir.
        # NOT (kasitli tasarim): USD-reel getiri KESITSEL hisse SECIMINE faktor
        # olarak eklenmedi — USD/TRY degisimi bir tarihte tum hisseler icin AYNI
        # skalerdir; tum getirileri ayni carpanla bolmek relatif siralamayi
        # DEGISTIRMEZ (Perf3Month ile ozdes). USD-reel deger zaman-serisi
        # kiyasindadir (portfoy vs dolar), kesit secimde degil. Gercek kesitsel
        # FX sinyali sirket bazli DOVIZ GELIR maruziyeti gerektirir (ayri veri).
        @{ Name = 'USD/TRY'; Series = $usdtry; Fx = $null }
        @{ Name = 'Altın (TRY)'; Series = $gold; Fx = $usdtry }
        @{ Name = 'Nasdaq (TRY)'; Series = $nasdaq; Fx = $usdtry }
        @{ Name = 'S&P 500 (TRY)'; Series = $sp500; Fx = $usdtry }
    )

    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($d in $defs) {
        if (@($d.Series).Count -lt 2) { continue }
        $base = & $tryLevel $d.Series $axis[0] $d.Fx
        if ($null -eq $base -or $base -le 0) { continue }
        $pts = [System.Collections.Generic.List[object]]::new()
        foreach ($day in $axis) {
            $lvl = & $tryLevel $d.Series $day $d.Fx
            if ($null -ne $lvl -and $lvl -gt 0) {
                [void]$pts.Add([pscustomobject]@{ Date = $day; ReturnPct = [Math]::Round((($lvl / $base) - 1.0) * 100.0, 2) })
            }
        }
        if ($pts.Count -gt 0) { [void]$result.Add([pscustomobject]@{ Name = $d.Name; Points = $pts.ToArray() }) }
    }

    # Mevduat (EVDS APIFON gunluk oran -> bilesik birikim). Anahtar yoksa atlanir.
    $rateSeries = Get-EvdsSeries -Series 'TP.APIFON4' -Frequency 1 -StartDate $start.AddDays(-10) -EndDate (Get-Date) -TimeoutSec $TimeoutSec
    if ($null -ne $rateSeries) {
        $ratePts = @(Get-ObjectPropertyValue -Object $rateSeries -Name 'Points' | ForEach-Object {
                $dt = $null
                $ok = [datetime]::TryParseExact([string]$_.Date, 'dd-MM-yyyy', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$dt)
                if ($ok) { [pscustomobject]@{ Date = $dt.Date; Value = [double]$_.Value } }
            } | Where-Object { $_ } | Sort-Object Date)
        if ($ratePts.Count -gt 0) {
            $pts = [System.Collections.Generic.List[object]]::new()
            $acc = 1.0; $prevDay = $axis[0]
            foreach ($day in $axis) {
                $rp = Get-PerfPointOnOrBefore -Points $ratePts -Date $day
                $annual = if ($null -ne $rp) { [double]$rp.Value } else { 0.0 }
                $days = ($day - $prevDay).TotalDays
                if ($days -gt 0) { $acc *= [Math]::Pow(1.0 + ($annual / 100.0), $days / 365.0) }
                $prevDay = $day
                [void]$pts.Add([pscustomobject]@{ Date = $day; ReturnPct = [Math]::Round(($acc - 1.0) * 100.0, 2) })
            }
            [void]$result.Add([pscustomobject]@{ Name = 'Mevduat (yaklaşık)'; Points = $pts.ToArray() })
        }
    }

    return @($result.ToArray())
}

function Save-BenchmarkPerfCache {
    <#
        Basarili benchmark serisini (BIST100/Altin/USD/Nasdaq/S&P) diske yazar ki
        bir sonraki kosuda Yahoo aksarsa cizgiler kaybolmasin (panel referans
        cizgileri surekliligi). Date 'yyyy-MM-dd' string'e cevrilir (JSON round-trip
        guvenli; ConvertTo-DashSeries string t'yi kabul eder). BOS seri KAYDEDILMEZ
        (iyi onbellegi bozmasin). Donus: kaydedildi mi ($true/$false).
    #>
    param([Parameter(Mandatory)]$Series, [Parameter(Mandatory)][string]$Path, [datetime]$AsOf = (Get-Date))
    $arr = @(@($Series) | Where-Object { $_ -and @($_.Points).Count -gt 0 })
    if ($arr.Count -eq 0) { return $false }
    $payload = [pscustomobject]@{
        asOf = $AsOf.ToString('yyyy-MM-dd')
        series = @($arr | ForEach-Object {
            [pscustomobject]@{
                Name = [string]$_.Name
                Points = @(@($_.Points) | ForEach-Object {
                    $d = $_.Date
                    $ds = if ($d -is [datetime]) { $d.ToString('yyyy-MM-dd') } else { [string]$d }
                    [pscustomobject]@{ Date = $ds; ReturnPct = [double]$_.ReturnPct }
                })
            }
        })
    }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $true
}

function Read-BenchmarkPerfCache {
    <#
        Onbellek benchmark serisini geri okur (Yahoo bu kosuda bos donduyse yedek).
        Cok bayatsa (> MaxAgeDays) KULLANILMAZ — cok eski referans cizgisi yanilticidir.
        Donus: [{ Name, Points:[{Date, ReturnPct}] }] (Get-BenchmarkPerformanceSeries
        ile ayni sekil; ConvertTo-DashSeries dogrudan tuketir) veya @().
    #>
    param([Parameter(Mandatory)][string]$Path, [int]$MaxAgeDays = 14, [datetime]$Now = (Get-Date))
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    try { $obj = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return @() }
    if ($null -eq $obj) { return @() }
    $asOf = $null
    try { $asOf = [datetime]::ParseExact([string]$obj.asOf, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) } catch { $asOf = $null }
    if ($null -ne $asOf -and ($Now.Date - $asOf.Date).TotalDays -gt $MaxAgeDays) { return @() }
    return @(@($obj.series) | Where-Object { $_ -and @($_.Points).Count -gt 0 } | ForEach-Object {
        [pscustomobject]@{ Name = [string]$_.Name; Points = @($_.Points) }
    })
}

function New-PerformanceComparisonChart {
    <#
        Strateji + benchmark serilerini tek bir cizgi grafige (QuickChart.io;
        X=tarih, Y=% getiri) cevirir ve QuickChart'in KALICI gorsel URL'sini dondurur
        (/chart/create). Bu URL e-postada <img src> olarak kullanilir; Gmail dis
        gorseli CID'den daha tutarli gosterir. Basari: URL; aksi halde $null.
        Best-effort: QuickChart erisilemezse cagiran grafigi atlar.
    #>
    [CmdletBinding()]
    param(
        [object[]]$StrategySeries = @(),
        [object[]]$BenchmarkSeries = @(),
        [int]$TimeoutSec = 25
    )

    $all = @(@($StrategySeries) + @($BenchmarkSeries) | Where-Object { $_ -and @($_.Points).Count -gt 0 })
    if ($all.Count -eq 0) { return $null }

    # Ortak etiketler: tum tarihlerin birlesimi (sirali)
    $labelSet = @{}
    foreach ($s in $all) { foreach ($pt in @($s.Points)) { $labelSet[([datetime]$pt.Date).Date] = $true } }
    $labels = @($labelSet.Keys | Sort-Object)
    if ($labels.Count -lt 2) { return $null }
    $labelText = @($labels | ForEach-Object { $_.ToString('dd.MM') })

    # Renk paleti (strateji=canli, benchmark=daha notr/kesik)
    $stratColors = @('#2563eb', '#16a34a', '#9333ea', '#0891b2', '#ea580c', '#db2777')
    $benchColors = @('#dc2626', '#ca8a04', '#6b7280', '#0d9488', '#1e3a8a')

    $datasets = [System.Collections.Generic.List[object]]::new()
    $ci = 0
    foreach ($s in @($StrategySeries | Where-Object { $_ -and @($_.Points).Count -gt 0 })) {
        $map = @{}; foreach ($pt in @($s.Points)) { $map[([datetime]$pt.Date).Date] = [double]$pt.ReturnPct }
        $data = @($labels | ForEach-Object { if ($map.ContainsKey($_)) { $map[$_] } else { $null } })
        [void]$datasets.Add([ordered]@{ label = [string]$s.Name; data = $data; borderColor = $stratColors[$ci % $stratColors.Count]; backgroundColor = $stratColors[$ci % $stratColors.Count]; fill = $false; borderWidth = 2; pointRadius = 0; spanGaps = $true; tension = 0.2 })
        $ci++
    }
    $ci = 0
    foreach ($s in @($BenchmarkSeries | Where-Object { $_ -and @($_.Points).Count -gt 0 })) {
        $map = @{}; foreach ($pt in @($s.Points)) { $map[([datetime]$pt.Date).Date] = [double]$pt.ReturnPct }
        $data = @($labels | ForEach-Object { if ($map.ContainsKey($_)) { $map[$_] } else { $null } })
        [void]$datasets.Add([ordered]@{ label = [string]$s.Name; data = $data; borderColor = $benchColors[$ci % $benchColors.Count]; backgroundColor = $benchColors[$ci % $benchColors.Count]; fill = $false; borderWidth = 2; borderDash = @(6, 4); pointRadius = 0; spanGaps = $true; tension = 0.2 })
        $ci++
    }

    $config = [ordered]@{
        type = 'line'
        data = [ordered]@{ labels = $labelText; datasets = $datasets.ToArray() }
        options = [ordered]@{
            plugins = [ordered]@{
                title  = [ordered]@{ display = $true; text = '100.000 TL ile getiri karşılaştırması (%)' }
                legend = [ordered]@{ position = 'bottom'; labels = [ordered]@{ boxWidth = 12; font = [ordered]@{ size = 10 } } }
            }
            scales = [ordered]@{
                x = [ordered]@{ title = [ordered]@{ display = $true; text = 'Tarih' } }
                y = [ordered]@{ title = [ordered]@{ display = $true; text = '% getiri' } }
            }
        }
    }

    $payload = [ordered]@{ width = 860; height = 480; backgroundColor = 'white'; chart = $config }
    $json = $payload | ConvertTo-Json -Depth 20 -Compress
    # Windows PowerShell 5.1 string govdeyi UTF-8 gondermez -> Turkce karakterler
    # bozulur (Portf�y�). Govdeyi UTF-8 byte dizisi olarak yolla + charset belirt.
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    try {
        $resp = Invoke-WithRetry -OperationName 'QuickChart' -MaxAttempts 2 -BaseDelaySec 1 -ScriptBlock {
            Invoke-RestMethod -Uri 'https://quickchart.io/chart/create' -Method Post -Body $bodyBytes -ContentType 'application/json; charset=utf-8' -TimeoutSec $TimeoutSec -ErrorAction Stop
        }
    }
    catch { return $null }
    $url = Get-ObjectPropertyValue -Object $resp -Name 'url'
    if (-not [string]::IsNullOrWhiteSpace($url)) { return [string]$url } else { return $null }
}

# ===========================================================================
#  FAZ A — Gozlem modu gostergeleri (skoru/portfoyu ETKILEMEZ; yalniz raporda)
# ===========================================================================

function Get-MarketBreadth {
    <#
        Piyasa genisligi: taranan tum evrende "kaç hisse trendde?" sorusunu olcer.
        Endeks birkac dev hisseyle yukseliyor olabilir; genislik bunu yakalar.
        Ekstra veri GEREKMEZ — mevcut tarama ($Stocks) uzerinde sayim yapar.
        Donus: oranlar (%) + ozet etiket. Skoru/secimi DEGISTIRMEZ (gozlem modu).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Stocks)

    $aboveSma200 = 0; $sma200Total = 0
    $aboveSma50 = 0; $sma50Total = 0
    $posMonth = 0; $monthTotal = 0
    $stackedUp = 0; $stackedTotal = 0   # 50 > 200 dizilim (yukseli trend yapisi)

    foreach ($s in $Stocks) {
        $price = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'Price')
        $sma50 = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'SMA50')
        $sma200 = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'SMA200')
        $perfM = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name 'PerfMonth')

        if ($null -ne $price -and $null -ne $sma200 -and $sma200 -gt 0) { $sma200Total++; if ($price -ge $sma200) { $aboveSma200++ } }
        if ($null -ne $price -and $null -ne $sma50 -and $sma50 -gt 0) { $sma50Total++; if ($price -ge $sma50) { $aboveSma50++ } }
        if ($null -ne $perfM) { $monthTotal++; if ($perfM -gt 0) { $posMonth++ } }
        if ($null -ne $sma50 -and $null -ne $sma200 -and $sma200 -gt 0) { $stackedTotal++; if ($sma50 -ge $sma200) { $stackedUp++ } }
    }

    $pct = { param($n, $d) if ($d -gt 0) { [Math]::Round(($n / [double]$d) * 100.0, 1) } else { $null } }
    $aboveSma200Pct = & $pct $aboveSma200 $sma200Total

    # Ozet etiket: SMA200 ustu orani genel rejim gostergesidir.
    $label = 'Veri Yok'
    if ($null -ne $aboveSma200Pct) {
        $label = if ($aboveSma200Pct -ge 60) { 'Genis (güçlü katılım)' }
        elseif ($aboveSma200Pct -ge 40) { 'Orta' }
        else { 'Dar (zayıf katılım)' }
    }

    return [pscustomobject][ordered]@{
        AboveSMA200Pct = $aboveSma200Pct
        AboveSMA50Pct  = & $pct $aboveSma50 $sma50Total
        PositiveMonthPct = & $pct $posMonth $monthTotal
        StackedUpPct   = & $pct $stackedUp $stackedTotal   # 50 >= 200 dizilimi
        SampleCount    = $sma200Total
        Label          = $label
        Note           = 'Gözlem modu: piyasa genişliği yalnız bağlam içindir; skoru/seçimi etkilemez.'
    }
}

function Add-RelativeStrengthRank {
    <#
        Hisse-bazli goreli guc (RS) sirasi: her hissenin getirisini BIST100'e gore
        kesitsel persentile (0-100) cevirir. "Mutlak yukseldi mi" degil "endeksten
        daha mi iyi" olcer. Skorlanmis hisseler Bist100Perf* alanlarini icerir.
        Her hisseye RelativeStrengthRank (0-100) ekler. Skoru DEGISTIRMEZ (gozlem).
        Bilesik fazla getiri = 0.5*3A + 0.3*1Y + 0.2*1A (endekse gore).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Stocks)

    $excessOf = {
        param($s)
        $g = { param($n) ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $s -Name $n) }
        $m = & $g 'PerfMonth'; $q = & $g 'Perf3Month'; $y = & $g 'PerfYear'
        $bm = & $g 'Bist100PerfMonth'; $bq = & $g 'Bist100Perf3Month'; $by = & $g 'Bist100PerfYear'
        # Eksik endeks getirisi 0 kabul edilir (mutlak getiriye duser).
        $bmv = if ($null -ne $bm) { [double]$bm } else { 0.0 }
        $bqv = if ($null -ne $bq) { [double]$bq } else { 0.0 }
        $byv = if ($null -ne $by) { [double]$by } else { 0.0 }
        $em = if ($null -ne $m) { [double]$m - $bmv } else { $null }
        $eq = if ($null -ne $q) { [double]$q - $bqv } else { $null }
        $ey = if ($null -ne $y) { [double]$y - $byv } else { $null }
        $parts = @(); $w = 0.0; $acc = 0.0
        if ($null -ne $eq) { $acc += 0.5 * $eq; $w += 0.5 }
        if ($null -ne $ey) { $acc += 0.3 * $ey; $w += 0.3 }
        if ($null -ne $em) { $acc += 0.2 * $em; $w += 0.2 }
        if ($w -le 0) { return $null }
        return $acc / $w
    }

    $stocksArr = @($Stocks)
    $scoresList = [System.Collections.Generic.List[double]]::new()
    $excessVals = @{}
    for ($i = 0; $i -lt $stocksArr.Count; $i++) {
        $e = & $excessOf $stocksArr[$i]
        $excessVals[$i] = $e
        if ($null -ne $e) { [void]$scoresList.Add([double]$e) }
    }
    $sorted = @($scoresList.ToArray() | Sort-Object)
    $n = $sorted.Count

    for ($i = 0; $i -lt $stocksArr.Count; $i++) {
        $rank = $null
        $e = $excessVals[$i]
        if ($null -ne $e -and $n -gt 1) {
            # persentil: kendisinden kucuk/esit olanlarin orani
            $below = 0
            foreach ($v in $sorted) { if ($v -le $e) { $below++ } }
            $rank = [Math]::Round((($below - 1) / [double]($n - 1)) * 100.0, 0)
            if ($rank -lt 0) { $rank = 0 }
        }
        elseif ($null -ne $e -and $n -eq 1) { $rank = 50 }
        $stocksArr[$i] | Add-Member -NotePropertyName 'RelativeStrengthRank' -NotePropertyValue $rank -Force
    }
    return $stocksArr
}

function Get-CrossPortfolioConcentration {
    <#
        TUM model portfoyler arasinda her hissenin TOPLAM TL maruziyetini ve defterin
        yuzdesini hesaplar; esigi (vars. %12) gecenleri isaretler. Portfoyler-arasi
        gizli yogunlasma riskini GOZLEMLEMEK icin (secimi degistirmez).
    #>
    param($PortfolioSet, [double]$WarnPct = 12.0)

    $bySymbol = @{}
    $totalBook = 0.0
    foreach ($p in @(Get-ObjectPropertyValue -Object $PortfolioSet -Name 'Portfolios')) {
        foreach ($h in @(Get-ObjectPropertyValue -Object $p -Name 'Holdings')) {
            $sym = [string](Get-ObjectPropertyValue -Object $h -Name 'Symbol')
            if ([string]::IsNullOrWhiteSpace($sym)) { continue }
            $v = ConvertTo-DoubleOrNull (Get-ObjectPropertyValue -Object $h -Name 'CurrentValueTL')
            if ($null -eq $v) { $v = 0.0 }
            if (-not $bySymbol.ContainsKey($sym)) {
                $bySymbol[$sym] = [pscustomobject]@{
                    Symbol = $sym
                    Company = [string](Get-ObjectPropertyValue -Object $h -Name 'Company')
                    ValueTL = 0.0
                    PortfolioCount = 0
                }
            }
            $bySymbol[$sym].ValueTL += $v
            $bySymbol[$sym].PortfolioCount += 1
            $totalBook += $v
        }
    }
    $rows = foreach ($s in $bySymbol.Values) {
        $pct = if ($totalBook -gt 0) { ($s.ValueTL / $totalBook) * 100.0 } else { 0.0 }
        [pscustomobject][ordered]@{
            Symbol = $s.Symbol
            Company = $s.Company
            PortfolioCount = $s.PortfolioCount
            ValueTL = [Math]::Round($s.ValueTL, 2)
            BookPct = [Math]::Round($pct, 2)
            Warn = ($pct -ge $WarnPct)
        }
    }
    return @($rows | Sort-Object BookPct -Descending)
}

function Get-DataQualitySummary {
    <#
        Kritik makro/benchmark girdilerinin (USD/TRY, BIST100, TR10Y, DXY, VIX) ve
        hisse temel verisinin eksikligini ozetler. Rapor, veri bozuldugunda GORUNUR
        uyari gostersin diye; sessizce yanlis skor/alfa uretmeyi onler.
        $Inputs: ad -> deger (null/bos/<=0 = eksik).
    #>
    param([hashtable]$Inputs, [int]$StocksMissingFundamentals = 0, [int]$TotalStocks = 0)

    # Eksik = null / sayisal-olmayan (kaynak HIC veri dondurmedi). Negatif/sifir
    # gecerli olabilir (degisim%, CDS) — bunlari eksik sayma; cagiran taraf seviye
    # girdilerini (or. BIST100=0) eksikse null olarak gecirir.
    # NOT: ConvertTo-DoubleOrNull burada KULLANILMAZ; PowerShell'de "0 -eq ''" true
    # oldugundan gecerli bir 0'i eksik sayar. Burada eksik = null VEYA sayisal-degil.
    $missing = New-Object System.Collections.Generic.List[string]
    if ($null -ne $Inputs) {
        foreach ($k in @($Inputs.Keys)) {
            $v = $Inputs[$k]
            $isMissing = $false
            if ($null -eq $v) {
                $isMissing = $true
            }
            else {
                try { [void][double]$v } catch { $isMissing = $true }
            }
            if ($isMissing) { [void]$missing.Add([string]$k) }
        }
    }
    $count = if ($null -ne $Inputs) { $Inputs.Count } else { 0 }
    $present = $count - $missing.Count
    $completeness = if ($count -gt 0) { [Math]::Round(($present / [double]$count) * 100.0, 0) } else { 100 }
    $staleRatio = if ($TotalStocks -gt 0) { $StocksMissingFundamentals / [double]$TotalStocks } else { 0.0 }
    $degraded = ($missing.Count -gt 0) -or ($staleRatio -gt 0.25)
    return [pscustomobject][ordered]@{
        CompletenessPct = $completeness
        MissingInputs = @($missing.ToArray())
        StocksMissingFundamentals = $StocksMissingFundamentals
        TotalStocks = $TotalStocks
        StaleRatioPct = [Math]::Round($staleRatio * 100.0, 1)
        Degraded = $degraded
    }
}

Export-ModuleMember -Function `
    Invoke-WithRetry, `
    Update-SignalPerformance, `
    Add-AcademicFactorScore, `
    Get-Momentum12_1Pct, `
    Resolve-InflationBenchmark, `
    Get-CumulativeInflationFromIndexPoints, `
    Add-EarningsTiming, `
    Get-EarningsSurpriseScore, `
    Get-EarningsTimingAdjustment, `
    Get-SignalCalibration, `
    Set-SignalCalibration, `
    Update-SignalCalibration, `
    Add-DataQualityAssessment, `
    Update-EarningsReactions, `
    Get-KapDisclosures, `
    Get-StoredKapDisclosures, `
    Get-YahooDailyCloseSeries, `
    Get-YahooDailyOhlcSeries, `
    Get-PriceStructureSignal, `
    Get-PriceStructureSignals, `
    Invoke-BistStockScan, `
    Get-ObjectPropertyValue, `
    Get-BistScore, `
    Get-BistScores, `
    Add-RawFactorScore, `
    Get-StaticFactorWeights, `
    Get-RawFactorVector, `
    Get-EvdsSeries, `
    Get-EvdsForeignEquityFlow, `
    Add-ForeignOwnershipData, `
    Add-InsiderSignalData, `
    Get-SmartMoneyAdjustment, `
    Get-FlowRegimeStatus, `
    Get-FlowMacroMetrics, `
    Get-MacroRegime, `
    Add-MacroRegimeData, `
    Get-AdjustmentImpactLog, `
    Add-JsonlLine, `
    Add-HoldingFlag, `
    Get-SignalVerdict, `
    Get-RegimeCashTarget, `
    Get-CircuitBreakerState, `
    Get-SignalConfig, `
    Set-SignalConfig, `
    Get-MacroSnapshotMetric, `
    Get-ModelPortfolioDefinitions, `
    Get-ModelPortfolioSelection, `
    Get-LastModelPortfolioTradingDay, `
    Get-BistMarketNow, `
    Get-LatestCompletedModelPortfolioPeriodEnd, `
    Get-MacroSnapshot, `
    Get-BistIndexBenchmarks, `
    Get-InstantEntryOpportunities, `
    Get-InstantEntryExitDecision, `
    Get-InstantEntryCashTL, `
    New-ModelPortfolioSet, `
    Update-ModelPortfolioSet, `
    Save-PitSnapshot, `
    Get-PitSnapshot, `
    Get-StrategyPerformanceSeries, `
    Get-BenchmarkPerformanceSeries, `
    Save-BenchmarkPerfCache, `
    Read-BenchmarkPerfCache, `
    New-PerformanceComparisonChart, `
    Get-MarketBreadth, `
    Add-RelativeStrengthRank, `
    Get-StrategySelectionScore, `
    Get-CrossPortfolioConcentration, `
    Get-DataQualitySummary, `
    Optimize-ModelPortfolioSetRisk, `
    Get-RawFactorVector, `
    Get-LearnedFactorWeights, `
    Get-WalkForwardFactorWeights
