param(
    [string]$SettingsPath = (Join-Path $PSScriptRoot 'config\report_settings.json'),
    [switch]$NoSend
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'BistScanner.Core.psm1'
Import-Module $modulePath -Force

function Resolve-ReportPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    if ([IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $PSScriptRoot $Path
}

function Get-ConfigValue {
    param(
        $Object,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $Default
    }

    return $property.Value
}

function Get-EnvironmentValue {
    param(
        [string[]]$Names,
        [string]$Default = ''
    )

    foreach ($name in $Names) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $value = [Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    return $Default
}

function ConvertTo-BooleanValue {
    param(
        $Value,
        [bool]$Default = $false
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $Default
    }

    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ($text -in @('1', 'true', 'yes', 'y', 'evet', 'on')) { return $true }
    if ($text -in @('0', 'false', 'no', 'n', 'hayir', 'hayır', 'off')) { return $false }

    try {
        return [bool]$Value
    }
    catch {
        return $Default
    }
}

function Get-EmailCredential {
    param(
        $Settings,
        [string]$DefaultUsername
    )

    $envUsername = Get-EnvironmentValue -Names @('BIST_SMTP_USERNAME', 'SMTP_USERNAME') -Default ''
    $envPassword = Get-EnvironmentValue -Names @('BIST_SMTP_PASSWORD', 'SMTP_PASSWORD') -Default ''
    if (-not [string]::IsNullOrWhiteSpace($envPassword)) {
        $username = if (-not [string]::IsNullOrWhiteSpace($envUsername)) { $envUsername } else { $DefaultUsername }
        if ([string]::IsNullOrWhiteSpace($username)) {
            throw 'SMTP sifresi env degiskeninde var ama kullanici adi yok. BIST_SMTP_USERNAME veya Email.From doldurulmali.'
        }

        $securePassword = ConvertTo-SecureString $envPassword -AsPlainText -Force
        return [Management.Automation.PSCredential]::new($username, $securePassword)
    }

    $credentialPath = Resolve-ReportPath -Path ([string](Get-ConfigValue -Object $Settings.Email -Name 'CredentialPath' -Default 'config/smtp_credential.xml'))
    if (-not [string]::IsNullOrWhiteSpace($credentialPath) -and (Test-Path $credentialPath)) {
        return Import-Clixml -Path $credentialPath
    }

    throw "SMTP kimlik bilgisi yok. Bulutta BIST_SMTP_USERNAME/BIST_SMTP_PASSWORD secrets kullanin; yerelde Kaydet-EpostaKimligi.ps1 calistirin."
}

function Format-ReportNumber {
    param(
        $Value,
        [string]$Format = 'N1',
        [string]$Suffix = ''
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return '-'
    }

    try {
        $template = '{0:' + $Format + '}{1}'
        return $template -f ([double]$Value), $Suffix
    }
    catch {
        return [string]$Value
    }
}

function ConvertTo-PlainText {
    param($Value)

    if ($null -eq $Value) {
        return '-'
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return '-'
    }

    return $text
}

function ConvertTo-HtmlText {
    param($Value)

    return [Net.WebUtility]::HtmlEncode((ConvertTo-PlainText $Value))
}

function Get-NumberValue {
    param(
        $Object,
        [string]$Name
    )

    $value = Get-ObjectPropertyValue -Object $Object -Name $Name
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
        return $null
    }

    try {
        return [double]$value
    }
    catch {
        return $null
    }
}

function Get-RecommendationText {
    param($Stock)

    $recommendation = Get-NumberValue -Object $Stock -Name 'Recommendation'
    if ($null -eq $recommendation) { return 'teknik ozet verisi yok' }
    if ($recommendation -ge 0.50) { return 'TradingView teknik özeti güçlü al bölgesinde' }
    if ($recommendation -ge 0.10) { return 'TradingView teknik ozeti al bolgesinde' }
    if ($recommendation -gt -0.10) { return 'TradingView teknik ozeti notr' }
    if ($recommendation -gt -0.50) { return 'TradingView teknik ozeti sat bolgesinde' }
    return 'TradingView teknik özeti güçlü sat bölgesinde'
}

function Get-MacdText {
    param(
        $Line,
        $Signal,
        $Histogram,
        [string]$Prefix
    )

    if ($null -eq $Line -or $null -eq $Signal -or $null -eq $Histogram) {
        return "$Prefix MACD verisi yok"
    }

    $status = if ($Line -gt $Signal -and $Histogram -gt 0) {
        'al teyidi var'
    }
    elseif ($Histogram -gt 0) {
        'histogram pozitif, toparlanma var'
    }
    elseif ($Line -gt $Signal) {
        'cizgi sinyalin ustunde ama histogram zayif'
    }
    else {
        'al teyidi yok'
    }

    return '{0} MACD {1}: cizgi {2}, sinyal {3}, histogram {4}' -f `
        $Prefix, `
        $status, `
        (Format-ReportNumber -Value $Line -Format 'N2'), `
        (Format-ReportNumber -Value $Signal -Format 'N2'), `
        (Format-ReportNumber -Value $Histogram -Format 'N2')
}

function Get-RsiText {
    param(
        $Value,
        [string]$Prefix
    )

    if ($null -eq $Value) {
        return "$Prefix RSI verisi yok"
    }

    $status = if ($Value -ge 40 -and $Value -le 60) {
        'saglikli momentum bandinda'
    }
    elseif ($Value -gt 60 -and $Value -le 70) {
        'momentum güçlü, aşırı alıma yaklaşıyor'
    }
    elseif ($Value -gt 70) {
        'asiri alim riski var'
    }
    elseif ($Value -ge 30) {
        'zayif ama toparlanabilir bantta'
    }
    else {
        'zayif momentum bolgesinde'
    }

    return '{0} RSI {1}: {2}' -f $Prefix, (Format-ReportNumber -Value $Value -Format 'N1'), $status
}

function Get-RelativeVolumeText {
    param($Value)

    if ($null -eq $Value) {
        return 'hacim verisi yok'
    }

    $status = if ($Value -ge 1.5) {
        'hacim patlaması var, talep teyidi güçlü'
    }
    elseif ($Value -ge 1.0) {
        'hacim ortalama ustu/normal, teyit orta'
    }
    elseif ($Value -ge 0.8) {
        'hacim hafif zayif, teyit sinirli'
    }
    else {
        'hacim dusuk, teyit zayif'
    }

    return 'Goreli hacim {0}: {1}' -f (Format-ReportNumber -Value $Value -Format 'N2' -Suffix 'x'), $status
}

function Get-AboveSma200Text {
    param($Stock)

    $price = Get-NumberValue -Object $Stock -Name 'Price'
    $sma200 = Get-NumberValue -Object $Stock -Name 'SMA200'
    if ($null -eq $price -or $null -eq $sma200 -or $sma200 -le 0) {
        return '200 gunluk ortalama verisi yok'
    }

    $distance = (($price / $sma200) - 1) * 100
    if ($price -ge $sma200) {
        return 'Fiyat 200 gunluk ortalamanin {0} uzerinde; ana trend pozitif okunuyor' -f (Format-ReportNumber -Value $distance -Format 'N1' -Suffix '%')
    }

    return 'Fiyat 200 gunluk ortalamanin {0} altinda; ana trend henuz tam teyitli degil' -f (Format-ReportNumber -Value ([Math]::Abs($distance)) -Format 'N1' -Suffix '%')
}

function Get-ConfirmationRank {
    param($Stock)

    $label = [string](Get-ObjectPropertyValue -Object $Stock -Name 'ConfirmationLabel')
    switch ($label) {
        'Tüm Teyitli Güçlü Aday' { return 1 }
        'Teknik Teyitli Güçlü İzle' { return 2 }
        'Temel İyi, Teknik İzle' { return 3 }
        'Sektör Güçlü, Teknik İzle' { return 4 }
        default { return 5 }
    }
}

function Get-StockDetailedReasonHtml {
    param($Stock)

    $sectorDiff = Get-NumberValue -Object $Stock -Name 'SectorRotationAverage'
    if ($null -eq $sectorDiff) {
        $sectorDiff = Get-NumberValue -Object $Stock -Name 'SectorVsBist3Month'
    }
    $sectorFlow = if ($null -eq $sectorDiff) {
        'Sektor rotasyonu hesaplanamadi.'
    }
    elseif ($sectorDiff -ge 5) {
        'Sektor BIST100e gore son 3 ayda pozitif ayrisiyor; para akisi bu taramada sektor lehine okunuyor.'
    }
    elseif ($sectorDiff -ge 0) {
        'Sektor BIST100e yakin/az pozitif; para akisi notr-pozitif.'
    }
    else {
        'Sektor BIST100e gore geride; sektor destegi sinirli.'
    }

    $stockVsInflation = Get-NumberValue -Object $Stock -Name 'StockVsInflation1YPct'
    $stockVsBist = Get-NumberValue -Object $Stock -Name 'StockVsBist1YPct'
    $macroText = @(
        $sectorFlow
        ('Sektor rotasyonu: {0}, izlenen endeks/proxy {1}. Farklar: gun {2}, hafta {3}, 1A {4}, 3A {5}, 1Y {6}; ortalama {7} puan.' -f `
            (ConvertTo-PlainText (Get-ObjectPropertyValue -Object $Stock -Name 'SectorRotationLabel')), `
            (ConvertTo-PlainText (Get-ObjectPropertyValue -Object $Stock -Name 'SectorWatchIndex')), `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'SectorVsBistDay') -Format 'N1'), `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'SectorVsBistWeek') -Format 'N1'), `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'SectorVsBistMonth') -Format 'N1'), `
            (Format-ReportNumber -Value $sectorDiff -Format 'N1'), `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'SectorVsBistYear') -Format 'N1'), `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'SectorRotationAverage') -Format 'N1'))
        ('Hisse 1Y: enflasyona gore {0} puan, BIST100e gore {1} puan.' -f `
            (Format-ReportNumber -Value $stockVsInflation -Format 'N1'), `
            (Format-ReportNumber -Value $stockVsBist -Format 'N1'))
        'Makro panelde CDS, TR10Y, USD/TRY, DXY, VIX ve BIST trendi ayrıca gösterilir; ücretsiz kaynaklar gecikmeli veya eksik olabilir.'
    )

    $fundamentalText = @(
        ('Bilanço puani {0}, kalite puani {1}, deger puani {2}.' -f `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'EarningsScore') -Format 'N1'), `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'QualityScore') -Format 'N1'), `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'ValueScore') -Format 'N1'))
        ('ROE {0}, F/K {1}, PD/DD {2}, FD/FAVOK {3}.' -f `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'ROE') -Format 'N1' -Suffix '%'), `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'PE') -Format 'N2'), `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'PB') -Format 'N2'), `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'EvEbitda') -Format 'N2'))
        ('USD net kar Y/Y {0}, USD FAVOK Y/Y {1}, FAVOK trendi {2}, son 5 çeyrekte karlı dönem {3}.' -f `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'NetIncomeUsdYoYPct') -Format 'N1' -Suffix '%'), `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'EbitdaUsdYoYPct') -Format 'N1' -Suffix '%'), `
            (ConvertTo-PlainText (Get-ObjectPropertyValue -Object $Stock -Name 'EbitdaTrendLabel')), `
            (ConvertTo-PlainText (Get-ObjectPropertyValue -Object $Stock -Name 'PositiveQuarterCount')))
        'USD güçlü bilanço filtresi: {0}.' -f (ConvertTo-PlainText (Get-ObjectPropertyValue -Object $Stock -Name 'StrongUsdEarningsLabel'))
    )

    $dailyMacd = Get-MacdText `
        -Line (Get-NumberValue -Object $Stock -Name 'MacdLine') `
        -Signal (Get-NumberValue -Object $Stock -Name 'MacdSignal') `
        -Histogram (Get-NumberValue -Object $Stock -Name 'MacdHistogram') `
        -Prefix 'Gunluk'
    $weeklyMacd = Get-MacdText `
        -Line (Get-NumberValue -Object $Stock -Name 'MacdLineWeekly') `
        -Signal (Get-NumberValue -Object $Stock -Name 'MacdSignalWeekly') `
        -Histogram (Get-NumberValue -Object $Stock -Name 'MacdHistogramWeekly') `
        -Prefix 'Haftalik'
    $monthlyMacd = Get-MacdText `
        -Line (Get-NumberValue -Object $Stock -Name 'MacdLineMonthly') `
        -Signal (Get-NumberValue -Object $Stock -Name 'MacdSignalMonthly') `
        -Histogram (Get-NumberValue -Object $Stock -Name 'MacdHistogramMonthly') `
        -Prefix 'Aylik'

    $technicalText = @(
        (Get-RecommendationText -Stock $Stock)
        (Get-AboveSma200Text -Stock $Stock)
        ('Gunluk degisim {0}, haftalik performans {1}, aylik performans {2}.' -f `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'ChangePct') -Format 'N2' -Suffix '%'), `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'PerfWeek') -Format 'N2' -Suffix '%'), `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'PerfMonth') -Format 'N2' -Suffix '%'))
        (Get-RsiText -Value (Get-NumberValue -Object $Stock -Name 'RSI') -Prefix 'Gunluk')
        (Get-RsiText -Value (Get-NumberValue -Object $Stock -Name 'RSIWeekly') -Prefix 'Haftalik')
        (Get-RsiText -Value (Get-NumberValue -Object $Stock -Name 'RSIMonthly') -Prefix 'Aylik')
        $dailyMacd
        $weeklyMacd
        $monthlyMacd
        (Get-RelativeVolumeText -Value (Get-NumberValue -Object $Stock -Name 'RelativeVolume'))
    )

    $confirmationLabel = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $Stock -Name 'ConfirmationLabel')
    $entryNote = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $Stock -Name 'EntryNote')
    $failedConfirmations = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $Stock -Name 'FailedConfirmations')
    $technicalPassCount = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $Stock -Name 'TechnicalPassCount')
    $technicalCheckCount = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $Stock -Name 'TechnicalCheckCount')
    $whyText = @(
        ('Teyit etiketi: {0}. Teknik teyit sayisi {1}/{2}.' -f $confirmationLabel, $technicalPassCount, $technicalCheckCount)
        ('Güçlü izleme gerekcesi: skor {0} / sinyal {1}; makro-sektor puani {2}, bilanço puani {3}, momentum puani {4}.' -f `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'Score') -Format 'N1'), `
            (ConvertTo-PlainText (Get-ObjectPropertyValue -Object $Stock -Name 'Signal')), `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'MacroSectorScore') -Format 'N1'), `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'EarningsScore') -Format 'N1'), `
            (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'MomentumScore') -Format 'N1'))
        $entryNote
        ('Eksik teyitler: {0}.' -f $(if ($failedConfirmations -eq '-') { 'yok' } else { $failedConfirmations }))
        'Yorum: makro/sektor destegi, temel kalite ve teknik teyit ayni yondeyse izleme kalitesi artar; bir bacak zayifsa kademeli giris ve teyit bekleme disiplini gerekir.'
    )

    $section = {
        param([string]$Title, [string[]]$Items)
        '<h4>{0}</h4><ul>{1}</ul>' -f `
            (ConvertTo-HtmlText $Title), `
            (($Items | ForEach-Object { '<li>{0}</li>' -f (ConvertTo-HtmlText $_) }) -join '')
    }

    $symbolHtml = ConvertTo-HtmlText (Get-ObjectPropertyValue -Object $Stock -Name 'Symbol')
    $companyHtml = ConvertTo-HtmlText (Get-ObjectPropertyValue -Object $Stock -Name 'Company')
    $sectorHtml = ConvertTo-HtmlText (Get-ObjectPropertyValue -Object $Stock -Name 'SectorTR')
    $signalHtml = ConvertTo-HtmlText (Get-ObjectPropertyValue -Object $Stock -Name 'Signal')
    $priceHtml = ConvertTo-HtmlText (Format-ReportNumber -Value (Get-NumberValue -Object $Stock -Name 'Price') -Format 'N2' -Suffix ' TL')
    $labelHtml = ConvertTo-HtmlText $confirmationLabel

    return @(
        '<div class="detail-card">'
        "<h3>$symbolHtml - $companyHtml</h3>"
        "<p><span class=`"badge`">$labelHtml</span></p>"
        "<p class=`"muted`">$sectorHtml | $signalHtml | Fiyat $priceHtml</p>"
        (& $section 'Makro ne diyor?' $macroText)
        (& $section 'Temel ne diyor?' $fundamentalText)
        (& $section 'Teknik ne diyor?' $technicalText)
        (& $section 'Neden güçlü izlemeliyim?' $whyText)
        '</div>'
    ) -join [Environment]::NewLine
}

function New-HtmlTable {
    param([object[]]$Rows)

    if ($null -eq $Rows -or $Rows.Count -eq 0) {
        return '<p class="muted">Veri yok.</p>'
    }

    return ($Rows | ConvertTo-Html -Fragment)
}

function Get-PortfolioSymbolTransaction {
    param(
        $Portfolio,
        [string]$Symbol,
        [ValidateSet('Buy', 'Sell', 'Any')]
        [string]$Side = 'Any',
        [switch]$Last
    )

    $matches = @(
        @(Get-ObjectPropertyValue -Object $Portfolio -Name 'Transactions') |
            Where-Object {
                $transactionSymbol = [string](Get-ObjectPropertyValue -Object $_ -Name 'Symbol')
                $action = [string](Get-ObjectPropertyValue -Object $_ -Name 'Action')
                if ($transactionSymbol -ne $Symbol) { return $false }
                if ($Side -eq 'Buy') { return ($action -like '*AL*' -and $action -notlike '*SAT*') }
                if ($Side -eq 'Sell') { return ($action -like '*SAT*') }
                return $true
            }
    )

    if ($matches.Count -eq 0) {
        return $null
    }

    $ordered = if ($Last) {
        @($matches | Sort-Object @{ Expression = { [int](Get-ObjectPropertyValue -Object $_ -Name 'Sequence') }; Descending = $true })
    }
    else {
        @($matches | Sort-Object @{ Expression = { [int](Get-ObjectPropertyValue -Object $_ -Name 'Sequence') }; Descending = $false })
    }

    return $ordered[0]
}

function Get-TransactionPriceReturnPct {
    param(
        $ReferenceTransaction,
        $CurrentPrice
    )

    $referencePrice = Get-NumberValue -Object $ReferenceTransaction -Name 'Price'
    if ($null -eq $referencePrice -or $referencePrice -le 0 -or $null -eq $CurrentPrice -or [double]$CurrentPrice -le 0) {
        return $null
    }

    return (([double]$CurrentPrice - $referencePrice) / $referencePrice) * 100
}

function Get-ModelPortfolioHoldingRows {
    param($PortfolioSet)

    return @($PortfolioSet.Portfolios | ForEach-Object {
            $portfolio = $_
            @(Get-ObjectPropertyValue -Object $portfolio -Name 'Holdings') | ForEach-Object {
                $holding = $_
                $symbol = [string](Get-ObjectPropertyValue -Object $holding -Name 'Symbol')
                $firstBuy = Get-PortfolioSymbolTransaction -Portfolio $portfolio -Symbol $symbol -Side Buy
                $firstSell = Get-PortfolioSymbolTransaction -Portfolio $portfolio -Symbol $symbol -Side Sell
                $lastTransaction = Get-PortfolioSymbolTransaction -Portfolio $portfolio -Symbol $symbol -Side Any -Last
                $currentPrice = Get-NumberValue -Object $holding -Name 'CurrentPrice'

                [pscustomobject][ordered]@{
                    Portfoy = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $portfolio -Name 'Name')
                    Sembol = ConvertTo-PlainText $symbol
                    Sirket = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $holding -Name 'Company')
                    Sektor = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $holding -Name 'SectorTR')
                    Adet = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $holding -Name 'Quantity') -Format 'N4'
                    'Ilk Alis Tarihi' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $firstBuy -Name 'ExecutionDateText')
                    'Ilk Alis Fiyati' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $firstBuy -Name 'Price') -Format 'N2' -Suffix ' TL'
                    'Ilk Satis Fiyati' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $firstSell -Name 'Price') -Format 'N2' -Suffix ' TL'
                    'Son Islem' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $lastTransaction -Name 'Action')
                    'Son Rebalance Fiyati' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $holding -Name 'RebalancePrice') -Format 'N2' -Suffix ' TL'
                    'Guncel Fiyat' = Format-ReportNumber -Value $currentPrice -Format 'N2' -Suffix ' TL'
                    'Maliyet' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $holding -Name 'CostBasisTL') -Format 'N2' -Suffix ' TL'
                    'Guncel Deger' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $holding -Name 'CurrentValueTL') -Format 'N2' -Suffix ' TL'
                    'Agirlik' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $holding -Name 'WeightPct') -Format 'N2' -Suffix '%'
                    'Rebalance Getirisi' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $holding -Name 'GainSinceRebalancePct') -Format 'N2' -Suffix '%'
                    'Ilk Alistan Getiri' = Format-ReportNumber -Value (Get-TransactionPriceReturnPct -ReferenceTransaction $firstBuy -CurrentPrice $currentPrice) -Format 'N2' -Suffix '%'
                    Gerekce = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $holding -Name 'SelectionReason')
                }
            }
        })
}

function Get-ModelPortfolioTransactionRows {
    param(
        $PortfolioSet,
        [int]$PerPortfolio = 12
    )

    return @($PortfolioSet.Portfolios | ForEach-Object {
            $portfolio = $_
            @(
                @(Get-ObjectPropertyValue -Object $portfolio -Name 'Transactions') |
                    Sort-Object @{ Expression = { [int](Get-ObjectPropertyValue -Object $_ -Name 'Sequence') }; Descending = $true } |
                    Select-Object -First $PerPortfolio
            ) | ForEach-Object {
                [pscustomobject][ordered]@{
                    Portfoy = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $portfolio -Name 'Name')
                    Sira = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Sequence')
                    Tarih = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'ExecutionDateText')
                    Islem = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Action')
                    Sembol = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Symbol')
                    Sirket = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Company')
                    Fiyat = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'Price') -Format 'N2' -Suffix ' TL'
                    Adet = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'Quantity') -Format 'N4'
                    Tutar = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'AmountTL') -Format 'N2' -Suffix ' TL'
                    Not = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Note')
                }
            }
        })
}

function Save-JsonFile {
    param(
        [string]$Path,
        $Value,
        [int]$Depth = 8
    )

    $directory = Split-Path $Path -Parent
    if (-not (Test-Path $directory)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }

    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth $Depth), [Text.UTF8Encoding]::new($true))
}

function Load-ReportSettings {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        $examplePath = Join-Path $PSScriptRoot 'config\report_settings.example.json'
        if (Test-Path $examplePath) {
            $directory = Split-Path $Path -Parent
            if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path $directory)) {
                [void](New-Item -ItemType Directory -Path $directory -Force)
            }
            Copy-Item -Path $examplePath -Destination $Path -Force
        }
    }

    if (Test-Path $Path) {
        return Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    return [pscustomobject]@{
        Report = [pscustomobject]@{ Strategy = 'Dengeli'; TopCount = 20; OutputDirectory = 'reports' }
        Send = [pscustomobject]@{ EmailEnabled = $false; TelegramEnabled = $false }
        Email = [pscustomobject]@{}
        Telegram = [pscustomobject]@{}
    }
}

function Send-EmailReport {
    param(
        $Settings,
        [string]$Subject,
        [string]$HtmlBody,
        [string]$HtmlPath,
        [string]$CsvPath
    )

    $server = Get-EnvironmentValue -Names @('BIST_SMTP_SERVER', 'SMTP_SERVER') -Default ([string](Get-ConfigValue -Object $Settings.Email -Name 'SmtpServer' -Default ''))
    $from = Get-EnvironmentValue -Names @('BIST_EMAIL_FROM', 'EMAIL_FROM') -Default ([string](Get-ConfigValue -Object $Settings.Email -Name 'From' -Default ''))
    $toEnv = Get-EnvironmentValue -Names @('BIST_EMAIL_TO', 'EMAIL_TO') -Default ''
    $rawTo = if (-not [string]::IsNullOrWhiteSpace($toEnv)) {
        $toEnv -split '[,;]'
    }
    else {
        @(Get-ConfigValue -Object $Settings.Email -Name 'To' -Default @())
    }
    $to = @($rawTo | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ([string]::IsNullOrWhiteSpace($server) -or [string]::IsNullOrWhiteSpace($from) -or $to.Count -eq 0) {
        throw 'E-posta gonderimi icin SmtpServer, From ve To alanlari doldurulmali.'
    }

    $credential = Get-EmailCredential -Settings $Settings -DefaultUsername $from

    $attachments = [System.Collections.Generic.List[string]]::new()
    if (Test-Path $HtmlPath) { [void]$attachments.Add($HtmlPath) }
    $attachCsv = [bool](Get-ConfigValue -Object $Settings.Email -Name 'AttachCsv' -Default $true)
    if ($attachCsv -and (Test-Path $CsvPath)) { [void]$attachments.Add($CsvPath) }

    $port = [int](Get-EnvironmentValue -Names @('BIST_SMTP_PORT', 'SMTP_PORT') -Default ([string](Get-ConfigValue -Object $Settings.Email -Name 'Port' -Default 587)))
    $useSsl = ConvertTo-BooleanValue -Value (Get-EnvironmentValue -Names @('BIST_SMTP_USE_SSL', 'SMTP_USE_SSL') -Default ([string](Get-ConfigValue -Object $Settings.Email -Name 'UseSsl' -Default $true))) -Default $true
    $timeoutMs = [int](Get-EnvironmentValue -Names @('BIST_SMTP_TIMEOUT_MS', 'SMTP_TIMEOUT_MS') -Default ([string](Get-ConfigValue -Object $Settings.Email -Name 'TimeoutMs' -Default 30000)))

    $message = [Net.Mail.MailMessage]::new()
    $client = [Net.Mail.SmtpClient]::new($server, $port)
    try {
        $message.From = [Net.Mail.MailAddress]::new($from)
        foreach ($address in $to) {
            [void]$message.To.Add($address)
        }
        $message.Subject = $Subject
        $message.SubjectEncoding = [Text.Encoding]::UTF8
        $message.Body = $HtmlBody
        $message.BodyEncoding = [Text.Encoding]::UTF8
        $message.IsBodyHtml = $true
        foreach ($attachmentPath in $attachments) {
            [void]$message.Attachments.Add([Net.Mail.Attachment]::new($attachmentPath))
        }

        $client.EnableSsl = $useSsl
        $client.UseDefaultCredentials = $false
        $client.Credentials = $credential.GetNetworkCredential()
        $client.Timeout = $timeoutMs
        $client.Send($message)
    }
    finally {
        $message.Dispose()
        $client.Dispose()
    }
}

function Send-TelegramSummary {
    param(
        $Settings,
        [string]$Text
    )

    $token = Get-EnvironmentValue -Names @('BIST_TELEGRAM_BOT_TOKEN', 'TELEGRAM_BOT_TOKEN') -Default ([string](Get-ConfigValue -Object $Settings.Telegram -Name 'BotToken' -Default ''))
    $chatId = Get-EnvironmentValue -Names @('BIST_TELEGRAM_CHAT_ID', 'TELEGRAM_CHAT_ID') -Default ([string](Get-ConfigValue -Object $Settings.Telegram -Name 'ChatId' -Default ''))
    if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($chatId)) {
        throw 'Telegram gonderimi icin BotToken ve ChatId doldurulmali.'
    }

    $uri = "https://api.telegram.org/bot$token/sendMessage"
    $body = @{
        chat_id = $chatId
        text = $Text
        disable_web_page_preview = $true
    }
    Invoke-RestMethod -Uri $uri -Method Post -Body $body -TimeoutSec 30 | Out-Null
}

function Write-TimingLog {
    param(
        [string]$Step,
        [datetime]$StartedAt
    )

    $elapsed = [Math]::Round(((Get-Date) - $StartedAt).TotalSeconds, 1)
    Write-Host ("[timing] {0}: {1:N1}s" -f $Step, $elapsed)
}

$settings = Load-ReportSettings -Path $SettingsPath
$strategy = [string](Get-ConfigValue -Object $settings.Report -Name 'Strategy' -Default 'Dengeli')
$topCount = [int](Get-ConfigValue -Object $settings.Report -Name 'TopCount' -Default 20)
$detailedCount = [int](Get-ConfigValue -Object $settings.Report -Name 'DetailedCount' -Default 5)
$macroTimeoutSec = [int](Get-ConfigValue -Object $settings.Report -Name 'MacroTimeoutSec' -Default 6)
$instantEntryCandidateLimit = [int](Get-ConfigValue -Object $settings.Report -Name 'InstantEntryCandidateLimit' -Default 40)
$instantEntryTimeoutSec = [int](Get-ConfigValue -Object $settings.Report -Name 'InstantEntryTimeoutSec' -Default 5)
$instantEntryMaxElapsedSec = [int](Get-ConfigValue -Object $settings.Report -Name 'InstantEntryMaxElapsedSec' -Default 75)
$outputDirectory = Resolve-ReportPath -Path ([string](Get-ConfigValue -Object $settings.Report -Name 'OutputDirectory' -Default 'reports'))
if (-not (Test-Path $outputDirectory)) {
    [void](New-Item -ItemType Directory -Path $outputDirectory -Force)
}

$runAt = Get-Date
$stamp = $runAt.ToString('yyyyMMdd_HHmm')
$htmlPath = Join-Path $outputDirectory "BIST_Rapor_$stamp.html"
$csvPath = Join-Path $outputDirectory "BIST_Top_$stamp.csv"
$logPath = Join-Path $outputDirectory 'GunlukRapor.log'

try {
    $reportStartedAt = Get-Date
    $stageStartedAt = Get-Date
    $stocks = @(Invoke-BistStockScan)
    Write-TimingLog -Step 'Canli BIST taramasi' -StartedAt $stageStartedAt

    $stageStartedAt = Get-Date
    $scored = @(Get-BistScores -Stocks $stocks -Strategy $strategy | Sort-Object Score -Descending)
    Write-TimingLog -Step 'Skorlama' -StartedAt $stageStartedAt

    $stageStartedAt = Get-Date
    Save-JsonFile -Path (Join-Path $PSScriptRoot 'data\last_scan.json') -Value ([pscustomobject]@{
            UpdatedAt = $runAt.ToString('o')
            Count = $stocks.Count
            Stocks = $stocks
        }) -Depth 8
    Write-TimingLog -Step 'Son tarama state kaydi' -StartedAt $stageStartedAt

    $stageStartedAt = Get-Date
    $portfolioPath = Join-Path $PSScriptRoot 'data\model_portfolios.json'
    $portfolioSet = $null
    if (Test-Path $portfolioPath) {
        $portfolioSet = Get-Content -Path $portfolioPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $updatedPortfolioSet = Update-ModelPortfolioSet -PortfolioSet $portfolioSet -Stocks $stocks -AsOf $runAt -AllowRebalance
    if ($null -eq $updatedPortfolioSet) {
        $updatedPortfolioSet = New-ModelPortfolioSet -Stocks $stocks -AsOf $runAt
    }
    Save-JsonFile -Path $portfolioPath -Value $updatedPortfolioSet -Depth 8
    Write-TimingLog -Step 'Model portfoy degerleme' -StartedAt $stageStartedAt

    $stageStartedAt = Get-Date
    $macroSnapshot = Get-MacroSnapshot -AsOf $runAt -TimeoutSec $macroTimeoutSec
    Write-TimingLog -Step 'Makro gorunum' -StartedAt $stageStartedAt

    $stageStartedAt = Get-Date
    $entryOpportunities = @(Get-InstantEntryOpportunities `
            -Stocks $scored `
            -CandidateLimit $instantEntryCandidateLimit `
            -TimeoutSec $instantEntryTimeoutSec `
            -MaxElapsedSec $instantEntryMaxElapsedSec)
    Write-TimingLog -Step 'Anlik giris firsati' -StartedAt $stageStartedAt

    $topRows = @($scored | Select-Object -First $topCount | ForEach-Object {
            [pscustomobject][ordered]@{
                Skor = Format-ReportNumber -Value $_.Score -Format 'N1'
                Gorus = ConvertTo-PlainText $_.Signal
                Teyit = ConvertTo-PlainText $_.ConfirmationLabel
                'Teknik Teyit' = '{0}/{1}' -f (ConvertTo-PlainText $_.TechnicalPassCount), (ConvertTo-PlainText $_.TechnicalCheckCount)
                'Kademeli Giris Notu' = ConvertTo-PlainText $_.EntryNote
                'Eksik Teyitler' = ConvertTo-PlainText $_.FailedConfirmations
                Sembol = ConvertTo-PlainText $_.Symbol
                Sirket = ConvertTo-PlainText $_.Company
                Sektor = ConvertTo-PlainText $_.SectorTR
                Fiyat = Format-ReportNumber -Value $_.Price -Format 'N2'
                'Makro/Sektor' = Format-ReportNumber -Value $_.MacroSectorScore -Format 'N1'
                'BIST Alfa 1Y' = Format-ReportNumber -Value $_.StockVsBist1YPct -Format 'N1'
                'FAVOK USD Y/Y' = Format-ReportNumber -Value $_.EbitdaUsdYoYPct -Format 'N1' -Suffix '%'
                'FD/FAVOK' = Format-ReportNumber -Value $_.EvEbitda -Format 'N2'
                RSI = Format-ReportNumber -Value $_.RSI -Format 'N1'
                'MACD Hist' = Format-ReportNumber -Value $_.MacdHistogram -Format 'N2'
                'Haftalik RSI' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'RSIWeekly') -Format 'N1'
                'Haftalik MACD Hist' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'MacdHistogramWeekly') -Format 'N2'
                'Aylik RSI' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'RSIMonthly') -Format 'N1'
                'Aylik MACD Hist' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'MacdHistogramMonthly') -Format 'N2'
                'Hacim' = Format-ReportNumber -Value $_.RelativeVolume -Format 'N2' -Suffix 'x'
            }
        })

    $rankedForDetails = @($scored | Sort-Object @{ Expression = { Get-ConfirmationRank -Stock $_ }; Ascending = $true }, @{ Expression = { $_.Score }; Descending = $true })
    $detailedStocks = @($rankedForDetails | Select-Object -First $detailedCount)
    $detailedCardsHtml = if ($detailedStocks.Count -gt 0) {
        ($detailedStocks | ForEach-Object { Get-StockDetailedReasonHtml -Stock $_ }) -join [Environment]::NewLine
    }
    else {
        '<p class="muted">Detaylı hisse notu için veri yok.</p>'
    }

    $strongUsdRows = @($scored | Where-Object StrongUsdEarnings | Select-Object -First 10 | ForEach-Object {
            [pscustomobject][ordered]@{
                Sembol = ConvertTo-PlainText $_.Symbol
                Sirket = ConvertTo-PlainText $_.Company
                Skor = Format-ReportNumber -Value $_.Score -Format 'N1'
                'Net Kar USD Y/Y' = Format-ReportNumber -Value $_.NetIncomeUsdYoYPct -Format 'N1' -Suffix '%'
                'FAVOK USD Y/Y' = Format-ReportNumber -Value $_.EbitdaUsdYoYPct -Format 'N1' -Suffix '%'
                'Pozitif Kar Ceyrek' = ConvertTo-PlainText $_.PositiveQuarterCount
                'FAVOK Trendi' = ConvertTo-PlainText $_.EbitdaTrendLabel
            }
        })

    $confirmedRows = @($scored |
            Where-Object { $_.ConfirmationLabel -in @('Tüm Teyitli Güçlü Aday', 'Teknik Teyitli Güçlü İzle') } |
            Sort-Object @{ Expression = { Get-ConfirmationRank -Stock $_ }; Ascending = $true }, @{ Expression = { $_.Score }; Descending = $true } |
            Select-Object -First 15 |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    Teyit = ConvertTo-PlainText $_.ConfirmationLabel
                    Sembol = ConvertTo-PlainText $_.Symbol
                    Sirket = ConvertTo-PlainText $_.Company
                    Skor = Format-ReportNumber -Value $_.Score -Format 'N1'
                    'Teknik Teyit' = '{0}/{1}' -f (ConvertTo-PlainText $_.TechnicalPassCount), (ConvertTo-PlainText $_.TechnicalCheckCount)
                    'Makro/Sektor' = Format-ReportNumber -Value $_.MacroSectorScore -Format 'N1'
                    'Bilanço' = Format-ReportNumber -Value $_.EarningsScore -Format 'N1'
                    'Momentum' = Format-ReportNumber -Value $_.MomentumScore -Format 'N1'
                    'Eksik Teyit' = ConvertTo-PlainText $_.FailedConfirmations
                }
            })

    $macroRows = @($macroSnapshot.Metrics | ForEach-Object {
            [pscustomobject][ordered]@{
                Metrik = ConvertTo-PlainText $_.Name
                Deger = if ($null -ne $_.Value) {
                    Format-ReportNumber -Value $_.Value -Format $(if ($_.Id -eq 'USDTRY_Tcmb') { 'N4' } else { 'N2' }) -Suffix $(" $($_.Unit)")
                }
                else {
                    '-'
                }
                'Gunluk Degisim' = if ($null -ne $_.ChangePct) {
                    Format-ReportNumber -Value $_.ChangePct -Format 'N2' -Suffix '%'
                }
                elseif ($null -ne $_.Change) {
                    Format-ReportNumber -Value $_.Change -Format 'N2'
                }
                else {
                    '-'
                }
                Durum = ConvertTo-PlainText $_.Status
                Kaynak = ConvertTo-PlainText $_.Source
                Not = ConvertTo-PlainText $_.Note
            }
        })

    $entryOpportunityRows = @($entryOpportunities | ForEach-Object {
            [pscustomobject][ordered]@{
                Sira = ConvertTo-PlainText $_.Rank
                'Giris Skoru' = Format-ReportNumber -Value $_.EntryOpportunityScore -Format 'N1'
                Sembol = ConvertTo-PlainText $_.Symbol
                Sirket = ConvertTo-PlainText $_.Company
                Sektor = ConvertTo-PlainText $_.SectorTR
                Fiyat = Format-ReportNumber -Value $_.Price -Format 'N2' -Suffix ' TL'
                'Haftalik Hist Etiket' = ConvertTo-PlainText $_.WeeklyHistogramLabel
                'Ust Uste Artis' = ConvertTo-PlainText $_.WeeklyHistogramRisingWeeks
                '8 Haftada Artis' = '{0}/7' -f (ConvertTo-PlainText $_.WeeklyHistogramIncreaseCount)
                'Son Hist' = Format-ReportNumber -Value $_.LastWeeklyHistogram -Format 'N2'
                'Onceki Hist' = Format-ReportNumber -Value $_.PreviousWeeklyHistogram -Format 'N2'
                RSI = Format-ReportNumber -Value $_.RSI -Format 'N1'
                'Goreli Hacim' = Format-ReportNumber -Value $_.RelativeVolume -Format 'N2' -Suffix 'x'
                'FD/FAVOK' = Format-ReportNumber -Value $_.EvEbitda -Format 'N2'
                '52H Konum' = Format-ReportNumber -Value $_.Range52PositionPct -Format 'N1' -Suffix '%'
                '52H Bant' = ConvertTo-PlainText $_.Range52Bucket
                'BIST 4H' = $(if ($null -ne $_.MarketRegimeLabel) { '{0} ({1})' -f (ConvertTo-PlainText $_.MarketRegimeLabel), (Format-ReportNumber -Value $_.MarketRegimeChangePct -Format 'N1' -Suffix '%') } else { '-' })
                'Makro/Sektor' = Format-ReportNumber -Value $_.MacroSectorScore -Format 'N1'
                'Neden Simdi Izlenir' = ConvertTo-PlainText $_.Reason
            }
        })

    $sectorRows = @($scored |
            Group-Object SectorTR |
            ForEach-Object {
                $first = @($_.Group | Select-Object -First 1)[0]
                [pscustomobject][ordered]@{
                    Sektor = [string]$_.Name
                    'Hisse Sayisi' = $_.Count
                    Rotasyon = ConvertTo-PlainText $first.SectorRotationLabel
                    'Endeks/Proxy' = ConvertTo-PlainText $first.SectorWatchIndex
                    'Gun Fark' = Format-ReportNumber -Value $first.SectorVsBistDay -Format 'N1'
                    'Hafta Fark' = Format-ReportNumber -Value $first.SectorVsBistWeek -Format 'N1'
                    '1A Fark' = Format-ReportNumber -Value $first.SectorVsBistMonth -Format 'N1'
                    '3A Fark' = Format-ReportNumber -Value $first.SectorVsBist3Month -Format 'N1'
                    '1Y Fark' = Format-ReportNumber -Value $first.SectorVsBistYear -Format 'N1'
                    'Ortalama Fark' = Format-ReportNumber -Value $first.SectorRotationAverage -Format 'N1'
                    'Sektor Gun' = Format-ReportNumber -Value $first.SectorIndexChangePct -Format 'N1' -Suffix '%'
                    'Sektor Hafta' = Format-ReportNumber -Value $first.SectorIndexPerfWeek -Format 'N1' -Suffix '%'
                    'Sektor 1A' = Format-ReportNumber -Value $first.SectorIndexPerfMonth -Format 'N1' -Suffix '%'
                    'Sektor 3A' = Format-ReportNumber -Value $first.SectorIndexPerf3Month -Format 'N1' -Suffix '%'
                    'Sektor 1Y' = Format-ReportNumber -Value $first.SectorIndexPerfYear -Format 'N1' -Suffix '%'
                }
            } |
            Sort-Object { [double]($_.'Ortalama Fark' -replace ',', '.' -replace '-', '-999') } -Descending |
            Select-Object -First 12)

    $portfolioRows = @($updatedPortfolioSet.Portfolios | ForEach-Object {
            [pscustomobject][ordered]@{
                Portfoy = ConvertTo-PlainText $_.Name
                Deger = Format-ReportNumber -Value $_.CurrentValueTL -Format 'N2' -Suffix ' TL'
                'Getiri' = Format-ReportNumber -Value $_.TotalReturnPct -Format 'N2' -Suffix '%'
                Hisseler = ((@($_.Holdings) | ForEach-Object Symbol) -join ', ')
                'Baslangic' = ConvertTo-PlainText $_.StartDateText
                'Son Islem' = ConvertTo-PlainText $_.LastRebalanceDateText
                'Son Rebalance Donemi' = ConvertTo-PlainText $_.LastRebalancePeriodEnd
                'Sonraki' = ConvertTo-PlainText $_.NextRebalanceDate
                Durum = ConvertTo-PlainText $_.StatusNote
            }
        })
    $portfolioHoldingRows = Get-ModelPortfolioHoldingRows -PortfolioSet $updatedPortfolioSet
    $portfolioTransactionRows = Get-ModelPortfolioTransactionRows -PortfolioSet $updatedPortfolioSet -PerPortfolio 12

    $topRows | Export-Csv -Path $csvPath -NoTypeInformation -Delimiter ';' -Encoding UTF8

    $subjectPrefix = [string](Get-ConfigValue -Object $settings.Email -Name 'SubjectPrefix' -Default 'BIST Gunluk Rapor')
    $subject = '{0} - {1}' -f $subjectPrefix, $runAt.ToString('dd.MM.yyyy HH:mm')
    $leader = @($scored | Select-Object -First 1)[0]
    $telegramText = @(
        "BIST Gunluk Rapor - $($runAt.ToString('dd.MM.yyyy HH:mm'))",
        "Hisse sayisi: $($stocks.Count)",
        "Lider: $($leader.Symbol) | Skor $($leader.Score) | $($leader.Signal)",
        "Makro: $($macroSnapshot.Status)",
        "Anlik giris radari: " + $(if ($entryOpportunities.Count -gt 0) { (($entryOpportunities | ForEach-Object { "$($_.Symbol)($($_.EntryOpportunityScore))" }) -join ', ') } else { 'bugun uygun aday yok' }),
        "Model portfoyler: " + ((@($updatedPortfolioSet.Portfolios) | ForEach-Object { "$($_.Strategy): " + ((@($_.Holdings) | ForEach-Object Symbol) -join ',') }) -join ' | '),
        "HTML rapor: $htmlPath"
    ) -join [Environment]::NewLine

    $css = @'
<style>
body { font-family: Segoe UI, Arial, sans-serif; color: #0f172a; margin: 24px; }
h1 { margin-bottom: 4px; }
h2 { margin-top: 28px; border-bottom: 1px solid #e2e8f0; padding-bottom: 6px; }
.muted { color: #64748b; }
.card { display: inline-block; border: 1px solid #e2e8f0; border-radius: 8px; padding: 12px 16px; margin: 8px 8px 8px 0; background: #f8fafc; }
.detail-card { border: 1px solid #cbd5e1; border-radius: 10px; padding: 14px 16px; margin: 14px 0; background: #ffffff; box-shadow: 0 1px 2px rgba(15,23,42,0.05); }
.detail-card h3 { margin: 0 0 4px 0; color: #0f172a; }
.detail-card h4 { margin: 12px 0 4px 0; color: #1e293b; }
.detail-card ul { margin-top: 4px; padding-left: 20px; }
.detail-card li { margin: 4px 0; }
.badge { display: inline-block; padding: 4px 8px; border-radius: 999px; background: #dcfce7; color: #166534; font-weight: 700; font-size: 12px; }
table { border-collapse: collapse; width: 100%; margin-top: 10px; font-size: 12px; }
th { background: #0f172a; color: white; text-align: left; padding: 7px; }
td { border-bottom: 1px solid #e2e8f0; padding: 7px; vertical-align: top; }
tr:nth-child(even) td { background: #f8fafc; }
.warn { background: #fffbeb; border: 1px solid #fde68a; padding: 10px; border-radius: 8px; }
@media (max-width: 760px) {
body { margin: 12px; font-size: 14px; }
.card { display: block; }
table { display: block; overflow-x: auto; white-space: nowrap; }
}
</style>
'@
    $htmlBody = @"
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
$css
<title>$subject</title>
</head>
<body>
<h1>$subject</h1>
<p class="muted">Bu rapor otomatik sayisal taramadir; yatirim tavsiyesi degildir.</p>
<div class="card"><b>Hisse sayisi</b><br>$($stocks.Count)</div>
<div class="card"><b>Strateji</b><br>$strategy</div>
<div class="card"><b>Lider</b><br>$($leader.Symbol) - $($leader.Score)</div>
<div class="card"><b>Makro</b><br>$($macroSnapshot.Status)</div>
<div class="card"><b>Rapor dosyasi</b><br>$htmlPath</div>
<h2>Makro Görünüm</h2>
<p class="muted">$($macroSnapshot.MeasurementNote)</p>
$(New-HtmlTable -Rows $macroRows)
<h2>Anlık Giriş Fırsatı</h2>
<p class="muted">Bu bölüm, temeli geçen hisselerde skor 85+ ve backtestte fake oranını düşüren teknik koşulu arar: MACD yeni sıfır kesişimi veya pozitif ivme + 52H %20-50 bandı. Liste sayısı sabit değildir; bugün koşul yoksa boş gelebilir.</p>
$(New-HtmlTable -Rows $entryOpportunityRows)
<h2>Tüm Teyitli / Teknik Teyitli Adaylar</h2>
<p class="muted">Bu tablo, temel ve teknik bacakları birlikte güçlü olanları öne alır. Liste boş ise bugün tüm koşulları aynı anda sağlayan aday yok demektir; bu durumda kademeli giriş yerine teyit beklemek daha disiplinlidir.</p>
$(New-HtmlTable -Rows $confirmedRows)
<h2>Neden Güçlü İzlenir? Detaylı Hisse Notları</h2>
<p class="muted">Her kart Makro, Temel ve Teknik bacaklarini ayri okur. Teknik bolumde gunluk, haftalik ve aylik RSI/MACD degerleri ayrica yazilir.</p>
$detailedCardsHtml
<h2>Top $topCount Radar</h2>
$(New-HtmlTable -Rows $topRows)
<h2>USD Güçlü Bilanço</h2>
$(New-HtmlTable -Rows $strongUsdRows)
<h2>Sektor Rotasyonu</h2>
<p class="muted">Fark sütunları sektör endeksi/proxy getirisi eksi BIST100 getirisi olarak okunur. Pozitif değer sektörün BIST100'e göre daha güçlü aktığını gösterir.</p>
$(New-HtmlTable -Rows $sectorRows)
<h2>Model Portfoyler</h2>
<p class="muted">Portföyler her çalışmada sadece değerlenir; ay sonu son işlem günü 18:10 sonrası tamamlanmış dönem varsa yeniden sıralanır ve AL/SAT/EŞİTLEME işlemleri state dosyasına yazılır.</p>
$(New-HtmlTable -Rows $portfolioRows)
<h2>Model Portfoy Aktif Hisse Detaylari</h2>
<p class="muted">İlk alış fiyatı işlem geçmişindeki ilk AL kaydından, satış fiyatı varsa ilk SAT/EŞİTLEME SAT kaydından gelir. Rebalance getirisi son portföy ayarlamasından bu yana, ilk alıştan getiri ilk AL fiyatına göre hesaplanır.</p>
$(New-HtmlTable -Rows $portfolioHoldingRows)
<h2>Model Portfoy Son Islemler</h2>
<p class="muted">Her portföy için son 12 işlem gösterilir; ilk kurulum, AL, SAT ve ay sonu eşitleme kayıtları fiyat/adet/tutar/not alanlarıyla izlenir.</p>
$(New-HtmlTable -Rows $portfolioTransactionRows)
<div class="warn">
Makro karar ağacı: makro uygun -> sektör güçlü -> bilanço güçlü -> teknik teyit -> kademeli giriş.
CDS, TR10Y, DXY, VIX ve USD/TRY ücretsiz kaynaklardan izleme metriği olarak alınır; gecikmeli veya eksik olabilir. İşlem kararı öncesi TCMB, Borsa İstanbul/MKK/KAP ve lisanslı veri kaynaklarıyla doğrulayın.
</div>
</body>
</html>
"@

    $stageStartedAt = Get-Date
    [IO.File]::WriteAllText($htmlPath, $htmlBody, [Text.UTF8Encoding]::new($true))
    Write-TimingLog -Step 'HTML rapor yazimi' -StartedAt $stageStartedAt

    $sendMessages = [System.Collections.Generic.List[string]]::new()
    if (-not $NoSend) {
        if ([bool](Get-ConfigValue -Object $settings.Send -Name 'EmailEnabled' -Default $false)) {
            $stageStartedAt = Get-Date
            Send-EmailReport -Settings $settings -Subject $subject -HtmlBody $htmlBody -HtmlPath $htmlPath -CsvPath $csvPath
            Write-TimingLog -Step 'E-posta gonderimi' -StartedAt $stageStartedAt
            [void]$sendMessages.Add('E-posta gonderildi.')
        }

        if ([bool](Get-ConfigValue -Object $settings.Send -Name 'TelegramEnabled' -Default $false)) {
            $stageStartedAt = Get-Date
            Send-TelegramSummary -Settings $settings -Text $telegramText
            Write-TimingLog -Step 'Telegram gonderimi' -StartedAt $stageStartedAt
            [void]$sendMessages.Add('Telegram ozeti gonderildi.')
        }
    }

    Write-TimingLog -Step 'Toplam rapor suresi' -StartedAt $reportStartedAt
    $result = "OK $($runAt.ToString('s')) | Hisse=$($stocks.Count) | HTML=$htmlPath | CSV=$csvPath | $($sendMessages -join ' ')"
    Add-Content -Path $logPath -Value $result -Encoding UTF8
    Write-Host $result
}
catch {
    $message = "ERROR $((Get-Date).ToString('s')) | $($_.Exception.Message)"
    Add-Content -Path $logPath -Value $message -Encoding UTF8
    Write-Error $message
    exit 1
}
