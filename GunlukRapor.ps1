param(
    [string]$SettingsPath = (Join-Path $PSScriptRoot 'config\report_settings.json'),
    [switch]$NoSend
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'BistScanner.Core.psm1'
Import-Module $modulePath -Force

# Web panel köprüsü (ADDITIVE; yalnız docs/data/latest_report.json yazar). Yüklenemezse
# rapor/mail akışı ETKİLENMEZ — best-effort.
try { . (Join-Path $PSScriptRoot 'Export-Dashboard.ps1') }
catch { Write-Warning "Web panel köprüsü yüklenemedi (rapor etkilenmez): $($_.Exception.Message)" }

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

function Add-MidasLinks {
    <#
        Raporun nihai HTML'inde hisse kisaltmalarini Midas linkine cevirir
        (or. A1CAP -> https://app.getmidas.com/gmih/a1cap). Yalniz GECERLI hisse
        kumesindeki semboller baglanir (yanlis eslesme olmaz). Tablo hucreleri
        (<td>SEMBOL</td>) ve detay kart basliklari (<h3>SEMBOL - ...) hedeflenir.
        Tablolar ConvertTo-Html ile uretildiginden cell'e dogrudan <a> konamaz;
        bu yuzden son adimda post-process edilir.
    #>
    param([string]$Html, $Symbols)

    if ([string]::IsNullOrEmpty($Html) -or $null -eq $Symbols -or $Symbols.Count -eq 0) {
        return $Html
    }
    $base = 'https://app.getmidas.com/gmih/'
    $eval = {
        param($m)
        $sym = $m.Groups['sym'].Value
        if ($Symbols.Contains($sym)) {
            $href = $base + $sym.ToLowerInvariant()
            return "$($m.Groups['pre'].Value)<a class=`"sym`" target=`"_blank`" href=`"$href`">$sym</a>$($m.Groups['post'].Value)"
        }
        return $m.Value
    }
    # Tablo hucresi: <td>SEMBOL</td>
    $Html = [regex]::Replace($Html, '(?<pre><td>)(?<sym>[A-Z0-9]{2,6})(?<post></td>)', $eval)
    # Detay kart basligi: <h3>SEMBOL - Sirket</h3>
    $Html = [regex]::Replace($Html, '(?<pre><h3>)(?<sym>[A-Z0-9]{2,6})(?<post> - )', $eval)
    return $Html
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

function New-ModelPortfolioHoldingGroupsHtml {
    param(
        $PortfolioSet,
        [object[]]$HoldingRows
    )

    if ($null -eq $PortfolioSet -or $null -eq $HoldingRows -or $HoldingRows.Count -eq 0) {
        return '<p class="muted">Aktif hisse detayı için veri yok.</p>'
    }

    $blocks = @($PortfolioSet.Portfolios | ForEach-Object {
            $portfolio = $_
            $portfolioName = [string](Get-ObjectPropertyValue -Object $portfolio -Name 'Name')
            $strategy = [string](Get-ObjectPropertyValue -Object $portfolio -Name 'Strategy')
            $valueText = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $portfolio -Name 'CurrentValueTL') -Format 'N2' -Suffix ' TL'
            $returnText = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $portfolio -Name 'TotalReturnPct') -Format 'N2' -Suffix '%'
            $rows = @(
                $HoldingRows |
                    Where-Object { [string](Get-ObjectPropertyValue -Object $_ -Name 'Portfoy') -eq $portfolioName } |
                    Select-Object * -ExcludeProperty Portfoy
            )

            @"
<section class="portfolio-group">
<h3>$(ConvertTo-HtmlText $portfolioName)</h3>
<p class="muted">Strateji: $(ConvertTo-HtmlText $strategy) | Güncel değer: $(ConvertTo-HtmlText $valueText) | Toplam getiri: $(ConvertTo-HtmlText $returnText)</p>
$(New-HtmlTable -Rows $rows)
</section>
"@
        })

    return ($blocks -join [Environment]::NewLine)
}

function New-ModelPortfolioDistributionPieChartsHtml {
    param($PortfolioSet)

    if ($null -eq $PortfolioSet -or $null -eq $PortfolioSet.Portfolios) {
        return '<p class="muted">Portföy dağılım grafiği için veri yok.</p>'
    }

    $colors = @('#2563eb', '#16a34a', '#f97316', '#dc2626', '#7c3aed', '#0891b2', '#ca8a04', '#be185d')
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $cards = @($PortfolioSet.Portfolios | ForEach-Object {
            $portfolio = $_
            $portfolioName = [string](Get-ObjectPropertyValue -Object $portfolio -Name 'Name')
            $holdings = @(Get-ObjectPropertyValue -Object $portfolio -Name 'Holdings')
            if ($holdings.Count -eq 0) {
                return @"
<section class="pie-card">
<h3>$(ConvertTo-HtmlText $portfolioName)</h3>
<p class="muted">Dağılım için aktif hisse yok.</p>
</section>
"@
            }

            $weightValues = @($holdings | ForEach-Object {
                    $weight = Get-NumberValue -Object $_ -Name 'WeightPct'
                    if ($null -ne $weight -and $weight -gt 0) { [double]$weight } else { 0.0 }
                })
            $totalWeight = ($weightValues | Measure-Object -Sum).Sum
            if ($null -eq $totalWeight -or $totalWeight -le 0) {
                $totalWeight = [double]$holdings.Count
                $weightValues = @(1..$holdings.Count | ForEach-Object { 1.0 })
            }

            $barCells = [System.Collections.Generic.List[string]]::new()
            $legendItems = [System.Collections.Generic.List[string]]::new()
            for ($index = 0; $index -lt $holdings.Count; $index++) {
                $holding = $holdings[$index]
                $symbol = [string](Get-ObjectPropertyValue -Object $holding -Name 'Symbol')
                $weightPct = ([double]$weightValues[$index] / [double]$totalWeight) * 100.0
                $color = $colors[$index % $colors.Count]
                # E-posta uyumlu: conic-gradient yerine genislik%'li tablo hucreleri
                [void]$barCells.Add(('<td style="width:{0}%;background:{1};font-size:1px;line-height:20px;">&nbsp;</td>' -f $weightPct.ToString('0.##', $culture), $color))
                [void]$legendItems.Add(('<div class="pie-legend-item"><span class="swatch" style="background:{0}"></span><span>{1}</span><b>{2}</b></div>' -f $color, (ConvertTo-HtmlText $symbol), (Format-ReportNumber -Value $weightPct -Format 'N1' -Suffix '%')))
            }

            $barHtml = $barCells -join ''
            $legendHtml = $legendItems -join [Environment]::NewLine
            @"
<section class="pie-card">
<h3>$(ConvertTo-HtmlText $portfolioName)</h3>
<table role="presentation" cellpadding="0" cellspacing="0" class="distbar"><tr>$barHtml</tr></table>
<div class="pie-legend">$legendHtml</div>
</section>
"@
        })

    return '<div class="pie-grid">' + (($cards) -join [Environment]::NewLine) + '</div>'
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

function Get-ReportRiskRules {
    param($Settings)

    $rules = Get-ConfigValue -Object $Settings.Report -Name 'RiskRules' -Default $null
    [pscustomobject][ordered]@{
        StopLossPct = [double](Get-ConfigValue -Object $rules -Name 'StopLossPct' -Default -8)
        ReduceLossPct = [double](Get-ConfigValue -Object $rules -Name 'ReduceLossPct' -Default -5)
        TakeProfitPct = [double](Get-ConfigValue -Object $rules -Name 'TakeProfitPct' -Default 18)
        TrailingStopPct = [double](Get-ConfigValue -Object $rules -Name 'TrailingStopPct' -Default 7)
        MinScoreForHold = [double](Get-ConfigValue -Object $rules -Name 'MinScoreForHold' -Default 55)
    }
}

function Get-PositionRiskDecision {
    param(
        $Holding,
        $Stock,
        $Rules
    )

    $currentPrice = Get-NumberValue -Object $Holding -Name 'CurrentPrice'
    $rebalancePrice = Get-NumberValue -Object $Holding -Name 'RebalancePrice'
    if ($null -eq $rebalancePrice -or $rebalancePrice -le 0) {
        $rebalancePrice = Get-NumberValue -Object $Holding -Name 'AverageBuyPrice'
    }
    $gainPct = Get-NumberValue -Object $Holding -Name 'GainSinceRebalancePct'
    if ($null -eq $gainPct) { $gainPct = Get-NumberValue -Object $Holding -Name 'UnrealizedGainPct' }
    if ($null -eq $gainPct) { $gainPct = 0.0 }

    $priceIsFresh = [bool](Get-ObjectPropertyValue -Object $Holding -Name 'PriceIsFresh')
    $score = Get-NumberValue -Object $Stock -Name 'Score'
    $riskLevel = [string](Get-ObjectPropertyValue -Object $Stock -Name 'RiskLevel')
    $stopPrice = if ($null -ne $rebalancePrice -and $rebalancePrice -gt 0) {
        [double]$rebalancePrice * (1.0 + ([double]$Rules.StopLossPct / 100.0))
    }
    else { $null }

    if ($null -ne $currentPrice -and $currentPrice -gt 0 -and $gainPct -ge [double]$Rules.TakeProfitPct) {
        $trail = [double]$currentPrice * (1.0 - ([double]$Rules.TrailingStopPct / 100.0))
        if ($null -eq $stopPrice -or $trail -gt $stopPrice) { $stopPrice = $trail }
    }

    $decision = 'Tut'
    $reason = 'Risk eşiği tetiklenmedi.'
    if (-not $priceIsFresh) {
        $decision = 'Bekle'
        $reason = 'Canlı fiyat taze değil; risk kararı için veri doğrulaması beklenmeli.'
    }
    elseif ($riskLevel -eq 'Yüksek') {
        $decision = 'Azalt / Çıkış Adayı'
        $reason = 'Hisse yüksek risk bayrağı taşıyor.'
    }
    elseif ([double]$gainPct -le [double]$Rules.StopLossPct) {
        $decision = 'Stop Adayı'
        $reason = 'Zarar stop eşiğini aştı.'
    }
    elseif ([double]$gainPct -le [double]$Rules.ReduceLossPct) {
        $decision = 'Azalt'
        $reason = 'Zarar azaltma eşiğine geldi.'
    }
    elseif ($null -ne $score -and [double]$score -lt [double]$Rules.MinScoreForHold) {
        $decision = 'Teyit Zayıf'
        $reason = 'Güncel skor elde tutma eşiğinin altına indi.'
    }
    elseif ([double]$gainPct -ge [double]$Rules.TakeProfitPct) {
        $decision = 'Kar Al / Stop Yükselt'
        $reason = 'Kar alma eşiği aşıldı; iz süren stop yukarı çekilmeli.'
    }

    [pscustomobject][ordered]@{
        Decision = $decision
        StopPrice = if ($null -ne $stopPrice) { [Math]::Round([double]$stopPrice, 4) } else { $null }
        Reason = $reason
    }
}

function Get-ModelPortfolioHoldingRows {
    param(
        $PortfolioSet,
        [hashtable]$StockMap = @{},
        $RiskRules = $null
    )

    return @($PortfolioSet.Portfolios | ForEach-Object {
            $portfolio = $_
            @(Get-ObjectPropertyValue -Object $portfolio -Name 'Holdings') | ForEach-Object {
                $holding = $_
                $symbol = [string](Get-ObjectPropertyValue -Object $holding -Name 'Symbol')
                $firstBuy = Get-PortfolioSymbolTransaction -Portfolio $portfolio -Symbol $symbol -Side Buy
                $firstSell = Get-PortfolioSymbolTransaction -Portfolio $portfolio -Symbol $symbol -Side Sell
                $lastTransaction = Get-PortfolioSymbolTransaction -Portfolio $portfolio -Symbol $symbol -Side Any -Last
                $currentPrice = Get-NumberValue -Object $holding -Name 'CurrentPrice'
                $stock = if ($null -ne $StockMap -and $StockMap.ContainsKey($symbol)) { $StockMap[$symbol] } else { $null }
                $riskDecision = if ($null -ne $RiskRules) { Get-PositionRiskDecision -Holding $holding -Stock $stock -Rules $RiskRules } else { $null }

                [pscustomobject][ordered]@{
                    Portfoy = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $portfolio -Name 'Name')
                    Sembol = ConvertTo-PlainText $symbol
                    Sirket = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $holding -Name 'Company')
                    Adet = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $holding -Name 'Quantity') -Format 'N2'
                    'Ilk Fiyat' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $firstBuy -Name 'Price') -Format 'N2'
                    'Guncel' = Format-ReportNumber -Value $currentPrice -Format 'N2'
                    'Maliyet TL' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $holding -Name 'CostBasisTL') -Format 'N0'
                    'Deger TL' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $holding -Name 'CurrentValueTL') -Format 'N0'
                    'Agirlik' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $holding -Name 'WeightPct') -Format 'N1' -Suffix '%'
                    'Rebalans %' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $holding -Name 'GainSinceRebalancePct') -Format 'N1'
                    'Getiri %' = Format-ReportNumber -Value (Get-TransactionPriceReturnPct -ReferenceTransaction $firstBuy -CurrentPrice $currentPrice) -Format 'N1'
                    'Risk Karari' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $riskDecision -Name 'Decision')
                    'Stop Seviye' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $riskDecision -Name 'StopPrice') -Format 'N2'
                    'Risk Notu' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $riskDecision -Name 'Reason')
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

function Test-InstantEntryPortfolioBuyCandidate {
    param(
        $Opportunity,
        [double]$MinScore = 90
    )

    if ($null -eq $Opportunity) { return $false }

    $score = Get-NumberValue -Object $Opportunity -Name 'EntryOpportunityScore'
    $price = Get-NumberValue -Object $Opportunity -Name 'Price'
    if ($null -eq $score -or $score -lt $MinScore) { return $false }
    if ($null -eq $price -or $price -le 0) { return $false }

    $rangeBucket = [string](Get-ObjectPropertyValue -Object $Opportunity -Name 'Range52Bucket')
    if ($rangeBucket -eq '52H Range 0-10') { return $false }

    $rsi = Get-NumberValue -Object $Opportunity -Name 'RSI'
    if ($null -ne $rsi -and ($rsi -lt 40 -or $rsi -gt 67)) { return $false }

    $relativeVolume = Get-NumberValue -Object $Opportunity -Name 'RelativeVolume'
    if ($null -ne $relativeVolume -and $relativeVolume -lt 0.75) { return $false }

    $label = [string](Get-ObjectPropertyValue -Object $Opportunity -Name 'WeeklyHistogramLabel')
    $zeroCross = [bool](Get-ObjectPropertyValue -Object $Opportunity -Name 'WeeklyHistogramZeroCross')
    $recentZeroCross = [bool](Get-ObjectPropertyValue -Object $Opportunity -Name 'WeeklyHistogramRecentZeroCross')
    $strongLabels = @(
        'Sıfır üstüne yeni dönüş',
        'Sifir ustune yeni donus',
        'Pozitif ivme'
    )

    return [bool]($zeroCross -or $recentZeroCross -or $label -in $strongLabels)
}

function New-InstantEntryPortfolioTransaction {
    param(
        [int]$Sequence,
        [datetime]$ExecutionDate,
        [string]$Action,
        [string]$Symbol,
        [string]$Company,
        $Price,
        $Quantity,
        $AmountTL,
        $SignalScore,
        [string]$SignalLabel,
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
        SignalScore = if ($null -ne $SignalScore) { [Math]::Round([double]$SignalScore, 1) } else { $null }
        SignalLabel = $SignalLabel
        Note = $Note
    }
}

function Get-StockLookup {
    param([object[]]$Stocks)

    $stockMap = @{}
    foreach ($stock in @($Stocks)) {
        $symbol = [string](Get-ObjectPropertyValue -Object $stock -Name 'Symbol')
        if (-not [string]::IsNullOrWhiteSpace($symbol)) {
            $stockMap[$symbol] = $stock
        }
    }

    return $stockMap
}

function Update-InstantEntryPortfolioValuation {
    param(
        $Portfolio,
        [object[]]$Stocks,
        [datetime]$AsOf
    )

    $stockMap = Get-StockLookup -Stocks $Stocks
    $holdings = [System.Collections.Generic.List[object]]::new()
    $totalInvested = 0.0
    $totalValue = 0.0

    foreach ($holding in @(Get-ObjectPropertyValue -Object $Portfolio -Name 'Holdings')) {
        $symbol = [string](Get-ObjectPropertyValue -Object $holding -Name 'Symbol')
        if ([string]::IsNullOrWhiteSpace($symbol)) { continue }

        $stock = if ($stockMap.ContainsKey($symbol)) { $stockMap[$symbol] } else { $null }
        $freshPrice = Get-NumberValue -Object $stock -Name 'Price'
        $priceIsFresh = $null -ne $freshPrice -and $freshPrice -gt 0
        $currentPrice = if ($priceIsFresh) {
            [double]$freshPrice
        }
        else {
            $storedPrice = Get-NumberValue -Object $holding -Name 'CurrentPrice'
            if ($null -ne $storedPrice -and $storedPrice -gt 0) { [double]$storedPrice } else { 0.0 }
        }

        $quantity = Get-NumberValue -Object $holding -Name 'Quantity'
        $costBasis = Get-NumberValue -Object $holding -Name 'CostBasisTL'
        if ($null -eq $quantity) { $quantity = 0.0 }
        if ($null -eq $costBasis) { $costBasis = 0.0 }

        $currentValue = [double]$quantity * [double]$currentPrice
        $gain = $currentValue - [double]$costBasis
        $gainPct = if ([double]$costBasis -gt 0) { ($gain / [double]$costBasis) * 100.0 } else { 0.0 }
        $averageBuyPrice = if ([double]$quantity -gt 0) { [double]$costBasis / [double]$quantity } else { $null }
        $totalInvested += [double]$costBasis
        $totalValue += $currentValue

        # Iz-suren stop icin tepe fiyat (high-water mark): gozlenen en yuksek fiyat.
        $storedPeak = Get-NumberValue -Object $holding -Name 'PeakPrice'
        $peakPrice = [double]$currentPrice
        if ($null -ne $averageBuyPrice -and [double]$averageBuyPrice -gt $peakPrice) { $peakPrice = [double]$averageBuyPrice }
        if ($null -ne $storedPeak -and [double]$storedPeak -gt $peakPrice) { $peakPrice = [double]$storedPeak }
        $peakGainPct = if ($null -ne $averageBuyPrice -and [double]$averageBuyPrice -gt 0) {
            (($peakPrice - [double]$averageBuyPrice) / [double]$averageBuyPrice) * 100.0
        }
        else { 0.0 }

        [void]$holdings.Add([pscustomobject][ordered]@{
                Symbol = $symbol
                Company = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $holding -Name 'Company')
                SectorTR = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $holding -Name 'SectorTR')
                Quantity = [Math]::Round([double]$quantity, 6)
                CostBasisTL = [Math]::Round([double]$costBasis, 2)
                AverageBuyPrice = if ($null -ne $averageBuyPrice) { [Math]::Round([double]$averageBuyPrice, 4) } else { $null }
                CurrentPrice = [Math]::Round([double]$currentPrice, 4)
                CurrentValueTL = [Math]::Round($currentValue, 2)
                WeightPct = 0.0
                UnrealizedGainTL = [Math]::Round($gain, 2)
                UnrealizedGainPct = [Math]::Round($gainPct, 2)
                PeakPrice = [Math]::Round([double]$peakPrice, 4)
                PeakGainPct = [Math]::Round([double]$peakGainPct, 2)
                FirstBuyAt = Get-ObjectPropertyValue -Object $holding -Name 'FirstBuyAt'
                FirstBuyAtText = Get-ObjectPropertyValue -Object $holding -Name 'FirstBuyAtText'
                LastBuyAt = Get-ObjectPropertyValue -Object $holding -Name 'LastBuyAt'
                LastBuyAtText = Get-ObjectPropertyValue -Object $holding -Name 'LastBuyAtText'
                BuyCount = Get-ObjectPropertyValue -Object $holding -Name 'BuyCount'
                LastSignalScore = Get-ObjectPropertyValue -Object $holding -Name 'LastSignalScore'
                LastSignalLabel = Get-ObjectPropertyValue -Object $holding -Name 'LastSignalLabel'
                LastReason = Get-ObjectPropertyValue -Object $holding -Name 'LastReason'
                PriceIsFresh = $priceIsFresh
            })
    }

    foreach ($holding in $holdings) {
        $holding.WeightPct = if ($totalValue -gt 0) {
            [Math]::Round(([double]$holding.CurrentValueTL / $totalValue) * 100.0, 2)
        }
        else {
            0.0
        }
    }

    $createdAt = Get-ObjectPropertyValue -Object $Portfolio -Name 'CreatedAt'
    if ($null -eq $createdAt -or [string]::IsNullOrWhiteSpace([string]$createdAt)) {
        $createdAt = $AsOf.ToString('o')
    }
    $dailyBudget = Get-NumberValue -Object $Portfolio -Name 'DailyBudgetTL'
    $minScore = Get-NumberValue -Object $Portfolio -Name 'MinBuyScore'
    $maxBuys = Get-ObjectPropertyValue -Object $Portfolio -Name 'MaxBuysPerDay'
    $lastBuyDate = Get-ObjectPropertyValue -Object $Portfolio -Name 'LastBuyDate'
    $lastBuyDateText = Get-ObjectPropertyValue -Object $Portfolio -Name 'LastBuyDateText'
    $transactions = @(Get-ObjectPropertyValue -Object $Portfolio -Name 'Transactions')
    $gain = $totalValue - $totalInvested
    $returnPct = if ($totalInvested -gt 0) { ($gain / $totalInvested) * 100.0 } else { 0.0 }
    # Gerceklesen (kapatilmis pozisyon) K/Z kumulatif tasinir (stop/kar-al cikislari).
    $realizedGain = Get-NumberValue -Object $Portfolio -Name 'RealizedGainTL'
    $realizedCost = Get-NumberValue -Object $Portfolio -Name 'RealizedCostTL'
    if ($null -eq $realizedGain) { $realizedGain = 0.0 }
    if ($null -eq $realizedCost) { $realizedCost = 0.0 }

    return [pscustomobject][ordered]@{
        Version = 1
        CreatedAt = $createdAt
        UpdatedAt = $AsOf.ToString('o')
        LastValuationAt = $AsOf.ToString('o')
        LastValuationAtText = $AsOf.ToString('dd.MM.yyyy HH:mm')
        DailyBudgetTL = if ($null -ne $dailyBudget) { [Math]::Round([double]$dailyBudget, 2) } else { 5000.0 }
        MinBuyScore = if ($null -ne $minScore) { [Math]::Round([double]$minScore, 1) } else { 90.0 }
        MaxBuysPerDay = if ($null -ne $maxBuys -and -not [string]::IsNullOrWhiteSpace([string]$maxBuys)) { [int]$maxBuys } else { 3 }
        TotalInvestedTL = [Math]::Round($totalInvested, 2)
        CurrentValueTL = [Math]::Round($totalValue, 2)
        TotalGainTL = [Math]::Round($gain, 2)
        TotalReturnPct = [Math]::Round($returnPct, 2)
        RealizedGainTL = [Math]::Round([double]$realizedGain, 2)
        RealizedCostTL = [Math]::Round([double]$realizedCost, 2)
        LastBuyDate = $lastBuyDate
        LastBuyDateText = $lastBuyDateText
        StatusNote = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $Portfolio -Name 'StatusNote')
        Notes = 'Anlık giriş fırsatı portföyü teorik modeldir. Her gün 18:15 kapanış taramasında yalnızca çok güçlü sinyal varsa günlük bütçe ile alım kaydı oluşturur; gerçek emir göndermez.'
        Holdings = @($holdings | Sort-Object CurrentValueTL -Descending)
        Transactions = $transactions
    }
}

function Update-InstantEntrySignalPortfolio {
    param(
        $Portfolio,
        [object[]]$Opportunities,
        [object[]]$Stocks,
        [datetime]$AsOf,
        [double]$DailyBudgetTL = 5000,
        [double]$InitialCapitalTL = 100000,
        [double]$MinBuyScore = 90,
        [int]$MaxBuysPerDay = 3,
        $RiskRules = $null
    )

    if ($null -eq $Portfolio -or $null -eq (Get-ObjectPropertyValue -Object $Portfolio -Name 'Holdings')) {
        $Portfolio = [pscustomobject][ordered]@{
            Version = 1
            CreatedAt = $AsOf.ToString('o')
            UpdatedAt = $AsOf.ToString('o')
            DailyBudgetTL = [Math]::Round($DailyBudgetTL, 2)
            MinBuyScore = [Math]::Round($MinBuyScore, 1)
            MaxBuysPerDay = $MaxBuysPerDay
            TotalInvestedTL = 0.0
            CurrentValueTL = 0.0
            TotalGainTL = 0.0
            TotalReturnPct = 0.0
            LastBuyDate = $null
            LastBuyDateText = $null
            StatusNote = 'Portföy yeni oluşturuldu.'
            Holdings = @()
            Transactions = @()
        }
    }

    $Portfolio.DailyBudgetTL = [Math]::Round($DailyBudgetTL, 2)
    $Portfolio.MinBuyScore = [Math]::Round($MinBuyScore, 1)
    $Portfolio.MaxBuysPerDay = $MaxBuysPerDay
    $valuedPortfolio = Update-InstantEntryPortfolioValuation -Portfolio $Portfolio -Stocks $Stocks -AsOf $AsOf

    $transactions = [System.Collections.Generic.List[object]]::new()
    foreach ($transaction in @(Get-ObjectPropertyValue -Object $valuedPortfolio -Name 'Transactions')) {
        [void]$transactions.Add($transaction)
    }

    $holdingsBySymbol = @{}
    foreach ($holding in @(Get-ObjectPropertyValue -Object $valuedPortfolio -Name 'Holdings')) {
        $symbol = [string](Get-ObjectPropertyValue -Object $holding -Name 'Symbol')
        if (-not [string]::IsNullOrWhiteSpace($symbol)) {
            $holdingsBySymbol[$symbol] = $holding
        }
    }

    # --- Risk cikislari (YALNIZ bu portfoy): stop-loss / kar-al / iz-suren stop ---
    # Model portfoyler aylik kalir; anlik firsat portfoyu gunluk kapanista risk
    # kurallariyla pozisyon kapatir (teorik; gercek emir gonderilmez). Kapatilan
    # pozisyonun K/Z'si RealizedGainTL'de kumulatif birikir (survivorship olmasin).
    $realizedGain = Get-NumberValue -Object $valuedPortfolio -Name 'RealizedGainTL'
    $realizedCost = Get-NumberValue -Object $valuedPortfolio -Name 'RealizedCostTL'
    if ($null -eq $realizedGain) { $realizedGain = 0.0 }
    if ($null -eq $realizedCost) { $realizedCost = 0.0 }
    $soldSymbols = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $RiskRules) {
        $sellSequence = $transactions.Count + 1
        foreach ($symbol in @($holdingsBySymbol.Keys)) {
            $holding = $holdingsBySymbol[$symbol]
            # Bayat fiyatla (canli fiyat yok) cikis kararini verme.
            if (-not (Get-ObjectPropertyValue -Object $holding -Name 'PriceIsFresh')) { continue }
            $exit = Get-InstantEntryExitDecision -Holding $holding -Rules $RiskRules
            if ($null -eq $exit) { continue }

            $sellQuantity = Get-NumberValue -Object $holding -Name 'Quantity'
            $sellPrice = Get-NumberValue -Object $holding -Name 'CurrentPrice'
            $sellValue = Get-NumberValue -Object $holding -Name 'CurrentValueTL'
            $sellCost = Get-NumberValue -Object $holding -Name 'CostBasisTL'
            $sellGain = Get-NumberValue -Object $holding -Name 'UnrealizedGainTL'
            if ($null -eq $sellGain) { $sellGain = 0.0 }
            if ($null -eq $sellCost) { $sellCost = 0.0 }
            $realizedGain = [double]$realizedGain + [double]$sellGain
            $realizedCost = [double]$realizedCost + [double]$sellCost

            [void]$transactions.Add((New-InstantEntryPortfolioTransaction `
                        -Sequence $sellSequence `
                        -ExecutionDate $AsOf `
                        -Action 'SAT' `
                        -Symbol $symbol `
                        -Company (ConvertTo-PlainText (Get-ObjectPropertyValue -Object $holding -Name 'Company')) `
                        -Price $sellPrice `
                        -Quantity $sellQuantity `
                        -AmountTL $sellValue `
                        -SignalScore $null `
                        -SignalLabel $exit.Kind `
                        -Note ('{0} Gerçekleşen K/Z {1:N2} TL.' -f $exit.Reason, [double]$sellGain)))
            $sellSequence++
            [void]$soldSymbols.Add(('{0} ({1})' -f $symbol, $exit.Kind))
            [void]$holdingsBySymbol.Remove($symbol)
        }
    }

    # --- KAPALI DONGU NAKIT (100k sermaye, 5k/gun) ---
    # Bu noktada $transactions bugunku SATIS'lari icerir (yukarida eklendi) ama bugunku
    # ALIM'lari henuz icermez. Nakit = sermaye - kumulatif alim + kumulatif satis hasilati;
    # satis hasilati (KAR dahil) nakte donerek tekrar girise musait olur ("kazandigi karla
    # da girsin"). Gunluk alim hakki hem 5k hem KALAN NAKIT ile sinirli (100k asilmaz).
    $cashState = Get-InstantEntryCashTL -InitialCapitalTL $InitialCapitalTL -Transactions $transactions.ToArray()
    $cashAvailable = [double]$cashState.CashTL
    $todayBudget = [Math]::Round([Math]::Min([double]$DailyBudgetTL, [Math]::Max(0.0, $cashAvailable)), 2)

    $todayKey = $AsOf.ToString('yyyy-MM-dd')
    $alreadyBoughtToday = @(
        $transactions | Where-Object {
            $action = [string](Get-ObjectPropertyValue -Object $_ -Name 'Action')
            if ($action -ne 'AL') {
                $false
            }
            else {
                $dateValue = Get-ObjectPropertyValue -Object $_ -Name 'ExecutionDate'
                try { ([datetime]$dateValue).ToString('yyyy-MM-dd') -eq $todayKey } catch { $false }
            }
        }
    ).Count -gt 0

    $statusNote = ''
    if ($alreadyBoughtToday) {
        $statusNote = ('Bugün bu portföy için daha önce alım kaydı oluştu; tekrar {0:N0} TL günlük hak kullanılmadı.' -f $DailyBudgetTL)
    }
    else {
        $maxBuys = [Math]::Max(1, [Math]::Min(3, $MaxBuysPerDay))
        $buyCandidates = @(
            @($Opportunities) |
                Where-Object { Test-InstantEntryPortfolioBuyCandidate -Opportunity $_ -MinScore $MinBuyScore } |
                Sort-Object @{ Expression = { Get-NumberValue -Object $_ -Name 'EntryOpportunityScore' }; Descending = $true } |
                Select-Object -First $maxBuys
        )

        if ($todayBudget -le 0) {
            $statusNote = ('Kullanılabilir nakit yok ({0:N0} TL); 100.000 TL sermaye tamamen pozisyonlarda. Bir satış nakit serbest bırakınca tekrar giriş yapılır.' -f $cashAvailable)
        }
        elseif ($buyCandidates.Count -eq 0) {
            $statusNote = ('Bugün çok güçlü anlık giriş sinyali yok; {0:N0} TL günlük alım hakkı kullanılmadı.' -f $todayBudget)
        }
        else {
            $sequence = $transactions.Count + 1
            $remainingBudget = [Math]::Round($todayBudget, 2)
            $boughtSymbols = [System.Collections.Generic.List[string]]::new()

            for ($index = 0; $index -lt $buyCandidates.Count; $index++) {
                $candidate = $buyCandidates[$index]
                $symbol = [string](Get-ObjectPropertyValue -Object $candidate -Name 'Symbol')
                $company = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $candidate -Name 'Company')
                $sector = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $candidate -Name 'SectorTR')
                $price = Get-NumberValue -Object $candidate -Name 'Price'
                if ([string]::IsNullOrWhiteSpace($symbol) -or $null -eq $price -or $price -le 0) {
                    continue
                }

                $amount = if ($index -eq ($buyCandidates.Count - 1)) {
                    $remainingBudget
                }
                else {
                    [Math]::Round($todayBudget / $buyCandidates.Count, 2)
                }
                $remainingBudget = [Math]::Round($remainingBudget - $amount, 2)
                if ($amount -le 0) { continue }

                $quantity = [double]$amount / [double]$price
                $existing = if ($holdingsBySymbol.ContainsKey($symbol)) { $holdingsBySymbol[$symbol] } else { $null }
                $oldQuantity = Get-NumberValue -Object $existing -Name 'Quantity'
                $oldCost = Get-NumberValue -Object $existing -Name 'CostBasisTL'
                $oldBuyCount = Get-ObjectPropertyValue -Object $existing -Name 'BuyCount'
                if ($null -eq $oldQuantity) { $oldQuantity = 0.0 }
                if ($null -eq $oldCost) { $oldCost = 0.0 }
                if ($null -eq $oldBuyCount -or [string]::IsNullOrWhiteSpace([string]$oldBuyCount)) { $oldBuyCount = 0 }

                $newQuantity = [double]$oldQuantity + $quantity
                $newCost = [double]$oldCost + [double]$amount
                $currentValue = $newQuantity * [double]$price
                $gain = $currentValue - $newCost
                $gainPct = if ($newCost -gt 0) { ($gain / $newCost) * 100.0 } else { 0.0 }
                $averageBuyPrice = if ($newQuantity -gt 0) { $newCost / $newQuantity } else { $null }
                $firstBuyAt = Get-ObjectPropertyValue -Object $existing -Name 'FirstBuyAt'
                $firstBuyAtText = Get-ObjectPropertyValue -Object $existing -Name 'FirstBuyAtText'
                if ($null -eq $firstBuyAt -or [string]::IsNullOrWhiteSpace([string]$firstBuyAt)) {
                    $firstBuyAt = $AsOf.ToString('o')
                    $firstBuyAtText = $AsOf.ToString('dd.MM.yyyy HH:mm')
                }

                $score = Get-NumberValue -Object $candidate -Name 'EntryOpportunityScore'
                $label = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $candidate -Name 'WeeklyHistogramLabel')
                $reason = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $candidate -Name 'Reason')
                # Tepe fiyati (iz-suren stop icin) koru: eski tepe / yeni fiyat / ort. maliyet en yuksegi.
                $oldPeak = Get-NumberValue -Object $existing -Name 'PeakPrice'
                $peakPrice = [double]$price
                if ($null -ne $oldPeak -and [double]$oldPeak -gt $peakPrice) { $peakPrice = [double]$oldPeak }
                if ($null -ne $averageBuyPrice -and [double]$averageBuyPrice -gt $peakPrice) { $peakPrice = [double]$averageBuyPrice }
                $peakGainPct = if ($null -ne $averageBuyPrice -and [double]$averageBuyPrice -gt 0) {
                    (($peakPrice - [double]$averageBuyPrice) / [double]$averageBuyPrice) * 100.0
                }
                else { 0.0 }
                $holdingsBySymbol[$symbol] = [pscustomobject][ordered]@{
                    Symbol = $symbol
                    Company = $company
                    SectorTR = $sector
                    Quantity = [Math]::Round($newQuantity, 6)
                    CostBasisTL = [Math]::Round($newCost, 2)
                    AverageBuyPrice = if ($null -ne $averageBuyPrice) { [Math]::Round($averageBuyPrice, 4) } else { $null }
                    CurrentPrice = [Math]::Round([double]$price, 4)
                    CurrentValueTL = [Math]::Round($currentValue, 2)
                    WeightPct = 0.0
                    UnrealizedGainTL = [Math]::Round($gain, 2)
                    UnrealizedGainPct = [Math]::Round($gainPct, 2)
                    PeakPrice = [Math]::Round([double]$peakPrice, 4)
                    PeakGainPct = [Math]::Round([double]$peakGainPct, 2)
                    FirstBuyAt = $firstBuyAt
                    FirstBuyAtText = $firstBuyAtText
                    LastBuyAt = $AsOf.ToString('o')
                    LastBuyAtText = $AsOf.ToString('dd.MM.yyyy HH:mm')
                    BuyCount = ([int]$oldBuyCount + 1)
                    LastSignalScore = if ($null -ne $score) { [Math]::Round([double]$score, 1) } else { $null }
                    LastSignalLabel = $label
                    LastReason = $reason
                    PriceIsFresh = $true
                }

                [void]$transactions.Add((New-InstantEntryPortfolioTransaction `
                            -Sequence $sequence `
                            -ExecutionDate $AsOf `
                            -Action 'AL' `
                            -Symbol $symbol `
                            -Company $company `
                            -Price $price `
                            -Quantity $quantity `
                            -AmountTL $amount `
                            -SignalScore $score `
                            -SignalLabel $label `
                            -Note ('Günlük anlık fırsat bütçesiyle alındı. {0}' -f $reason)))
                $sequence++
                [void]$boughtSymbols.Add(('{0} {1:N0} TL' -f $symbol, $amount))
            }

            if ($boughtSymbols.Count -gt 0) {
                $statusNote = 'Bugünkü alım: ' + ($boughtSymbols -join ', ') + '.'
                $valuedPortfolio.LastBuyDate = $todayKey
                $valuedPortfolio.LastBuyDateText = $AsOf.ToString('dd.MM.yyyy HH:mm')
            }
            else {
                $statusNote = ('Aday bulundu ama fiyat/sembol eksikliği nedeniyle {0:N0} TL günlük alım hakkı kullanılmadı.' -f $todayBudget)
            }
        }
    }

    $finalHoldings = [System.Collections.Generic.List[object]]::new()
    $totalInvested = 0.0
    $totalValue = 0.0
    foreach ($holding in @($holdingsBySymbol.Values | Sort-Object CurrentValueTL -Descending)) {
        $totalInvested += [double](Get-NumberValue -Object $holding -Name 'CostBasisTL')
        $totalValue += [double](Get-NumberValue -Object $holding -Name 'CurrentValueTL')
        [void]$finalHoldings.Add($holding)
    }

    foreach ($holding in $finalHoldings) {
        $holding.WeightPct = if ($totalValue -gt 0) {
            [Math]::Round(([double]$holding.CurrentValueTL / $totalValue) * 100.0, 2)
        }
        else {
            0.0
        }
    }

    # $totalInvested = acik pozisyonlarin maliyeti; $totalValue = acik pozisyonlarin guncel degeri.
    $unrealizedGain = $totalValue - $totalInvested
    $lastBuyDate = Get-ObjectPropertyValue -Object $valuedPortfolio -Name 'LastBuyDate'
    $lastBuyDateText = Get-ObjectPropertyValue -Object $valuedPortfolio -Name 'LastBuyDateText'

    # Risk cikislari olduysa durum notuna ekle (en one).
    if ($soldSymbols.Count -gt 0) {
        $statusNote = ('Risk çıkışı (sat): ' + ($soldSymbols -join ', ') + '. ' + $statusNote).Trim()
    }
    # Gerceklesen getiri: kapatilmis pozisyonlarin maliyetine gore.
    $realizedReturnPct = if ([double]$realizedCost -gt 0) { ([double]$realizedGain / [double]$realizedCost) * 100.0 } else { 0.0 }

    # KAPALI DONGU final nakit/deger (bugunku ALIM'lar da islendikten sonra, defterden turetilir).
    $finalCash = Get-InstantEntryCashTL -InitialCapitalTL $InitialCapitalTL -Transactions $transactions.ToArray()
    $cashTL = [double]$finalCash.CashTL
    $portfolioTotalValue = [Math]::Round($cashTL + $totalValue, 2)   # nakit + hissede duran deger
    $portfolioReturnPct = if ($InitialCapitalTL -gt 0) { (($portfolioTotalValue - $InitialCapitalTL) / $InitialCapitalTL) * 100.0 } else { 0.0 }
    $deployedPct = if ($InitialCapitalTL -gt 0) { ($totalValue / $InitialCapitalTL) * 100.0 } else { 0.0 }

    return [pscustomobject][ordered]@{
        Version = 1
        CreatedAt = Get-ObjectPropertyValue -Object $valuedPortfolio -Name 'CreatedAt'
        UpdatedAt = $AsOf.ToString('o')
        LastValuationAt = $AsOf.ToString('o')
        LastValuationAtText = $AsOf.ToString('dd.MM.yyyy HH:mm')
        DailyBudgetTL = [Math]::Round($DailyBudgetTL, 2)
        InitialCapitalTL = [Math]::Round($InitialCapitalTL, 2)
        MinBuyScore = [Math]::Round($MinBuyScore, 1)
        MaxBuysPerDay = $MaxBuysPerDay
        # Kapali dongu durumu
        CashTL = [Math]::Round($cashTL, 2)                       # kullanilabilir nakit (tekrar girise hazir)
        HoldingsValueTL = [Math]::Round($totalValue, 2)          # hissede duran guncel deger
        TotalValueTL = $portfolioTotalValue                     # nakit + hisse = toplam portfoy degeri
        TotalReturnPct = [Math]::Round($portfolioReturnPct, 2)  # 100k sermayeye gore getiri
        DeployedPct = [Math]::Round($deployedPct, 2)            # sermayenin yuzde kaci hissede
        TotalBoughtTL = [Math]::Round([double]$finalCash.TotalBoughtTL, 2)         # kumulatif girilen (tum alimlar)
        TotalSoldProceedsTL = [Math]::Round([double]$finalCash.TotalSoldProceedsTL, 2)  # kumulatif satis hasilati
        # Acik pozisyon detayi
        TotalInvestedTL = [Math]::Round($totalInvested, 2)      # acik pozisyon maliyeti
        CurrentValueTL = [Math]::Round($totalValue, 2)          # acik pozisyon guncel degeri (geriye uyum)
        UnrealizedGainTL = [Math]::Round($unrealizedGain, 2)    # acik K/Z
        # Gerceklesen (kapatilmis pozisyon) K/Z
        RealizedGainTL = [Math]::Round([double]$realizedGain, 2)
        RealizedCostTL = [Math]::Round([double]$realizedCost, 2)
        RealizedReturnPct = [Math]::Round([double]$realizedReturnPct, 2)
        LastBuyDate = $lastBuyDate
        LastBuyDateText = $lastBuyDateText
        StatusNote = $statusNote
        Notes = ('Anlık giriş fırsatı portföyü teorik modeldir (kapalı döngü: {0:N0} TL sermaye, günlük {1:N0} TL alım hakkı). Satış hasılatı + kâr nakte döner ve tekrar girişte kullanılabilir; nakit bitince yeni alım durur. Gerçek emir göndermez.' -f $InitialCapitalTL, $DailyBudgetTL)
        Holdings = $finalHoldings.ToArray()
        Transactions = $transactions.ToArray()
    }
}

function Get-InstantEntryPortfolioSummaryRows {
    param($Portfolio)

    # Kapali dongu ozeti: 100k sermaye -> ne kadar girilmis (kumulatif), ne kadar hissede
    # duruyor (guncel), ne kadar kar-satisi (gerceklesen) yapilmis, kalan nakit ve toplam deger.
    # Geriye uyum: yeni alanlar yoksa (eski state) makul varsayilanlara duser.
    $initialCapital = Get-NumberValue -Object $Portfolio -Name 'InitialCapitalTL'
    if ($null -eq $initialCapital) { $initialCapital = 100000.0 }
    $holdingsValue = Get-NumberValue -Object $Portfolio -Name 'HoldingsValueTL'
    if ($null -eq $holdingsValue) { $holdingsValue = Get-NumberValue -Object $Portfolio -Name 'CurrentValueTL' }
    $cash = Get-NumberValue -Object $Portfolio -Name 'CashTL'
    $totalValue = Get-NumberValue -Object $Portfolio -Name 'TotalValueTL'
    if ($null -ne $cash -and $null -ne $holdingsValue -and $null -eq $totalValue) { $totalValue = [double]$cash + [double]$holdingsValue }

    return @(
        [pscustomobject][ordered]@{
            'Toplam Sermaye' = Format-ReportNumber -Value $initialCapital -Format 'N0' -Suffix ' TL'
            'Günlük Alım Hakkı' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $Portfolio -Name 'DailyBudgetTL') -Format 'N0' -Suffix ' TL'
            'Kullanılabilir Nakit' = Format-ReportNumber -Value $cash -Format 'N2' -Suffix ' TL'
            'Hissede (Güncel Değer)' = Format-ReportNumber -Value $holdingsValue -Format 'N2' -Suffix ' TL'
            'Toplam Girilen (kümülatif alım)' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $Portfolio -Name 'TotalBoughtTL') -Format 'N2' -Suffix ' TL'
            'Kâr-Satışı Hasılatı (kümülatif)' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $Portfolio -Name 'TotalSoldProceedsTL') -Format 'N2' -Suffix ' TL'
            'Açık K/Z' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $Portfolio -Name 'UnrealizedGainTL') -Format 'N2' -Suffix ' TL'
            'Gerçekleşen K/Z (satışlardan)' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $Portfolio -Name 'RealizedGainTL') -Format 'N2' -Suffix ' TL'
            'Toplam Değer (nakit + hisse)' = Format-ReportNumber -Value $totalValue -Format 'N2' -Suffix ' TL'
            'Getiri (100k sermayeye göre)' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $Portfolio -Name 'TotalReturnPct') -Format 'N2' -Suffix '%'
            'Son Alım' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $Portfolio -Name 'LastBuyDateText')
            Durum = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $Portfolio -Name 'StatusNote')
        }
    )
}

function Get-InstantEntryPortfolioHoldingRows {
    param($Portfolio)

    return @(
        @(Get-ObjectPropertyValue -Object $Portfolio -Name 'Holdings') | ForEach-Object {
            [pscustomobject][ordered]@{
                Sembol = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Symbol')
                Şirket = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Company')
                Adet = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'Quantity') -Format 'N2'
                'Maliyet TL' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'CostBasisTL') -Format 'N0'
                'Deger TL' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'CurrentValueTL') -Format 'N0'
                Ağırlık = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'WeightPct') -Format 'N1' -Suffix '%'
                'Getiri %' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'UnrealizedGainPct') -Format 'N1'
                'Alim' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'BuyCount')
                'Ilk Alim' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'FirstBuyAtText')
            }
        }
    )
}

function Get-InstantEntryPortfolioTransactionRows {
    param(
        $Portfolio,
        [int]$Count = 30
    )

    return @(
        @(Get-ObjectPropertyValue -Object $Portfolio -Name 'Transactions') |
            Sort-Object @{ Expression = { [int](Get-ObjectPropertyValue -Object $_ -Name 'Sequence') }; Descending = $true } |
            Select-Object -First $Count |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    Sıra = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Sequence')
                    Tarih = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'ExecutionDateText')
                    İşlem = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Action')
                    Sembol = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Symbol')
                    Şirket = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Company')
                    Fiyat = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'Price') -Format 'N2' -Suffix ' TL'
                    Adet = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'Quantity') -Format 'N4'
                    Tutar = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'AmountTL') -Format 'N2' -Suffix ' TL'
                    'Sinyal Skoru' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'SignalScore') -Format 'N1'
                    Etiket = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'SignalLabel')
                    Not = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Note')
                }
            }
    )
}

function Invoke-ClaudeMessage {
    <#
        Anthropic Messages API'ye tek seferlik (non-streaming) cagri (ham REST,
        ek bagimlilik yok). Doner: metin (text blocklari birlestirilmis) ya da $null.
        Best-effort: hata/refusal durumunda $null doner; cagiran tarafi bozmaz.
    #>
    param(
        [Parameter(Mandatory)][string]$ApiKey,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$System,
        [Parameter(Mandatory)][string]$UserMessage,
        [int]$MaxTokens = 2000,
        [int]$TimeoutSec = 120,
        [string]$FallbackModel = ''
    )

    $payload = [ordered]@{
        model      = $Model
        max_tokens = $MaxTokens
        system     = $System
        messages   = @(@{ role = 'user'; content = $UserMessage })
    }
    $headers = @{
        'x-api-key'         = $ApiKey
        'anthropic-version' = '2023-06-01'
    }
    # En ust model (Fable/Mythos) icin: nadir bir reddi (refusal) sessizce
    # dusurmemek adina sunucu-tarafi fallback'i (Opus 4.8) ac.
    if (-not [string]::IsNullOrWhiteSpace($FallbackModel)) {
        $payload['fallbacks'] = @(@{ model = $FallbackModel })
        $headers['anthropic-beta'] = 'server-side-fallback-2026-06-01'
    }
    $json = $payload | ConvertTo-Json -Depth 6 -Compress

    # ONEMLI: Windows PowerShell 5.1'de Invoke-RestMethod, yanit govdesindeki UTF-8'i
    # yanlis (Latin-1) cozup Turkce karakterleri bozar (or. "Portföy" -> "PortfÃ¶y").
    # Bunu onlemek icin HttpClient ile ham bayt alip ACIKCA UTF-8 cozuyoruz.
    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 } catch { }
    $client = [System.Net.Http.HttpClient]::new()
    $respText = $null
    try {
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
        $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, 'https://api.anthropic.com/v1/messages')
        foreach ($k in $headers.Keys) { [void]$req.Headers.TryAddWithoutValidation($k, [string]$headers[$k]) }
        $req.Content = [System.Net.Http.StringContent]::new($json, [System.Text.Encoding]::UTF8, 'application/json')
        $httpResp = $client.SendAsync($req).GetAwaiter().GetResult()
        $bytes = $httpResp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        $respText = [System.Text.Encoding]::UTF8.GetString($bytes)
        if (-not $httpResp.IsSuccessStatusCode) {
            $snippet = $respText.Substring(0, [Math]::Min(300, $respText.Length))
            throw ("HTTP {0}: {1}" -f [int]$httpResp.StatusCode, $snippet)
        }
    }
    finally {
        $client.Dispose()
    }
    $resp = $respText | ConvertFrom-Json
    if ([string](Get-ObjectPropertyValue -Object $resp -Name 'stop_reason') -eq 'refusal') {
        return $null
    }
    # Fable/Mythos: yanitta bos metinli 'thinking' bloklari olabilir; yalniz 'text'
    # bloklarini al ('fallback' blogu da varsa atlanir, sorun degil).
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($block in @(Get-ObjectPropertyValue -Object $resp -Name 'content')) {
        if ([string](Get-ObjectPropertyValue -Object $block -Name 'type') -eq 'text') {
            [void]$parts.Add([string](Get-ObjectPropertyValue -Object $block -Name 'text'))
        }
    }
    $text = ($parts -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text
}

function Build-ModelPortfolioCommentaryPrompt {
    <#
        Ay sonu yeniden dengeleme degisikliklerini (cikan/giren/kalan + secim
        gerekceleri + agirliklar) LLM'e verilecek kompakt Turkce metne cevirir.
    #>
    param($PortfolioSet, [string]$PeriodEnd, $StockMap = $null)

    function Format-Metric {
        param($Value, [string]$Prefix, [string]$Suffix, [switch]$AllowNegative)
        if ($null -eq $Value -or [string]$Value -eq '') { return $null }
        $d = $null
        try { $d = [double]$Value } catch { return $null }
        if (-not $AllowNegative -and $d -eq 0) { return $null }
        return ('{0}{1:N1}{2}' -f $Prefix, $d, $Suffix)
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    [void]$lines.Add("Ay sonu yeniden dengeleme donemi: $PeriodEnd")
    [void]$lines.Add('Asagida 6 model portfoyun bu donemki degisiklikleri, secim gerekceleri ve guncel pozisyonlarinin temel/teknik verileri var.')
    foreach ($p in @(Get-ObjectPropertyValue -Object $PortfolioSet -Name 'Portfolios')) {
        $name = [string](Get-ObjectPropertyValue -Object $p -Name 'Name')
        $strategy = [string](Get-ObjectPropertyValue -Object $p -Name 'Strategy')
        $ret = Get-ObjectPropertyValue -Object $p -Name 'TotalReturnPct'
        $alpha = Get-ObjectPropertyValue -Object $p -Name 'AlphaPct'
        $mdd = Get-ObjectPropertyValue -Object $p -Name 'MaxDrawdownPct'
        $mddNum = $null
        if ($null -ne $mdd -and [string]$mdd -ne '') { try { $mddNum = [double]$mdd } catch { $mddNum = $null } }
        $weighting = [string](Get-ObjectPropertyValue -Object $p -Name 'WeightingMethod')
        [void]$lines.Add('')
        [void]$lines.Add(("### {0} (strateji: {1}{2})" -f $name, $strategy,
                $(if ($weighting -eq 'InverseVolatility') { ', agirlik: ters-oynaklik' } else { ', agirlik: esit' })))
        [void]$lines.Add(("Kurulustan getiri %{0}, BIST100'e karsi alfa %{1}{2}." -f `
                    $ret, $(if ($null -ne $alpha) { $alpha } else { 'yok' }),
                $(if ($null -ne $mddNum) { ", maks dusus %$mdd" } else { '' })))

        # Bu donemin islemleri (cikan/giren/esitleme) — secim gerekceleri Note'ta.
        $periodTx = @(Get-ObjectPropertyValue -Object $p -Name 'Transactions') | Where-Object {
            $pe = Get-ObjectPropertyValue -Object $_ -Name 'ExecutionDate'
            $act = [string](Get-ObjectPropertyValue -Object $_ -Name 'Action')
            $matchPeriod = $false
            try { $matchPeriod = ([datetime]$pe).ToString('yyyy-MM') -eq ([datetime]$PeriodEnd).ToString('yyyy-MM') } catch { $matchPeriod = $false }
            $matchPeriod -and ($act -ne 'PORTFÖY') -and ($act -ne 'KOMİSYON')
        }
        if (@($periodTx).Count -eq 0) {
            [void]$lines.Add('Bu donem alim/satim yok; yalniz mevcut pozisyonlar korundu/esitlendi.')
        }
        else {
            [void]$lines.Add('Bu donemki islemler ve secim gerekceleri:')
            foreach ($t in @($periodTx | Select-Object -First 12)) {
                $act = [string](Get-ObjectPropertyValue -Object $t -Name 'Action')
                $sym = [string](Get-ObjectPropertyValue -Object $t -Name 'Symbol')
                $note = [string](Get-ObjectPropertyValue -Object $t -Name 'Note')
                [void]$lines.Add(("- {0} {1}: {2}" -f $act, $sym, $note))
            }
        }

        # Guncel pozisyonlar — GERCEK temel/teknik veriyle (StockMap'ten zenginlestirilir).
        [void]$lines.Add('Guncel pozisyonlar (temel/teknik):')
        foreach ($h in @(Get-ObjectPropertyValue -Object $p -Name 'Holdings')) {
            $sym = [string](Get-ObjectPropertyValue -Object $h -Name 'Symbol')
            $weight = Get-ObjectPropertyValue -Object $h -Name 'WeightPct'
            $stock = if ($null -ne $StockMap -and $StockMap.ContainsKey($sym)) { $StockMap[$sym] } else { $h }
            $company = [string](Get-ObjectPropertyValue -Object $stock -Name 'Company')
            $sector = [string](Get-ObjectPropertyValue -Object $stock -Name 'SectorTR')
            $segs = New-Object System.Collections.Generic.List[string]
            [void]$segs.Add("agirlik %$weight")
            $m = Format-Metric (Get-ObjectPropertyValue -Object $stock -Name 'MarketCapBn') 'piyasa degeri ' ' mlr TL'; if ($m) { [void]$segs.Add($m) }
            $m = Format-Metric (Get-ObjectPropertyValue -Object $stock -Name 'PE') 'F/K ' ''; if ($m) { [void]$segs.Add($m) }
            $m = Format-Metric (Get-ObjectPropertyValue -Object $stock -Name 'PB') 'PD/DD ' ''; if ($m) { [void]$segs.Add($m) }
            $m = Format-Metric (Get-ObjectPropertyValue -Object $stock -Name 'EvEbitda') 'FD/FAVOK ' ''; if ($m) { [void]$segs.Add($m) }
            $m = Format-Metric (Get-ObjectPropertyValue -Object $stock -Name 'ROE') 'ROE %' '' -AllowNegative; if ($m) { [void]$segs.Add($m) }
            $m = Format-Metric (Get-ObjectPropertyValue -Object $stock -Name 'DividendYield') 'temettu %' ''; if ($m) { [void]$segs.Add($m) }
            $m = Format-Metric (Get-ObjectPropertyValue -Object $stock -Name 'PerfMonth') '1A getiri %' '' -AllowNegative; if ($m) { [void]$segs.Add($m) }
            $m = Format-Metric (Get-ObjectPropertyValue -Object $stock -Name 'Perf3Month') '3A getiri %' '' -AllowNegative; if ($m) { [void]$segs.Add($m) }
            $m = Format-Metric (Get-ObjectPropertyValue -Object $stock -Name 'RSI') 'RSI ' ''; if ($m) { [void]$segs.Add($m) }
            $head = if ([string]::IsNullOrWhiteSpace($company)) { $sym } else { "$sym ($company" + $(if ($sector) { ", $sector" } else { '' }) + ')' }
            [void]$lines.Add(('- {0}: {1}' -f $head, ($segs -join ', ')))
        }
    }
    return ($lines -join "`n")
}

function Update-ModelPortfolioCommentary {
    <#
        Ay sonu portfoy YENIDEN DENGELENDIGINDE (donem degistiginde) Claude ile
        portfoy degisikliklerini yorumlatip set'e (MonthlyCommentary) yazar; rapor
        bu yorumu her gun gosterir. Yalniz donem degisince uretilir (ayda 1 cagri).
        Best-effort: anahtar yoksa / hata olursa yorum atlanir, set bozulmaz.
    #>
    param($PortfolioSet, $Settings, [datetime]$AsOf, [switch]$Force, $StockMap = $null)

    if ($null -eq $PortfolioSet) { return $PortfolioSet }
    $cfg = Get-ConfigValue -Object $Settings.Report -Name 'ModelPortfolioCommentary' -Default $null
    $enabled = [bool](Get-ConfigValue -Object $cfg -Name 'Enabled' -Default $false)
    if (-not $enabled) { return $PortfolioSet }

    # En guncel yeniden dengeleme donemi (tum portfoyler ayni gun dengelenir).
    $latestPeriod = $null
    foreach ($p in @(Get-ObjectPropertyValue -Object $PortfolioSet -Name 'Portfolios')) {
        $pe = Get-ObjectPropertyValue -Object $p -Name 'LastRebalancePeriodEnd'
        if ($pe -and -not [string]::IsNullOrWhiteSpace([string]$pe)) {
            if ($null -eq $latestPeriod -or ([datetime]$pe) -gt ([datetime]$latestPeriod)) { $latestPeriod = [string]$pe }
        }
    }
    if ($null -eq $latestPeriod) { return $PortfolioSet }

    # Idempotent: bu donem icin yorum zaten varsa yeniden uretme (ayda 1 token).
    $existing = Get-ObjectPropertyValue -Object $PortfolioSet -Name 'MonthlyCommentary'
    $existingPeriod = if ($null -ne $existing) { [string](Get-ObjectPropertyValue -Object $existing -Name 'Period') } else { '' }
    if (-not $Force -and $existingPeriod -eq $latestPeriod) { return $PortfolioSet }

    $apiKey = $env:ANTHROPIC_API_KEY
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        Write-Warning 'ANTHROPIC_API_KEY yok; ay sonu portfoy yorumu atlandi (rapor bozulmaz).'
        return $PortfolioSet
    }
    $model = [string](Get-ConfigValue -Object $cfg -Name 'Model' -Default 'claude-opus-4-8')
    $maxTokens = [int](Get-ConfigValue -Object $cfg -Name 'MaxOutputTokens' -Default 2000)

    $system = (
        "Kidemli bir BIST portfoy yoneticisisin ve yatirimcilarina AYLIK portfoy notu yaziyorsun. " +
        "Sana, kantitatif bir botun ay sonu yeniden dengeledigi 6 model portfoyun bu donemki " +
        "degisiklikleri, secim gerekceleri ve her pozisyonun GERCEK temel/teknik verileri (F/K, PD/DD, " +
        "FD/FAVOK, ROE, temettu, momentum, RSI, sektor, getiri/alfa) veriliyor.`n`n" +
        "YAZIM ILKELERI:`n" +
        "- Her portfoy icin 3-5 cumlelik AKICI bir paragraf yaz. Once NET BIR TEZ/KARAR ver (bu portfoy " +
        "bu ay neyi ifade ediyor, strateji kimligine uygun mu), sonra bunu 1-2 somut pozisyonla ve " +
        "GERCEK rakamlarla (F/K, ROE, FD/FAVOK, momentum vb.) gerekcelendir, en sonda EN ONEMLI RISKI belirt.`n" +
        "- Botun ic puanlarini (skor/kalite/makro puani gibi) ham sayi olarak SAYIP DOKME; bunlari " +
        "yatirimci diline cevir (or. 'F/K 5.7 ile ucuz ama holding iskontosu olabilir', 'momentum zayif " +
        "cunku 1 aylik getiri negatif ve RSI dusuk').`n" +
        "- Su risklere ozellikle dikkat et: sektor/isim yogunlasmasi, asiri tek-hisse agirligi, degerleme " +
        "(pahali/ucuz), momentum-strateji tutarsizligi (or. Momentum portfoyunde dususte olan hisse), " +
        "likidite, negatif alfa.`n" +
        "- En sonda '## Genel Degerlendirme' basligi altinda 2-3 cumle: hangi strateji one cikiyor, " +
        "PORTFOYLER ARASI ortak riskler (ayni isimlerin/sektorun birden cok portfoyde tekrar etmesi gibi " +
        "kurumsal bir gozlem cok degerlidir), ve bu ay sonu rotasyonunun ana temasi.`n" +
        "- Profesyonel ama anlasilir Turkce. Madde madde degil, paragraf halinde yaz. Uydurma rakam KULLANMA, " +
        "yalniz verilen veriye dayan. Markdown kullan: her portfoy icin '### Portfoy Adi' basligi.`n" +
        "- En altta tek satir: 'Bu bir yatirim tavsiyesi degildir; verilen veriye dayali gozlem ve yorumdur.'"
    )
    $userMessage = Build-ModelPortfolioCommentaryPrompt -PortfolioSet $PortfolioSet -PeriodEnd $latestPeriod -StockMap $StockMap
    # En ust model (Fable/Mythos) icin reddi Opus 4.8'e dusur (best-effort guvence).
    $fallbackModel = if ($model -like 'claude-fable*' -or $model -like 'claude-mythos*') { 'claude-opus-4-8' } else { '' }

    $text = $null
    try {
        $text = Invoke-ClaudeMessage -ApiKey $apiKey -Model $model -System $system -UserMessage $userMessage -MaxTokens $maxTokens -FallbackModel $fallbackModel
    }
    catch {
        Write-Warning "Ay sonu portfoy yorumu uretilemedi ($model): $($_.Exception.Message)"
        return $PortfolioSet
    }
    if ([string]::IsNullOrWhiteSpace($text)) {
        Write-Warning 'Ay sonu portfoy yorumu bos dondu (refusal/bos); atlandi.'
        return $PortfolioSet
    }

    $commentary = [pscustomobject][ordered]@{
        Period      = $latestPeriod
        Model       = $model
        GeneratedAt = $AsOf.ToString('o')
        GeneratedAtText = $AsOf.ToString('dd.MM.yyyy HH:mm')
        Text        = $text.Trim()
    }
    $PortfolioSet | Add-Member -NotePropertyName 'MonthlyCommentary' -NotePropertyValue $commentary -Force
    Write-Host "Ay sonu portfoy yorumu uretildi ($model, donem $latestPeriod, $($text.Length) kar.)."
    return $PortfolioSet
}

function Get-TransactionOrderSide {
    param($Transaction)

    $action = [string](Get-ObjectPropertyValue -Object $Transaction -Name 'Action')
    if ($action -match 'AL') { return 'Buy' }
    if ($action -match 'SAT') { return 'Sell' }
    return $null
}

function New-OrderIntentFromTransaction {
    param(
        [string]$Source,
        [string]$PortfolioId,
        [string]$PortfolioName,
        $Transaction
    )

    $symbol = [string](Get-ObjectPropertyValue -Object $Transaction -Name 'Symbol')
    if ([string]::IsNullOrWhiteSpace($symbol) -or $symbol -in @('PORTFÖY', 'KOMİSYON')) { return $null }

    $side = Get-TransactionOrderSide -Transaction $Transaction
    if ([string]::IsNullOrWhiteSpace($side)) { return $null }

    $quantity = Get-NumberValue -Object $Transaction -Name 'Quantity'
    $amount = Get-NumberValue -Object $Transaction -Name 'AmountTL'
    $price = Get-NumberValue -Object $Transaction -Name 'Price'
    if ($null -eq $quantity -or $quantity -le 0 -or $null -eq $amount -or $amount -le 0) { return $null }

    $sequence = [string](Get-ObjectPropertyValue -Object $Transaction -Name 'Sequence')
    $executionDate = [string](Get-ObjectPropertyValue -Object $Transaction -Name 'ExecutionDate')
    $intentId = '{0}:{1}:{2}:{3}:{4}' -f $Source, $PortfolioId, $sequence, $symbol, $executionDate

    return [pscustomobject][ordered]@{
        Id = $intentId
        CreatedAt = $executionDate
        Source = $Source
        PortfolioId = $PortfolioId
        PortfolioName = $PortfolioName
        Side = $side
        Symbol = $symbol
        Company = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $Transaction -Name 'Company')
        Price = if ($null -ne $price) { [Math]::Round([double]$price, 4) } else { $null }
        Quantity = [Math]::Round([double]$quantity, 6)
        AmountTL = [Math]::Round([double]$amount, 2)
        Note = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $Transaction -Name 'Note')
        Mode = 'PaperOnly'
    }
}

function Get-CurrentRunOrderIntents {
    param(
        $ModelPortfolioSet,
        $InstantEntryPortfolio,
        [datetime]$AsOf
    )

    $todayKey = $AsOf.ToString('yyyy-MM-dd')
    $intents = [System.Collections.Generic.List[object]]::new()

    foreach ($portfolio in @(Get-ObjectPropertyValue -Object $ModelPortfolioSet -Name 'Portfolios')) {
        $portfolioId = [string](Get-ObjectPropertyValue -Object $portfolio -Name 'Id')
        $portfolioName = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $portfolio -Name 'Name')
        foreach ($transaction in @(Get-ObjectPropertyValue -Object $portfolio -Name 'Transactions')) {
            $executionDate = Get-ObjectPropertyValue -Object $transaction -Name 'ExecutionDate'
            $isToday = try { ([datetime]$executionDate).ToString('yyyy-MM-dd') -eq $todayKey } catch { $false }
            if (-not $isToday) { continue }
            $intent = New-OrderIntentFromTransaction -Source 'ModelPortfolio' -PortfolioId $portfolioId -PortfolioName $portfolioName -Transaction $transaction
            if ($null -ne $intent) { [void]$intents.Add($intent) }
        }
    }

    foreach ($transaction in @(Get-ObjectPropertyValue -Object $InstantEntryPortfolio -Name 'Transactions')) {
        $executionDate = Get-ObjectPropertyValue -Object $transaction -Name 'ExecutionDate'
        $isToday = try { ([datetime]$executionDate).ToString('yyyy-MM-dd') -eq $todayKey } catch { $false }
        if (-not $isToday) { continue }
        $intent = New-OrderIntentFromTransaction -Source 'InstantEntry' -PortfolioId 'InstantEntry' -PortfolioName 'Anlık Fırsat Portföyü' -Transaction $transaction
        if ($null -ne $intent) { [void]$intents.Add($intent) }
    }

    return $intents.ToArray()
}

function Update-PaperBrokerState {
    param(
        $State,
        [object[]]$OrderIntents,
        [datetime]$AsOf,
        [int]$MaxOrders = 500
    )

    if ($null -eq $State -or $null -eq (Get-ObjectPropertyValue -Object $State -Name 'Orders')) {
        $State = [pscustomobject][ordered]@{
            Version = 1
            CreatedAt = $AsOf.ToString('o')
            UpdatedAt = $AsOf.ToString('o')
            Mode = 'PaperOnly'
            Notes = 'Gerçek emir göndermez; raporun ürettiği teorik order intent kayıtlarını doldurulmuş varsayan denetim defteridir.'
            Orders = @()
            Positions = @()
        }
    }

    $orders = [System.Collections.Generic.List[object]]::new()
    $knownOrderIds = @{}
    foreach ($order in @(Get-ObjectPropertyValue -Object $State -Name 'Orders')) {
        $id = [string](Get-ObjectPropertyValue -Object $order -Name 'Id')
        if (-not [string]::IsNullOrWhiteSpace($id)) { $knownOrderIds[$id] = $true }
        [void]$orders.Add($order)
    }

    $positions = @{}
    foreach ($position in @(Get-ObjectPropertyValue -Object $State -Name 'Positions')) {
        $key = [string](Get-ObjectPropertyValue -Object $position -Name 'Key')
        if ([string]::IsNullOrWhiteSpace($key)) {
            $key = '{0}|{1}|{2}' -f (Get-ObjectPropertyValue -Object $position -Name 'Source'), (Get-ObjectPropertyValue -Object $position -Name 'PortfolioId'), (Get-ObjectPropertyValue -Object $position -Name 'Symbol')
        }
        $positions[$key] = [pscustomobject][ordered]@{
            Key = $key
            Source = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $position -Name 'Source')
            PortfolioId = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $position -Name 'PortfolioId')
            PortfolioName = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $position -Name 'PortfolioName')
            Symbol = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $position -Name 'Symbol')
            Company = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $position -Name 'Company')
            Quantity = [double](Get-NumberValue -Object $position -Name 'Quantity')
            CostBasisTL = [double](Get-NumberValue -Object $position -Name 'CostBasisTL')
            LastPrice = Get-NumberValue -Object $position -Name 'LastPrice'
            LastOrderAt = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $position -Name 'LastOrderAt')
        }
    }

    foreach ($intent in @($OrderIntents)) {
        $id = [string](Get-ObjectPropertyValue -Object $intent -Name 'Id')
        if ([string]::IsNullOrWhiteSpace($id) -or $knownOrderIds.ContainsKey($id)) { continue }

        $source = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $intent -Name 'Source')
        $portfolioId = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $intent -Name 'PortfolioId')
        $symbol = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $intent -Name 'Symbol')
        $key = '{0}|{1}|{2}' -f $source, $portfolioId, $symbol
        $side = [string](Get-ObjectPropertyValue -Object $intent -Name 'Side')
        $quantity = [double](Get-NumberValue -Object $intent -Name 'Quantity')
        $amount = [double](Get-NumberValue -Object $intent -Name 'AmountTL')
        $price = Get-NumberValue -Object $intent -Name 'Price'

        [void]$orders.Add([pscustomobject][ordered]@{
                Id = $id
                CreatedAt = Get-ObjectPropertyValue -Object $intent -Name 'CreatedAt'
                FilledAt = $AsOf.ToString('o')
                Status = 'PaperFilled'
                Source = $source
                PortfolioId = $portfolioId
                PortfolioName = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $intent -Name 'PortfolioName')
                Side = $side
                Symbol = $symbol
                Company = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $intent -Name 'Company')
                Price = if ($null -ne $price) { [Math]::Round([double]$price, 4) } else { $null }
                Quantity = [Math]::Round($quantity, 6)
                AmountTL = [Math]::Round($amount, 2)
                Note = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $intent -Name 'Note')
            })
        $knownOrderIds[$id] = $true

        $position = if ($positions.ContainsKey($key)) { $positions[$key] } else {
            [pscustomobject][ordered]@{
                Key = $key
                Source = $source
                PortfolioId = $portfolioId
                PortfolioName = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $intent -Name 'PortfolioName')
                Symbol = $symbol
                Company = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $intent -Name 'Company')
                Quantity = 0.0
                CostBasisTL = 0.0
                LastPrice = $null
                LastOrderAt = $null
            }
        }

        if ($side -eq 'Buy') {
            $position.Quantity = [double]$position.Quantity + $quantity
            $position.CostBasisTL = [double]$position.CostBasisTL + $amount
        }
        elseif ($side -eq 'Sell') {
            $oldQuantity = [double]$position.Quantity
            $sellQuantity = [Math]::Min($oldQuantity, $quantity)
            $costReduction = if ($oldQuantity -gt 0) { [double]$position.CostBasisTL * ($sellQuantity / $oldQuantity) } else { 0.0 }
            $position.Quantity = [Math]::Max(0.0, $oldQuantity - $sellQuantity)
            $position.CostBasisTL = [Math]::Max(0.0, [double]$position.CostBasisTL - $costReduction)
        }
        $position.LastPrice = if ($null -ne $price) { [Math]::Round([double]$price, 4) } else { $position.LastPrice }
        $position.LastOrderAt = $AsOf.ToString('o')
        $positions[$key] = $position
    }

    $positionRows = @($positions.Values | Where-Object { [double](Get-ObjectPropertyValue -Object $_ -Name 'Quantity') -gt 0 } | Sort-Object Source, PortfolioId, Symbol | ForEach-Object {
            $_.Quantity = [Math]::Round([double]$_.Quantity, 6)
            $_.CostBasisTL = [Math]::Round([double]$_.CostBasisTL, 2)
            $_
        })
    $orderRows = @($orders | Sort-Object @{ Expression = { [string](Get-ObjectPropertyValue -Object $_ -Name 'FilledAt') }; Descending = $true } | Select-Object -First $MaxOrders)

    [pscustomobject][ordered]@{
        Version = 1
        CreatedAt = Get-ObjectPropertyValue -Object $State -Name 'CreatedAt'
        UpdatedAt = $AsOf.ToString('o')
        Mode = 'PaperOnly'
        Notes = 'Gerçek emir göndermez; raporun ürettiği teorik order intent kayıtlarını doldurulmuş varsayan denetim defteridir.'
        Orders = $orderRows
        Positions = $positionRows
    }
}

function ConvertTo-TurkishOrderSide {
    param([string]$Side)
    switch -Regex ($Side) {
        'Buy'  { return 'AL' }
        'Sell' { return 'SAT' }
        default { return (ConvertTo-PlainText $Side) }
    }
}

function ConvertTo-TurkishOrderSource {
    param([string]$Source)
    switch ($Source) {
        'ModelPortfolio' { return 'Model Portföy' }
        'InstantEntry'   { return 'Anlık Fırsat' }
        default          { return (ConvertTo-PlainText $Source) }
    }
}

function Get-OrderIntentRows {
    param([object[]]$OrderIntents)

    return @($OrderIntents | ForEach-Object {
            [pscustomobject][ordered]@{
                Kaynak = ConvertTo-TurkishOrderSource ([string](Get-ObjectPropertyValue -Object $_ -Name 'Source'))
                Portfoy = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'PortfolioName')
                Yon = ConvertTo-TurkishOrderSide ([string](Get-ObjectPropertyValue -Object $_ -Name 'Side'))
                Sembol = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Symbol')
                Sirket = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Company')
                Fiyat = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'Price') -Format 'N2'
                Adet = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'Quantity') -Format 'N4'
                Tutar = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'AmountTL') -Format 'N2' -Suffix ' TL'
                Not = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Note')
            }
        })
}

function Get-PaperBrokerPositionRows {
    param($PaperBroker)

    return @(@(Get-ObjectPropertyValue -Object $PaperBroker -Name 'Positions') | ForEach-Object {
            [pscustomobject][ordered]@{
                Kaynak = ConvertTo-TurkishOrderSource ([string](Get-ObjectPropertyValue -Object $_ -Name 'Source'))
                Portfoy = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'PortfolioName')
                Sembol = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Symbol')
                Sirket = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Company')
                Adet = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'Quantity') -Format 'N4'
                'Maliyet TL' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'CostBasisTL') -Format 'N2'
                'Son Fiyat' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'LastPrice') -Format 'N2'
                'Son Emir' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'LastOrderAt')
            }
        })
}

function New-PointInTimeSnapshot {
    param(
        [object[]]$ScoredStocks,
        $MacroSnapshot,
        $ModelPortfolioSet,
        [datetime]$AsOf,
        [int]$Limit = 120
    )

    $rows = @(
        $ScoredStocks |
            Sort-Object Score -Descending |
            Select-Object -First $Limit |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    Symbol = ConvertTo-PlainText $_.Symbol
                    Company = ConvertTo-PlainText $_.Company
                    SectorTR = ConvertTo-PlainText $_.SectorTR
                    Price = Get-NumberValue -Object $_ -Name 'Price'
                    Score = Get-NumberValue -Object $_ -Name 'Score'
                    Signal = ConvertTo-PlainText $_.Signal
                    RiskLevel = ConvertTo-PlainText $_.RiskLevel
                    RawFactorScore100 = Get-NumberValue -Object $_ -Name 'RawFactorScore100'
                    AcademicFactorScore100 = Get-NumberValue -Object $_ -Name 'AcademicFactorScore100'
                    VolatilityD = Get-NumberValue -Object $_ -Name 'VolatilityD'
                    AverageVolume10D = Get-NumberValue -Object $_ -Name 'AverageVolume10D'
                    MarketCap = Get-NumberValue -Object $_ -Name 'MarketCap'
                    RSI = Get-NumberValue -Object $_ -Name 'RSI'
                    RelativeVolume = Get-NumberValue -Object $_ -Name 'RelativeVolume'
                    DataQualityOk = Get-ObjectPropertyValue -Object $_ -Name 'DataQualityOk'
                }
            }
    )

    [pscustomobject][ordered]@{
        Version = 1
        AsOf = $AsOf.ToString('o')
        UniverseCount = @($ScoredStocks).Count
        SnapshotLimit = $Limit
        MacroStatus = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $MacroSnapshot -Name 'Status')
        MacroSupportiveCount = Get-ObjectPropertyValue -Object $MacroSnapshot -Name 'SupportiveCount'
        MacroPressureCount = Get-ObjectPropertyValue -Object $MacroSnapshot -Name 'PressureCount'
        ModelPortfolioIds = @(@(Get-ObjectPropertyValue -Object $ModelPortfolioSet -Name 'Portfolios') | ForEach-Object { [string](Get-ObjectPropertyValue -Object $_ -Name 'Id') })
        Stocks = $rows
    }
}

function Save-JsonFile {
    param(
        [string]$Path,
        $Value,
        [int]$Depth = 8
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $directory = [IO.Path]::GetDirectoryName($fullPath)
    if ([string]::IsNullOrWhiteSpace($directory)) {
        throw "JSON dosyasi icin dizin belirlenemedi: $Path"
    }
    if (-not (Test-Path -LiteralPath $directory)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }

    $json = ConvertTo-Json -InputObject $Value -Depth $Depth
    $targetFileName = [IO.Path]::GetFileName($fullPath)
    $tempPath = Join-Path -Path $directory -ChildPath ('.{0}.{1}.tmp' -f $targetFileName, [guid]::NewGuid().ToString('N'))
    $backupPath = Join-Path -Path $directory -ChildPath ('.{0}.{1}.bak' -f $targetFileName, [guid]::NewGuid().ToString('N'))
    $encoding = [Text.UTF8Encoding]::new($true)

    try {
        [IO.File]::WriteAllText($tempPath, $json, $encoding)
        [void](ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($tempPath, $encoding)))

        if ([IO.File]::Exists($fullPath)) {
            [IO.File]::Replace($tempPath, $fullPath, $backupPath, $true)
            if ([IO.File]::Exists($backupPath)) {
                [IO.File]::Delete($backupPath)
            }
        }
        else {
            [IO.File]::Move($tempPath, $fullPath)
        }
    }
    catch {
        if ([IO.File]::Exists($tempPath)) {
            try { [IO.File]::Delete($tempPath) } catch { }
        }
        if ([IO.File]::Exists($backupPath) -and [IO.File]::Exists($fullPath)) {
            try { [IO.File]::Delete($backupPath) } catch { }
        }
        throw
    }
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
        [string]$CsvPath,
        [string]$InlineImagePath,
        [string]$InlineImageCid = 'perfchart'
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
        $message.HeadersEncoding = [Text.Encoding]::UTF8
        # Grafik gomulu (CID) gonderilecekse AlternateView + LinkedResource kullan;
        # Gmail data-URI/dis gorseli engelleyebildigi icin CID en guvenilir yontemdir.
        if (-not [string]::IsNullOrWhiteSpace($InlineImagePath) -and (Test-Path -LiteralPath $InlineImagePath)) {
            $altView = [Net.Mail.AlternateView]::CreateAlternateViewFromString($HtmlBody, [Text.Encoding]::UTF8, 'text/html')
            $linked = [Net.Mail.LinkedResource]::new($InlineImagePath, 'image/png')
            $linked.ContentId = $InlineImageCid
            $linked.TransferEncoding = [System.Net.Mime.TransferEncoding]::Base64
            $altView.LinkedResources.Add($linked)
            $message.AlternateViews.Add($altView)
        }
        else {
            $message.Body = $HtmlBody
            $message.BodyEncoding = [Text.Encoding]::UTF8
            $message.IsBodyHtml = $true
        }
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
$instantEntryPortfolioDailyBudgetTL = [double](Get-ConfigValue -Object $settings.Report -Name 'InstantEntryPortfolioDailyBudgetTL' -Default 5000)
$instantEntryPortfolioInitialCapitalTL = [double](Get-ConfigValue -Object $settings.Report -Name 'InstantEntryPortfolioInitialCapitalTL' -Default 100000)
$instantEntryPortfolioMinBuyScore = [double](Get-ConfigValue -Object $settings.Report -Name 'InstantEntryPortfolioMinBuyScore' -Default 90)
$instantEntryPortfolioMaxBuysPerDay = [int](Get-ConfigValue -Object $settings.Report -Name 'InstantEntryPortfolioMaxBuysPerDay' -Default 3)
$modelCostBps = [double](Get-EnvironmentValue -Names @('BIST_MODEL_COST_BPS') -Default ([string](Get-ConfigValue -Object $settings.Report -Name 'ModelPortfolioCostBps' -Default 50)))
$snapshotMaxStocks = [int](Get-ConfigValue -Object $settings.Report -Name 'SnapshotMaxStocks' -Default 120)
$riskRules = Get-ReportRiskRules -Settings $settings
$outputDirectory = Resolve-ReportPath -Path ([string](Get-ConfigValue -Object $settings.Report -Name 'OutputDirectory' -Default 'reports'))
if (-not (Test-Path $outputDirectory)) {
    [void](New-Item -ItemType Directory -Path $outputDirectory -Force)
}

# BIST piyasa yerel saati (Istanbul, UTC+3). CI runner UTC oldugu icin Get-Date
# UTC dönerdi; bu da ay-sonu rebalance kararini yanlis saat diliminde verdiriyordu
# (18:15 Istanbul = 15:15 UTC < 18:10 tampon -> ay-sonu gec algilaniyordu). Artik
# tum rapor zaman damgalari ve rebalance kararlari piyasa saatine gore.
$runAt = Get-BistMarketNow
$stamp = $runAt.ToString('yyyyMMdd_HHmm')
$htmlPath = Join-Path $outputDirectory "BIST_Rapor_$stamp.html"
$csvPath = Join-Path $outputDirectory "BIST_Top_$stamp.csv"
$logPath = Join-Path $outputDirectory 'GunlukRapor.log'

try {
    $reportStartedAt = Get-Date
    $stageStartedAt = Get-Date
    $stocks = @(Invoke-BistStockScan)
    Write-TimingLog -Step 'Canli BIST taramasi' -StartedAt $stageStartedAt

    # Kendini ogrenen sinyal kalibrasyonunu skorlamadan ONCE yukle (varsa).
    # Get-BistScore, bilanço zamanlama ayarini bu kalibrasyona gore uygular.
    $calibrationPath = Join-Path $PSScriptRoot 'data\signal_calibration.json'
    if (Test-Path $calibrationPath) {
        try { Set-SignalCalibration -Calibration (Get-Content -Path $calibrationPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
        catch { Write-Warning "Sinyal kalibrasyonu okunamadi: $($_.Exception.Message)" }
    }
    $activeCalibration = Get-SignalCalibration

    $stageStartedAt = Get-Date
    $scored = @(Get-BistScores -Stocks $stocks -Strategy $strategy | Sort-Object Score -Descending)
    # Ham-faktor eklenti skoru (kesitsel): backtest bulgusu, botun skorunun ~2 kati IC.
    # Mevcut Score'u degistirmez; her hisseye RawFactorScore100 (0-100) ekler.
    $scored = @(Add-RawFactorScore -Stocks $scored)
    # Akademik cok-faktor skoru (kesitsel beklenen-getiri proxy'si): deger +
    # kalite + momentum(12-1) + dusuk-vol + boyut. Mevcut Score'u degistirmez;
    # AcademicFactorScore100 (0-100) ve risk/getiri metrikleri ekler.
    $scored = @(Add-AcademicFactorScore -Stocks $scored)
    # FAZ A (gozlem modu): hisse-bazli goreli guc (RS) sirasi. Skoru/secimi
    # DEGISTIRMEZ; her hisseye RelativeStrengthRank (0-100) ekler, yalniz raporda.
    $scored = @(Add-RelativeStrengthRank -Stocks $scored)
    Write-TimingLog -Step 'Skorlama' -StartedAt $stageStartedAt

    # FAZ A (gozlem modu): piyasa genisligi. Skoru/secimi DEGISTIRMEZ; bağlamdır.
    $marketBreadth = $null
    try { $marketBreadth = Get-MarketBreadth -Stocks $scored }
    catch { Write-Warning "Piyasa genisligi hesaplanamadi: $($_.Exception.Message)" }

    $stageStartedAt = Get-Date
    Save-JsonFile -Path (Join-Path $PSScriptRoot 'data\last_scan.json') -Value ([pscustomobject]@{
            UpdatedAt = $runAt.ToString('o')
            Count = $stocks.Count
            Stocks = $stocks
        }) -Depth 8
    Write-TimingLog -Step 'Son tarama state kaydi' -StartedAt $stageStartedAt

    # Point-in-time (PIT) anlik goruntu arsivi: o gun gozlenen evren + temel veriyi
    # tarihli olarak biriktirir (ileri-bakis yok). Zamanla gercek bir as-observed PIT
    # arsivi olusur ve backtest'ler temel veriyle beslenebilir hale gelir. Best-effort.
    $stageStartedAt = Get-Date
    try {
        $pitPath = Save-PitSnapshot -Stocks $stocks -Directory (Join-Path $PSScriptRoot 'data\pit') -AsOf $runAt
        Write-Host "PIT anlik goruntu kaydedildi: $pitPath"
    }
    catch { Write-Warning "PIT anlik goruntu kaydedilemedi: $($_.Exception.Message)" }
    Write-TimingLog -Step 'PIT anlik goruntu kaydi' -StartedAt $stageStartedAt

    # Kendi kendini degerlendiren geri-besleme: onceki kosunun yuksek-skorlu
    # secilerinin gerceklesen getirisi, skorun isabet oranini (hit-rate) olcer.
    $stageStartedAt = Get-Date
    $signalPerfPath = Join-Path $PSScriptRoot 'data\signal_performance.json'
    $previousSignalPerf = $null
    if (Test-Path $signalPerfPath) {
        try {
            $previousSignalPerf = Get-Content -Path $signalPerfPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            Write-Warning "Onceki sinyal performans state'i okunamadi: $($_.Exception.Message)"
            $previousSignalPerf = $null
        }
    }
    $signalPerf = Update-SignalPerformance -Previous $previousSignalPerf -ScoredStocks $scored -AsOf $runAt -TopCount $topCount
    Save-JsonFile -Path $signalPerfPath -Value $signalPerf -Depth 10
    $signalPerfSummary = $signalPerf.Summary
    Write-TimingLog -Step 'Sinyal performans degerlendirmesi' -StartedAt $stageStartedAt

    # PEAD (bilanco sonrasi suruklenme) geri-besleme dongusu.
    $stageStartedAt = Get-Date
    $earningsReactionPath = Join-Path $PSScriptRoot 'data\earnings_reactions.json'
    $previousReactions = $null
    if (Test-Path $earningsReactionPath) {
        try { $previousReactions = Get-Content -Path $earningsReactionPath -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { Write-Warning "Onceki PEAD state'i okunamadi: $($_.Exception.Message)"; $previousReactions = $null }
    }
    $earningsReactions = Update-EarningsReactions -Previous $previousReactions -Stocks $stocks -AsOf $runAt
    Save-JsonFile -Path $earningsReactionPath -Value $earningsReactions -Depth 10
    $earningsReactionSummary = $earningsReactions.Summary
    Write-TimingLog -Step 'PEAD bilanço tepkisi' -StartedAt $stageStartedAt

    # Kendini ogrenen kalibrasyon: PEAD tamamlanmis orneklerinden bilanço sonrasi
    # skor ayarini veriye gore guncelle ve SONRAKI kosu icin kaydet.
    $stageStartedAt = Get-Date
    $signalCalibration = Update-SignalCalibration -Reactions $earningsReactions -AsOf $runAt
    Save-JsonFile -Path $calibrationPath -Value $signalCalibration -Depth 6
    Write-TimingLog -Step 'Sinyal kalibrasyonu' -StartedAt $stageStartedAt

    # BIST100 seviyesini bir kez cek (portfoy alfasi + makro icin tekrar kullan).
    $indexSnapshot = Get-BistIndexBenchmarks -TimeoutSec $macroTimeoutSec
    $bist100Level = [double](Get-ObjectPropertyValue -Object (Get-ObjectPropertyValue -Object $indexSnapshot -Name 'Bist100') -Name 'Price')
    if ($null -eq $bist100Level) { $bist100Level = 0 }

    $stageStartedAt = Get-Date
    $portfolioPath = Join-Path $PSScriptRoot 'data\model_portfolios.json'
    $portfolioSet = $null
    if (Test-Path $portfolioPath) {
        $portfolioSet = Get-Content -Path $portfolioPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $modelMaxBookPct = [double](Get-ConfigValue -Object $settings.Report -Name 'ModelPortfolioMaxBookPct' -Default 15)
    $updatedPortfolioSet = Update-ModelPortfolioSet -PortfolioSet $portfolioSet -Stocks $stocks -AsOf $runAt -AllowRebalance -BenchmarkLevel $bist100Level -CostBps $modelCostBps -MaxBookPct $modelMaxBookPct
    if ($null -eq $updatedPortfolioSet) {
        $updatedPortfolioSet = New-ModelPortfolioSet -Stocks $stocks -AsOf $runAt -BenchmarkLevel $bist100Level -CostBps $modelCostBps
        $updatedPortfolioSet.Portfolios = Optimize-ModelPortfolioSetRisk -Portfolios @($updatedPortfolioSet.Portfolios) -MaxBookPct $modelMaxBookPct
    }
    # Ay sonu Claude yorumu (best-effort): yalniz portfoy bu donem yeniden
    # dengelendiyse uretilir; aksi halde onceki donemin yorumu korunup gosterilir.
    try {
        $updatedPortfolioSet = Update-ModelPortfolioCommentary -PortfolioSet $updatedPortfolioSet -Settings $settings -AsOf $runAt -StockMap (Get-StockLookup -Stocks $stocks)
    }
    catch {
        Write-Warning "Ay sonu portfoy yorumu adimi atlandi: $($_.Exception.Message)"
    }
    Save-JsonFile -Path $portfolioPath -Value $updatedPortfolioSet -Depth 8
    Write-TimingLog -Step 'Model portfoy degerleme' -StartedAt $stageStartedAt

    # Performans karsilastirma grafigi: tum model portfoyler + BIST100/Altin/Mevduat/
    # Nasdaq/S&P500 (TRY %). Kurulustan bugune islem gecmisi + Yahoo ile yeniden kurulur;
    # her gun otomatik uzar. Best-effort: hata olursa grafik atlanir, rapor bozulmaz.
    $stageStartedAt = Get-Date
    $perfChartUrl = $null
    $perfSummaryRows = @()
    $bistSourceWarning = $null   # BIST100 canli-snapshot vs Yahoo serisi capraz-kontrol uyarisi
    $priceCache = @{}   # portfoy hisselerinin 1y kapanis serisi; R:R 52h zirvesi icin paylasilir
    try {
        $strategySeries = @(Get-StrategyPerformanceSeries -PortfolioSet $updatedPortfolioSet -TimeoutSec 8 -PriceCache $priceCache)
        $earliestStart = $null
        foreach ($p in @(Get-ObjectPropertyValue -Object $updatedPortfolioSet -Name 'Portfolios')) {
            $sd = Get-ObjectPropertyValue -Object $p -Name 'StartDate'
            if ($sd) { $d = [datetime]$sd; if ($null -eq $earliestStart -or $d -lt $earliestStart) { $earliestStart = $d } }
        }
        if ($null -eq $earliestStart) { $earliestStart = $runAt.AddMonths(-1) }
        $benchmarkSeries = @(Get-BenchmarkPerformanceSeries -StartDate $earliestStart -TimeoutSec 8)

        $perfChartUrl = New-PerformanceComparisonChart -StrategySeries $strategySeries -BenchmarkSeries $benchmarkSeries -TimeoutSec 25
        if ($perfChartUrl) { Write-Host "Performans grafigi URL'si uretildi: $perfChartUrl" } else { Write-Host 'Performans grafigi uretilemedi (QuickChart erisilemedi); ozet tablo gosterilecek.' }

        # Ozet tablo: MODEL PORTFOYLER + BIST100 icin OTORITE/CANLI getiriler kullanilir
        # (detay model-portfoy tablosuyla BIREBIR ayni; TradingView mark-to-market). Boylece
        # iki tablo celismez. Grafikteki gunluk cizgiler Yahoo kapanisindan YENIDEN KURULUR
        # (gecmis seri icin gerekli) ve saglayici/zaman farkiyla bu canli degerlerden hafif
        # sapabilir. Yabanci varliklar (Altin/Nasdaq/S&P/Mevduat) icin canli kaynak yok -> Yahoo.
        $livePortfolios = @(Get-ObjectPropertyValue -Object $updatedPortfolioSet -Name 'Portfolios')
        $liveRows = @($livePortfolios | ForEach-Object {
                [pscustomobject]@{ Name = [string](Get-ObjectPropertyValue -Object $_ -Name 'Name'); ReturnPct = [double](Get-ObjectPropertyValue -Object $_ -Name 'TotalReturnPct') }
            })
        # BIST100: alfa ile AYNI canli snapshot getirisi (tum portfoyler ayni benchmark'i paylasir).
        $liveBistReturn = $null
        foreach ($lp in $livePortfolios) {
            $br = Get-NumberValue -Object $lp -Name 'BenchmarkReturnPct'
            if ($null -ne $br) { $liveBistReturn = [double]$br; break }
        }
        if ($null -ne $liveBistReturn) { $liveRows += [pscustomobject]@{ Name = 'BIST100'; ReturnPct = $liveBistReturn } }
        # Yabanci varliklar (BIST100 HARIC; o canli geldi) Yahoo serisinden.
        $foreignRows = @(@($benchmarkSeries) | Where-Object { $_ -and @($_.Points).Count -gt 0 -and [string]$_.Name -ne 'BIST100' } | ForEach-Object {
                $last = $_.Points[$_.Points.Count - 1]
                [pscustomobject]@{ Name = [string]$_.Name; ReturnPct = [double]$last.ReturnPct }
            })
        $perfSummaryRows = @(@($liveRows) + @($foreignRows) | Sort-Object ReturnPct -Descending)
        # BIST100 capraz-kontrol: canli TradingView snapshot vs Yahoo XU100.IS serisi. Belirgin
        # sapma alfayi guvenilmez kilar -> SESSIZCE yanlis gostermeyiz, rapora gorunur uyari.
        $yahooBist = @(@($benchmarkSeries) | Where-Object { [string]$_.Name -eq 'BIST100' -and @($_.Points).Count -gt 0 } | Select-Object -First 1)
        if ($yahooBist.Count -gt 0 -and $null -ne $liveBistReturn) {
            $yb = [double]$yahooBist[0].Points[$yahooBist[0].Points.Count - 1].ReturnPct
            if ([Math]::Abs($yb - $liveBistReturn) -gt 1.5) {
                $bistSourceWarning = ('⚠️ BIST100 iki veri kaynağında belirgin farklı: canlı TradingView %{0}, Yahoo XU100.IS %{1} (aynı dönem). Tablodaki getiriler ve <b>alfa canlı TradingView</b>''i kullanır; grafikteki BIST100 çizgisi Yahoo''dan gelir. Fark veri sağlayıcı kaynaklıdır — alfayı temkinli okuyun.' -f ([Math]::Round($liveBistReturn, 2)), ([Math]::Round($yb, 2)))
            }
        }
    }
    catch { Write-Warning "Performans grafigi/serisi uretilemedi: $($_.Exception.Message)" }
    Write-TimingLog -Step 'Performans karsilastirma grafigi' -StartedAt $stageStartedAt

    $stageStartedAt = Get-Date
    $macroSnapshot = Get-MacroSnapshot -IndexSnapshot $indexSnapshot -AsOf $runAt -TimeoutSec $macroTimeoutSec
    Write-TimingLog -Step 'Makro gorunum' -StartedAt $stageStartedAt

    # KAP son bildirimleri. Birincil kaynak: ayri is (kap-collector.yml, borsapy)
    # ile uretilip repoya commit edilen data/kap_disclosures.json. O dosya yoksa
    # canli best-effort Get-KapDisclosures'a duser. Her ikisi de bos donerse rapor
    # bozulmaz (gozlem modu; karar etkisi YOK).
    $stageStartedAt = Get-Date
    $storedKap = @()
    try { $storedKap = @(Get-StoredKapDisclosures -MaxAgeDays 1) } catch { $storedKap = @() }
    $kapDisclosures = if ($storedKap.Count -gt 0) { $storedKap } else { @(Get-KapDisclosures -TimeoutSec 5 -Limit 40) }
    $kapMeta = if ($storedKap.Count -gt 0) { 'depolanmis (borsapy/KAP)' } else { 'canli best-effort' }
    Write-TimingLog -Step 'KAP bildirimleri' -StartedAt $stageStartedAt

    $stageStartedAt = Get-Date
    $entryOpportunities = @(Get-InstantEntryOpportunities `
            -Stocks $scored `
            -CandidateLimit $instantEntryCandidateLimit `
            -TimeoutSec $instantEntryTimeoutSec `
            -MaxElapsedSec $instantEntryMaxElapsedSec)
    Write-TimingLog -Step 'Anlik giris firsati' -StartedAt $stageStartedAt

    $stageStartedAt = Get-Date
    $instantEntryPortfolioPath = Join-Path $PSScriptRoot 'data\instant_entry_portfolio.json'
    $instantEntryPortfolio = $null
    if (Test-Path $instantEntryPortfolioPath) {
        $instantEntryPortfolio = Get-Content -Path $instantEntryPortfolioPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $updatedInstantEntryPortfolio = Update-InstantEntrySignalPortfolio `
        -Portfolio $instantEntryPortfolio `
        -Opportunities $entryOpportunities `
        -Stocks $stocks `
        -AsOf $runAt `
        -DailyBudgetTL $instantEntryPortfolioDailyBudgetTL `
        -InitialCapitalTL $instantEntryPortfolioInitialCapitalTL `
        -MinBuyScore $instantEntryPortfolioMinBuyScore `
        -MaxBuysPerDay $instantEntryPortfolioMaxBuysPerDay `
        -RiskRules $riskRules
    Save-JsonFile -Path $instantEntryPortfolioPath -Value $updatedInstantEntryPortfolio -Depth 10
    Write-TimingLog -Step 'Anlik firsat portfoyu' -StartedAt $stageStartedAt

    # --- Web panel JSON (best-effort; mevcut rapor/mail/strateji akışını ETKİLEMEZ) ---
    # Bellekteki çıktıları docs/data/latest_report.json'a yazar; panel bunu okur.
    if (Get-Command Export-DashboardReport -ErrorAction SilentlyContinue) {
        try {
            $dashStrat = Get-Variable -Name strategySeries -ValueOnly -ErrorAction SilentlyContinue
            $dashBench = Get-Variable -Name benchmarkSeries -ValueOnly -ErrorAction SilentlyContinue
            if ($null -eq $dashStrat) { $dashStrat = @() }
            if ($null -eq $dashBench) { $dashBench = @() }
            [void](Export-DashboardReport -OutPath (Join-Path $PSScriptRoot 'docs/data/latest_report.json') `
                    -Stocks $scored -PortfolioSet $updatedPortfolioSet -InstantEntryPortfolio $updatedInstantEntryPortfolio `
                    -StrategySeries $dashStrat -BenchmarkSeries $dashBench -MarketBreadth $marketBreadth `
                    -PortfolioCommentary (Get-ObjectPropertyValue -Object $updatedPortfolioSet -Name 'MonthlyCommentary') `
                    -MacroSnapshot $macroSnapshot `
                    -AsOf $runAt -Strategy $strategy -PagesUrl 'https://neccoju.github.io/bist-rapor-botu/')
            Write-Host 'Web panel JSON guncellendi: docs/data/latest_report.json'
        }
        catch { Write-Warning "Web panel JSON uretilemedi (rapor etkilenmez): $($_.Exception.Message)" }
    }

    $stageStartedAt = Get-Date
    $snapshot = New-PointInTimeSnapshot -ScoredStocks $scored -MacroSnapshot $macroSnapshot -ModelPortfolioSet $updatedPortfolioSet -AsOf $runAt -Limit $snapshotMaxStocks
    $snapshotDirectory = Join-Path $PSScriptRoot 'data\point_in_time_snapshots'
    $snapshotPath = Join-Path $snapshotDirectory ($runAt.ToString('yyyyMMdd_HHmm') + '.json')
    Save-JsonFile -Path $snapshotPath -Value $snapshot -Depth 8
    Save-JsonFile -Path (Join-Path $PSScriptRoot 'data\latest_point_in_time_snapshot.json') -Value $snapshot -Depth 8
    Write-TimingLog -Step 'Point-in-time snapshot' -StartedAt $stageStartedAt

    $stageStartedAt = Get-Date
    $orderIntents = @(Get-CurrentRunOrderIntents -ModelPortfolioSet $updatedPortfolioSet -InstantEntryPortfolio $updatedInstantEntryPortfolio -AsOf $runAt)
    $orderIntentState = [pscustomobject][ordered]@{
        Version = 1
        UpdatedAt = $runAt.ToString('o')
        Mode = 'PaperOnly'
        Notes = 'Gerçek emir değildir; raporun ürettiği teorik işlem niyetlerinin denetim kaydıdır.'
        Intents = $orderIntents
    }
    $paperBrokerPath = Join-Path $PSScriptRoot 'data\paper_broker.json'
    $previousPaperBroker = $null
    if (Test-Path $paperBrokerPath) {
        try { $previousPaperBroker = Get-Content -Path $paperBrokerPath -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { Write-Warning "PaperBroker state'i okunamadi: $($_.Exception.Message)"; $previousPaperBroker = $null }
    }
    $paperBroker = Update-PaperBrokerState -State $previousPaperBroker -OrderIntents $orderIntents -AsOf $runAt
    Save-JsonFile -Path (Join-Path $PSScriptRoot 'data\order_intents.json') -Value $orderIntentState -Depth 8
    Save-JsonFile -Path $paperBrokerPath -Value $paperBroker -Depth 10
    Write-TimingLog -Step 'PaperBroker intent defteri' -StartedAt $stageStartedAt

    $topRows = @($scored | Select-Object -First $topCount | ForEach-Object {
            [pscustomobject][ordered]@{
                Skor = Format-ReportNumber -Value $_.Score -Format 'N1'
                'RFS100' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'RawFactorScore100') -Format 'N1'
                'AFS' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'AcademicFactorScore100') -Format 'N1'
                Gorus = ConvertTo-PlainText $_.Signal
                Teyit = ConvertTo-PlainText $_.ConfirmationLabel
                'Teyit n' = '{0}/{1}' -f (ConvertTo-PlainText $_.TechnicalPassCount), (ConvertTo-PlainText $_.TechnicalCheckCount)
                Sembol = ConvertTo-PlainText $_.Symbol
                Sirket = ConvertTo-PlainText $_.Company
                Sektor = ConvertTo-PlainText $_.SectorTR
                Fiyat = Format-ReportNumber -Value $_.Price -Format 'N2'
                'Makro' = Format-ReportNumber -Value $_.MacroSectorScore -Format 'N1'
                RSI = Format-ReportNumber -Value $_.RSI -Format 'N1'
                'MACD' = Format-ReportNumber -Value $_.MacdHistogram -Format 'N2'
                'Hacim' = Format-ReportNumber -Value $_.RelativeVolume -Format 'N1' -Suffix 'x'
            }
        })

    $academicRows = @($scored |
            Sort-Object @{ Expression = { [double](Get-ObjectPropertyValue -Object $_ -Name 'AcademicFactorScore100') }; Descending = $true } |
            Select-Object -First 12 |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    Sembol = ConvertTo-PlainText $_.Symbol
                    Sirket = ConvertTo-PlainText $_.Company
                    Sektor = ConvertTo-PlainText $_.SectorTR
                    'AFS' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'AcademicFactorScore100') -Format 'N1'
                    'Momentum 12-1' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'Momentum12_1Pct') -Format 'N1' -Suffix '%'
                    'Yillik Vol' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'AnnualizedVolatilityPct') -Format 'N1' -Suffix '%'
                    'Getiri/Risk' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'RiskAdjustedMomentum') -Format 'N2'
                    'FD/FAVOK' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'EvEbitda') -Format 'N1'
                    ROE = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'ROE') -Format 'N1' -Suffix '%'
                    Skor = Format-ReportNumber -Value $_.Score -Format 'N1'
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

    $earningsCalendarRows = @($scored |
            Where-Object { $null -ne (Get-ObjectPropertyValue -Object $_ -Name 'NextEarningsDate') } |
            Sort-Object @{ Expression = { [datetime](Get-ObjectPropertyValue -Object $_ -Name 'NextEarningsDate') }; Ascending = $true } |
            Select-Object -First 15 |
            ForEach-Object {
                $nextDate = [datetime](Get-ObjectPropertyValue -Object $_ -Name 'NextEarningsDate')
                $lastDate = Get-ObjectPropertyValue -Object $_ -Name 'LatestReportDate'
                $daysTo = [int][Math]::Ceiling(($nextDate.Date - $runAt.Date).TotalDays)
                $flag = if ($daysTo -lt 0) { 'Geçti/güncellenmedi' } elseif ($daysTo -le 7) { '⚠ Yaklaşıyor (olay riski)' } elseif ($daysTo -le 21) { 'Yakında' } else { 'Uzak' }
                [pscustomobject][ordered]@{
                    Sembol = ConvertTo-PlainText $_.Symbol
                    Sirket = ConvertTo-PlainText $_.Company
                    Skor = Format-ReportNumber -Value $_.Score -Format 'N1'
                    'Son Bilanço' = if ($null -ne $lastDate) { ([datetime]$lastDate).ToString('dd.MM.yyyy') } else { '-' }
                    'Sonraki Bilanço' = $nextDate.ToString('dd.MM.yyyy')
                    'Kalan Gün' = ConvertTo-PlainText $daysTo
                    Durum = $flag
                }
            })

    # Bilanco oncesi ivme radari (anticipation): yaklasan bilanco + guclenen fiyat.
    $preEarningsRows = @($scored |
            Where-Object { [bool](Get-ObjectPropertyValue -Object $_ -Name 'PreEarningsRunupActive') } |
            Sort-Object @{ Expression = { [int](Get-ObjectPropertyValue -Object $_ -Name 'DaysToNextEarnings') }; Ascending = $true } |
            Select-Object -First 15 |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    Sembol = ConvertTo-PlainText $_.Symbol
                    Sirket = ConvertTo-PlainText $_.Company
                    Skor = Format-ReportNumber -Value $_.Score -Format 'N1'
                    'Bilançoya Kalan' = '{0} gün' -f (ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'DaysToNextEarnings'))
                    'Aylık Getiri' = Format-ReportNumber -Value $_.PerfMonth -Format 'N1' -Suffix '%'
                    'Hacim' = Format-ReportNumber -Value $_.RelativeVolume -Format 'N1' -Suffix 'x'
                    RSI = Format-ReportNumber -Value $_.RSI -Format 'N1'
                }
            })

    # PEAD: yeni bilanco aciklamis ve izlenen hisseler (surprize gore).
    $peadTrackedRows = @($earningsReactions.Tracked |
            Sort-Object @{ Expression = { [double](Get-ObjectPropertyValue -Object $_ -Name 'SurpriseScore') }; Descending = $true } |
            Select-Object -First 12 |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    Sembol = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Symbol')
                    'Bilanço Tarihi' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'ReportDate')
                    'Sürpriz Skoru' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'SurpriseScore') -Format 'N0'
                    'Giriş Fiyatı' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'EntryPrice') -Format 'N2' -Suffix ' TL'
                }
            })

    # KAP son bildirimleri: oncelikle Top radar sembollerine ait olanlar, ardindan
    # diger ONEMLI bildirimler (gurultu = devre kesici/likidite/endeks haric).
    $topSymbolsForKap = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($s in @($scored | Select-Object -First $topCount)) {
        $cs = ([string]$s.Symbol).Trim().ToUpperInvariant() -replace '\.IS$', ''
        if ($cs) { [void]$topSymbolsForKap.Add($cs) }
    }
    # gurultu kategorilerini (onem='noise') rapordan dustur
    $kapSignal = @($kapDisclosures | Where-Object {
            $imp = [string](Get-ObjectPropertyValue -Object $_ -Name 'Importance')
            [string]::IsNullOrWhiteSpace($imp) -or $imp -ne 'noise'
        })
    $kapTop = @($kapSignal | Where-Object {
            $sym = ([string](Get-ObjectPropertyValue -Object $_ -Name 'Symbol')).Trim().ToUpperInvariant() -replace '\.IS$', ''
            $topSymbolsForKap.Contains($sym)
        })
    $kapForReport = @($kapTop) + @($kapSignal | Where-Object { $kapTop -notcontains $_ })
    if (@($kapForReport).Count -eq 0) { $kapForReport = $kapSignal }
    $dirIcon = @{ '+' = '🟢'; '-' = '🔴'; '~' = '🟡'; '0' = '⚪'; '?' = '❔' }
    $kapRows = @($kapForReport | Select-Object -First 20 | ForEach-Object {
            $dir = [string](Get-ObjectPropertyValue -Object $_ -Name 'Direction')
            $cat = [string](Get-ObjectPropertyValue -Object $_ -Name 'Category')
            $icon = if ($dir -and $dirIcon.ContainsKey($dir)) { $dirIcon[$dir] } else { '' }
            $catLabel = if ([string]::IsNullOrWhiteSpace($cat)) { ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Kind') } else { (ConvertTo-PlainText $cat) }
            # LLM yorumu varsa baslik yerine ozeti goster (etki skoruyla); yoksa basliga don.
            $summary = [string](Get-ObjectPropertyValue -Object $_ -Name 'Summary')
            $impact = Get-ObjectPropertyValue -Object $_ -Name 'Impact'
            $title = [string](Get-ObjectPropertyValue -Object $_ -Name 'Title')
            $yorum = if (-not [string]::IsNullOrWhiteSpace($summary)) {
                $pref = if ($null -ne $impact -and "$impact" -ne '') { "[etki $impact/5] " } else { '' }
                $pref + $summary
            }
            else { $title }
            [pscustomobject][ordered]@{
                Sembol = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Symbol')
                Kategori = (("$icon $catLabel").Trim())
                Yorum = ConvertTo-PlainText $yorum
                Tarih = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Date')
            }
        })

    # Veri kalitesi ozeti.
    $dqFlagged = @($scored | Where-Object { -not [bool](Get-ObjectPropertyValue -Object $_ -Name 'DataQualityOk') })
    $dqFlaggedCount = $dqFlagged.Count
    $dqTotal = @($scored).Count

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
                Fiyat = Format-ReportNumber -Value $_.Price -Format 'N2'
                'Hist Etiket' = ConvertTo-PlainText $_.WeeklyHistogramLabel
                '8H Artis' = '{0}/7' -f (ConvertTo-PlainText $_.WeeklyHistogramIncreaseCount)
                RSI = Format-ReportNumber -Value $_.RSI -Format 'N1'
                '52H %' = Format-ReportNumber -Value $_.Range52PositionPct -Format 'N1'
                'Makro' = Format-ReportNumber -Value $_.MacroSectorScore -Format 'N1'
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
                'BIST100' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'BenchmarkReturnPct') -Format 'N2' -Suffix '%'
                'Alfa' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'AlphaPct') -Format 'N2' -Suffix '%'
                'Maks Düşüş' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'MaxDrawdownPct') -Format 'N1' -Suffix '%'
                'Ağırlık' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'WeightingMethod')
                Hisseler = ((@($_.Holdings) | ForEach-Object Symbol) -join ', ')
                'Baslangic' = ConvertTo-PlainText $_.StartDateText
                'Son Islem' = ConvertTo-PlainText $_.LastRebalanceDateText
                'Son Rebalance Donemi' = ConvertTo-PlainText $_.LastRebalancePeriodEnd
                'Sonraki' = ConvertTo-PlainText $_.NextRebalanceDate
                Durum = ConvertTo-PlainText $_.StatusNote
            }
        })

    # Kendini-ogrenen lider strateji: alfaya (yoksa getiriye) gore en iyi portfoy.
    $leaderPortfolio = @($updatedPortfolioSet.Portfolios |
            Sort-Object @{ Expression = {
                    $a = Get-ObjectPropertyValue -Object $_ -Name 'AlphaPct'
                    if ($null -ne $a) { [double]$a } else { [double](Get-ObjectPropertyValue -Object $_ -Name 'TotalReturnPct') }
                }; Descending = $true
            } | Select-Object -First 1)[0]
    $leaderText = if ($null -ne $leaderPortfolio) {
        $la = Get-ObjectPropertyValue -Object $leaderPortfolio -Name 'AlphaPct'
        if ($null -ne $la) {
            'Lider strateji (alfaya göre): {0} — alfa %{1}, getiri %{2}, BIST100 %{3}.' -f $leaderPortfolio.Name, $la, $leaderPortfolio.TotalReturnPct, (Get-ObjectPropertyValue -Object $leaderPortfolio -Name 'BenchmarkReturnPct')
        }
        else {
            'Lider strateji (getiriye göre; alfa için BIST100 verisi henüz birikmedi): {0} — getiri %{1}.' -f $leaderPortfolio.Name, $leaderPortfolio.TotalReturnPct
        }
    }
    else { 'Lider strateji henüz belirlenemedi.' }

    $stockLookupForReport = Get-StockLookup -Stocks $scored
    $portfolioHoldingRows = Get-ModelPortfolioHoldingRows -PortfolioSet $updatedPortfolioSet -StockMap $stockLookupForReport -RiskRules $riskRules
    $portfolioTransactionRows = Get-ModelPortfolioTransactionRows -PortfolioSet $updatedPortfolioSet -PerPortfolio 12
    $portfolioHoldingGroupsHtml = New-ModelPortfolioHoldingGroupsHtml -PortfolioSet $updatedPortfolioSet -HoldingRows $portfolioHoldingRows
    $portfolioDistributionPieHtml = New-ModelPortfolioDistributionPieChartsHtml -PortfolioSet $updatedPortfolioSet
    # Ay sonu Claude yorumu (varsa) — donem degisince uretilir, her gun gosterilir.
    $portfolioCommentaryHtml = ''
    $commentaryObj = Get-ObjectPropertyValue -Object $updatedPortfolioSet -Name 'MonthlyCommentary'
    if ($null -ne $commentaryObj) {
        $cText = [string](Get-ObjectPropertyValue -Object $commentaryObj -Name 'Text')
        if (-not [string]::IsNullOrWhiteSpace($cText)) {
            $cModel = [string](Get-ObjectPropertyValue -Object $commentaryObj -Name 'Model')
            $cPeriod = [string](Get-ObjectPropertyValue -Object $commentaryObj -Name 'Period')
            $cWhen = [string](Get-ObjectPropertyValue -Object $commentaryObj -Name 'GeneratedAtText')
            $cHtml = $cText.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') -replace '\r?\n', '<br>'
            $portfolioCommentaryHtml = @"
<h2>🤖 Ay Sonu Portföy Yorumu (Claude)</h2>
<p class="muted">$cPeriod ay sonu yeniden dengelemesinde portföy değişikliklerinin <b>$cModel</b> ile fon-yöneticisi gözüyle yorumu (üretim: $cWhen). Yalnızca ay sonu portföy değiştiğinde yenilenir. Yatırım tavsiyesi değildir.</p>
<div class="claude-commentary">$cHtml</div>
"@
        }
    }
    $instantEntryPortfolioSummaryRows = Get-InstantEntryPortfolioSummaryRows -Portfolio $updatedInstantEntryPortfolio
    $instantEntryPortfolioHoldingRows = Get-InstantEntryPortfolioHoldingRows -Portfolio $updatedInstantEntryPortfolio
    $instantEntryPortfolioTransactionRows = Get-InstantEntryPortfolioTransactionRows -Portfolio $updatedInstantEntryPortfolio -Count 30
    $orderIntentRows = @(Get-OrderIntentRows -OrderIntents $orderIntents)
    $paperBrokerPositionRows = @(Get-PaperBrokerPositionRows -PaperBroker $paperBroker)

    # --- Veri kalitesi (sessiz yanlis veri uyarisi) + portfoyler-arasi yogunlasma ---
    $dqInputs = [ordered]@{ 'BIST100 endeks' = $(if ($bist100Level -gt 0) { $bist100Level } else { $null }) }
    foreach ($m in @(Get-ObjectPropertyValue -Object $macroSnapshot -Name 'Metrics')) {
        $nm = [string](Get-ObjectPropertyValue -Object $m -Name 'Name')
        if (-not [string]::IsNullOrWhiteSpace($nm)) { $dqInputs[$nm] = (Get-ObjectPropertyValue -Object $m -Name 'Value') }
    }
    $stocksMissingFund = @($scored | Where-Object { $null -eq (Get-ObjectPropertyValue -Object $_ -Name 'PE') }).Count
    $dataQuality = Get-DataQualitySummary -Inputs $dqInputs -StocksMissingFundamentals $stocksMissingFund -TotalStocks @($scored).Count
    $dataQualityBanner = ''
    if ($dataQuality.Degraded) {
        $miss = if (@($dataQuality.MissingInputs).Count -gt 0) { 'Eksik kaynak: <b>' + ((@($dataQuality.MissingInputs)) -join ', ') + '</b>. ' } else { '' }
        $dataQualityBanner = '<div class="dq-warn">⚠️ <b>Veri kalitesi uyarısı.</b> ' + $miss + ('Makro/benchmark tamlık %{0}; temel verisi eksik hisse {1}/{2} (%{3}). Bu koşudaki skorlar ve alfa eksik veriden etkilenmiş olabilir; ihtiyatla okuyun.' -f $dataQuality.CompletenessPct, $dataQuality.StocksMissingFundamentals, $dataQuality.TotalStocks, $dataQuality.StaleRatioPct) + '</div>'
    }

    $crossConc = @(Get-CrossPortfolioConcentration -PortfolioSet $updatedPortfolioSet -WarnPct 12)
    $crossConcRows = @($crossConc | Where-Object { $_.PortfolioCount -gt 1 } | Select-Object -First 12 | ForEach-Object {
            [pscustomobject][ordered]@{
                Sembol = $_.Symbol
                Şirket = ConvertTo-PlainText $_.Company
                'Portföy Sayısı' = $_.PortfolioCount
                'Defter %' = Format-ReportNumber -Value $_.BookPct -Format 'N1' -Suffix '%'
                'Değer TL' = Format-ReportNumber -Value $_.ValueTL -Format 'N0'
                Durum = if ($_.Warn) { '⚠️ yüksek' } else { '' }
            }
        })
    $crossConcWarnCount = @($crossConc | Where-Object { $_.Warn }).Count

    $topRows | Export-Csv -Path $csvPath -NoTypeInformation -Delimiter ';' -Encoding UTF8

    $subjectPrefix = [string](Get-ConfigValue -Object $settings.Email -Name 'SubjectPrefix' -Default 'BIST Gunluk Rapor')
    $subject = '{0} - {1}' -f $subjectPrefix, $runAt.ToString('dd.MM.yyyy HH:mm')
    $leader = @($scored | Select-Object -First 1)[0]
    $telegramText = @(
        "BIST Gunluk Rapor - $($runAt.ToString('dd.MM.yyyy HH:mm'))",
        "Hisse sayisi: $($stocks.Count)",
        "Lider: $($leader.Symbol) | Skor $($leader.Score) | $($leader.Signal)",
        "Makro: $($macroSnapshot.Status)",
        "Skor isabet orani: " + $(if ($null -ne $signalPerfSummary.HitRatePct) { "%$($signalPerfSummary.HitRatePct) ($($signalPerfSummary.SampleCount) gun, ort. fark %$($signalPerfSummary.AvgEdgePct))" } else { 'henuz veri yok' }),
        "Anlik giris radari: " + $(if ($entryOpportunities.Count -gt 0) { (($entryOpportunities | ForEach-Object { "$($_.Symbol)($($_.EntryOpportunityScore))" }) -join ', ') } else { 'bugun uygun aday yok' }),
        "Anlik firsat portfoyu: $($updatedInstantEntryPortfolio.StatusNote) Toplam deger $($updatedInstantEntryPortfolio.TotalValueTL) TL (nakit $($updatedInstantEntryPortfolio.CashTL) + hisse $($updatedInstantEntryPortfolio.HoldingsValueTL)), getiri $($updatedInstantEntryPortfolio.TotalReturnPct)%",
        "Model portfoyler: " + ((@($updatedPortfolioSet.Portfolios) | ForEach-Object { "$($_.Strategy): " + ((@($_.Holdings) | ForEach-Object Symbol) -join ',') }) -join ' | '),
        "HTML rapor: $htmlPath"
    ) -join [Environment]::NewLine

    $css = @'
<style>
body { font-family: 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color:#0f172a; margin:0; padding:0; background:#e9eef5; -webkit-font-smoothing:antialiased; }
.wrap { max-width:1000px; margin:0 auto; background:#ffffff; box-shadow:0 6px 30px rgba(11,18,32,0.10); }
.mono { font-family:'Consolas','SF Mono','Roboto Mono',monospace; }
/* Masthead */
.masthead { background:#0b1220; background:linear-gradient(135deg,#0b1220 0%,#132744 58%,#1e466f 100%); color:#e8eef7; padding:28px 30px 24px; border-bottom:3px solid #c9a227; }
.mh-kicker { font-size:11px; letter-spacing:4px; text-transform:uppercase; color:#d6b34a; font-weight:700; }
.mh-title { font-size:27px; font-weight:800; margin:7px 0 3px; letter-spacing:.3px; }
.mh-sub { font-size:13px; color:#9fb3cc; }
.mh-badge { float:right; text-align:center; border:1px solid rgba(214,179,74,.45); border-radius:12px; padding:10px 14px; background:rgba(255,255,255,.04); }
.mh-badge .b1 { font-size:10px; letter-spacing:2px; color:#d6b34a; text-transform:uppercase; }
.mh-badge .b2 { font-size:22px; font-weight:800; color:#fff; }
.disclaim { display:inline-block; margin-top:12px; font-size:11px; color:#cbd5e1; background:rgba(255,255,255,.05); border:1px solid rgba(201,162,39,.35); padding:6px 11px; border-radius:7px; }
/* KPI tiles */
.kpi-row { padding:20px 30px 6px; background:#f4f7fb; border-bottom:1px solid #e2e8f0; }
.kpi { display:inline-block; vertical-align:top; width:175px; background:#fff; border:1px solid #e6ebf2; border-top:3px solid #1e466f; border-radius:11px; padding:13px 15px; margin:0 11px 14px 0; box-shadow:0 1px 3px rgba(15,23,42,.06); }
.kpi .lab { font-size:10.5px; text-transform:uppercase; letter-spacing:1px; color:#6b7a90; font-weight:700; }
.kpi .val { font-size:23px; font-weight:800; color:#0b1220; margin-top:4px; font-family:'Consolas','Roboto Mono',monospace; }
.kpi .sub { font-size:11px; color:#94a3b8; margin-top:3px; }
.kpi.good { border-top-color:#059669; } .kpi.bad { border-top-color:#dc2626; } .kpi.gold { border-top-color:#c9a227; }
.up { color:#059669; font-weight:700; } .down { color:#dc2626; font-weight:700; }
/* Sections */
.section { padding:4px 30px 8px; }
h1 { margin:0; }
h2 { margin:30px 0 3px; font-size:18px; color:#0b1220; border-left:4px solid #c9a227; padding-left:11px; }
.muted { color:#64748b; font-size:12.5px; line-height:1.5; }
.card { display:inline-block; vertical-align:top; border:1px solid #e2e8f0; border-radius:10px; padding:12px 16px; margin:8px 8px 8px 0; background:#f8fafc; }
.detail-card { border:1px solid #e2e8f0; border-left:4px solid #1e466f; border-radius:10px; padding:15px 17px; margin:14px 0; background:#ffffff; box-shadow:0 1px 3px rgba(15,23,42,0.05); }
.detail-card h3 { margin:0 0 4px 0; color:#0b1220; }
.detail-card h4 { margin:12px 0 4px 0; color:#1e466f; font-size:13px; text-transform:uppercase; letter-spacing:.5px; }
.detail-card ul { margin-top:4px; padding-left:20px; }
.detail-card li { margin:4px 0; }
.badge { display:inline-block; padding:4px 11px; border-radius:999px; background:#0b1220; color:#d6b34a; font-weight:700; font-size:11.5px; letter-spacing:.3px; border:1px solid #c9a227; }
.sym { color:#2563eb; text-decoration:none; font-weight:600; }
.clip-note { margin:10px 30px 0; padding:8px 12px; border-radius:7px; background:#fffbeb; border:1px solid #fde68a; color:#92400e; font-size:12px; }
.dq-warn { margin:10px 30px 0; padding:10px 14px; border-radius:7px; background:#fef2f2; border:1px solid #fecaca; color:#991b1b; font-size:12.5px; }
.claude-commentary { margin:6px 0 4px; padding:14px 16px; border-radius:9px; background:#f5f3ff; border:1px solid #ddd6fe; color:#312e81; font-size:13.5px; line-height:1.6; }
.portfolio-group { margin:18px 0 26px 0; }
.portfolio-group h3 { margin:0 0 4px 0; }
.pie-grid { font-size:0; margin-top:12px; }
.pie-card { display:inline-block; vertical-align:top; width:46%; min-width:280px; border:1px solid #e2e8f0; border-radius:10px; padding:13px; margin:0 1.5% 14px 0; background:#ffffff; box-shadow:0 1px 3px rgba(15,23,42,.05); }
.pie-card h3 { margin:0 0 10px 0; font-size:15px; color:#0b1220; }
.distbar { width:100%; border-collapse:separate; border-spacing:0; border-radius:6px; overflow:hidden; margin-bottom:10px; border:1px solid #e2e8f0; }
.distbar td { padding:0; border:0; }
.pie-legend { font-size:0; }
.pie-legend-item { display:inline-block; width:48%; font-size:12px; margin:2px 0; white-space:nowrap; }
.pie-legend-item span { display:inline; }
.pie-legend-item b { font-weight:700; margin-left:4px; }
.swatch { width:10px; height:10px; border-radius:2px; display:inline-block; margin-right:5px; vertical-align:middle; }
/* Tables - e-posta uyumlu: sabit yerlesim + kelime kirma (kesilmeyi onler) */
table { border-collapse:collapse; width:100%; table-layout:fixed; margin-top:10px; font-size:11px; background:#fff; border:1px solid #e6ebf2; border-radius:10px; }
th { background:#0b1220; color:#e8eef7; text-align:left; padding:7px 5px; font-size:10px; letter-spacing:.2px; text-transform:uppercase; font-weight:700; word-break:break-word; overflow-wrap:anywhere; }
td { border-bottom:1px solid #eef2f7; padding:6px 5px; vertical-align:top; word-break:break-word; overflow-wrap:anywhere; }
tr:nth-child(even) td { background:#f8fafc; }
.distbar td { word-break:normal; }
.warn { background:#0b1220; color:#cbd5e1; border:1px solid #c9a227; border-radius:11px; padding:15px 18px; font-size:12px; line-height:1.6; margin:24px 30px 30px; }
.warn b { color:#d6b34a; }
.footer { text-align:center; color:#94a3b8; font-size:11px; padding:14px 30px 26px; }
@media (max-width:760px) {
body { font-size:14px; }
.card, .kpi { display:block; width:auto; }
.mh-badge { float:none; display:inline-block; margin-top:12px; }
.pie-layout { grid-template-columns:96px 1fr; }
.pie-chart { width:96px; height:96px; }
table { display:block; overflow-x:auto; white-space:nowrap; }
}
</style>
'@
    # Getiri karsilastirma grafigi bolumu (grafik + ozet tablo). Grafik CID ile gomulur.
    $perfChartSectionHtml = ''
    if ($perfChartUrl -or @($perfSummaryRows).Count -gt 0) {
        $perfImgTag = if ($perfChartUrl) {
            "<img src=`"$perfChartUrl`" alt=`"Getiri karsilastirma grafigi`" width=`"860`" style=`"display:block;width:100%;max-width:860px;height:auto;margin:8px auto;border:1px solid #e6ebf2;border-radius:10px;`">"
        }
        else {
            '<p class="muted">Grafik gorseli bu sefer uretilemedi; asagidaki ozet tabloyu kullanin.</p>'
        }
        $perfRowsHtml = (@($perfSummaryRows) | ForEach-Object {
                $col = if ($_.ReturnPct -ge 0) { '#16a34a' } else { '#dc2626' }
                $nm = [System.Net.WebUtility]::HtmlEncode([string]$_.Name)
                "<tr><td>$nm</td><td style=`"text-align:right;color:$col;font-weight:700`">%$([Math]::Round($_.ReturnPct, 2))</td></tr>"
            }) -join "`n"
        $perfChartSectionHtml = @"
<div class="card" style="margin:24px 30px;">
<h2>📈 Getiri Karşılaştırması (100.000 TL)</h2>
<p class="muted">Tüm model portföyler + BIST100, Altın, Mevduat, Nasdaq, S&amp;P 500 — TRY bazında % getiri. Model portföylerin kuruluşundan bugüne; grafik her çalışmada otomatik uzar. Yabancı varlıklar ve altın USD/TRY ile TRY'ye çevrilmiştir; mevduat yaklaşıktır. <b>Aşağıdaki tablo</b> model portföyler ve BIST100 için <b>canlı (TradingView) değerleri</b> gösterir — model portföy detay tablosuyla birebir aynıdır. <b>Grafik çizgileri</b> günlük geçmiş için Yahoo kapanışından yeniden kurulur ve sağlayıcı/zaman farkıyla tablodan hafif sapabilir.</p>
$(if ($bistSourceWarning) { "<p class=`"muted`" style=`"color:#b45309`">$bistSourceWarning</p>" } else { '' })
$perfImgTag
<table><thead><tr><th>Strateji / Varlık</th><th style="text-align:right">Dönem getirisi</th></tr></thead><tbody>
$perfRowsHtml
</tbody></table>
</div>
"@
    }

    # FAZ A — Gözlem Göstergeleri bölümü (piyasa genişliği + RS liderleri + R:R).
    # Yalnız gözlem; skoru/portföyü/seçimi ETKİLEMEZ. Best-effort.
    $observationSectionHtml = ''
    try {
        $breadthHtml = ''
        if ($null -ne $marketBreadth -and $null -ne $marketBreadth.AboveSMA200Pct) {
            $breadthHtml = "<p>Piyasa genişliği: <b>$($marketBreadth.Label)</b> — evrenin <b>%$($marketBreadth.AboveSMA200Pct)</b>'i 200 günlük, <b>%$($marketBreadth.AboveSMA50Pct)</b>'i 50 günlük ortalamasının üzerinde; <b>%$($marketBreadth.PositiveMonthPct)</b>'i son ayda pozitif ($($marketBreadth.SampleCount) hisse). Dar genişlik kırılgan yükselişe, geniş genişlik sağlıklı katılıma işaret eder.</p>"
        }

        $rsLeaders = @($scored | Where-Object { $null -ne $_.RelativeStrengthRank } |
                Sort-Object @{ Expression = { [double]$_.RelativeStrengthRank }; Descending = $true } | Select-Object -First 10)
        $rsRowsHtml = (@($rsLeaders) | ForEach-Object {
                $nm = [System.Net.WebUtility]::HtmlEncode([string]$_.Symbol)
                $p3 = if ($null -ne $_.Perf3Month) { '%' + [Math]::Round([double]$_.Perf3Month, 1) } else { '—' }
                "<tr><td>$nm</td><td style=`"text-align:right;font-weight:700`">$([Math]::Round([double]$_.RelativeStrengthRank))</td><td style=`"text-align:right`">$p3</td></tr>"
            }) -join "`n"
        $rsBlock = if ($rsRowsHtml) {
            "<h3 style=`"margin:14px 0 4px;font-size:13px`">Göreli Güç (RS) Liderleri — BIST100'e göre en güçlü 10 hisse</h3><table><thead><tr><th>Hisse</th><th style=`"text-align:right`">RS (0-100)</th><th style=`"text-align:right`">3A getiri</th></tr></thead><tbody>$rsRowsHtml</tbody></table>"
        }
        else { '' }

        $rrRowsHtml = ''
        $stopPct = if ($null -ne $riskRules) { [double]$riskRules.StopLossPct } else { -8.0 }
        $seenRr = @{}
        foreach ($p in @(Get-ObjectPropertyValue -Object $updatedPortfolioSet -Name 'Portfolios')) {
            foreach ($h in @(Get-ObjectPropertyValue -Object $p -Name 'Holdings')) {
                $sym = [string]$h.Symbol
                if ([string]::IsNullOrWhiteSpace($sym) -or $seenRr.ContainsKey($sym)) { continue }
                $price = Get-ObjectPropertyValue -Object $h -Name 'CurrentPrice'
                if ($null -eq $price -or [double]$price -le 0) { continue }
                $price = [double]$price
                $series = @($priceCache[$sym])
                if ($series.Count -lt 20) { continue }
                $high52 = (@($series | ForEach-Object { [double]$_.Close }) | Measure-Object -Maximum).Maximum
                $stopPrice = $price * (1.0 + $stopPct / 100.0)
                $risk = $price - $stopPrice
                if ($risk -le 0) { continue }
                $reward = [Math]::Max(0.0, $high52 - $price)
                $rr = [Math]::Round($reward / $risk, 2)
                $seenRr[$sym] = $true
                $upPct = [Math]::Round((($high52 / $price) - 1.0) * 100.0, 1)
                $rrRowsHtml += "<tr><td>$([System.Net.WebUtility]::HtmlEncode($sym))</td><td style=`"text-align:right`">$([Math]::Round($price, 2))</td><td style=`"text-align:right`">$([Math]::Round($high52, 2))</td><td style=`"text-align:right`">%$upPct</td><td style=`"text-align:right;font-weight:700`">$rr</td></tr>`n"
            }
        }
        $rrBlock = if ($rrRowsHtml) {
            "<h3 style=`"margin:14px 0 4px;font-size:13px`">Risk/Ödül (R:R) — portföy pozisyonları</h3><p class=`"muted`">Risk = stop mesafesi (%$([Math]::Abs($stopPct))); Ödül = 52 hafta kapanış zirvesine uzaklık. R:R ≥ 2 tercih edilir.</p><table><thead><tr><th>Hisse</th><th style=`"text-align:right`">Fiyat</th><th style=`"text-align:right`">52h zirve</th><th style=`"text-align:right`">Yukarı</th><th style=`"text-align:right`">R:R</th></tr></thead><tbody>$rrRowsHtml</tbody></table>"
        }
        else { '' }

        if ($breadthHtml -or $rsBlock -or $rrBlock) {
            $observationSectionHtml = @"
<div class="card" style="margin:24px 30px;">
<h2>🔬 Gözlem Göstergeleri (deneysel — karar etkisi yok)</h2>
<p class="muted">Aşağıdaki üç gösterge <b>yalnız gözlem amaçlıdır</b>; skoru, portföy seçimini veya ağırlıkları DEĞİŞTİRMEZ. Veriler birikince hangisinin gerçekten ayrıştırıcı olduğu değerlendirilip karara bağlanacaktır.</p>
$breadthHtml
$rsBlock
$rrBlock
</div>
"@
        }
    }
    catch { Write-Warning "Gozlem gostergeleri bolumu uretilemedi: $($_.Exception.Message)" }
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
<div class="wrap">
<div class="masthead">
<div class="mh-badge"><div class="b1">BIST</div><div class="b2">$topCount</div></div>
<div class="mh-kicker">BORSA İSTANBUL · GÜNLÜK KANTİTATİF RAPOR</div>
<h1 class="mh-title">$subject</h1>
<div class="mh-sub mono">$($runAt.ToString('dd.MM.yyyy HH:mm')) · Strateji: $strategy · $($stocks.Count) hisse tarandı</div>
<div class="disclaim">⚠ Otomatik sayısal taramadır; yatırım tavsiyesi değildir.</div>
</div>
<div class="clip-note">📎 Bu e-posta, Gmail'in kırpma sınırının (~102 KB) altında kalmak için <b>özetlenmiştir</b>: bazı araştırma/denetim bölümleri (akademik faktör, bilanço öncesi ivme + PEAD, model portföy işlem geçmişi, paper broker) <b>ekteki tam HTML raporunda</b>. Hisse kodlarına tıklayınca Midas'ta açılır.</div>
$dataQualityBanner
<div class="kpi-row">
<div class="kpi gold"><div class="lab">Skor Lideri</div><div class="val">$($leader.Symbol)</div><div class="sub">Skor $($leader.Score) · $($leader.Signal)</div></div>
<div class="kpi"><div class="lab">Ham-Faktör Lideri</div><div class="val">$(($scored | Sort-Object RawFactorScore100 -Descending | Select-Object -First 1).Symbol)</div><div class="sub">RFS100 $(($scored | Sort-Object RawFactorScore100 -Descending | Select-Object -First 1).RawFactorScore100)</div></div>
<div class="kpi $(if ($macroSnapshot.Status -match 'destekleyici') { 'good' } elseif ($macroSnapshot.Status -match 'temkinli') { 'bad' } else { 'gold' })"><div class="lab">Makro Zemin</div><div class="val" style="font-size:15px">$($macroSnapshot.Status)</div><div class="sub">Destek $($macroSnapshot.SupportiveCount) · Baskı $($macroSnapshot.PressureCount)</div></div>
<div class="kpi $(if ([double]($updatedInstantEntryPortfolio.TotalReturnPct) -ge 0) { 'good' } else { 'bad' })"><div class="lab">Anlık Fırsat Portföyü</div><div class="val">%$($updatedInstantEntryPortfolio.TotalReturnPct)</div><div class="sub">Toplam $([string]::Format('{0:N0}', [double](Get-NumberValue -Object $updatedInstantEntryPortfolio -Name 'TotalValueTL'))) TL · nakit $([string]::Format('{0:N0}', [double](Get-NumberValue -Object $updatedInstantEntryPortfolio -Name 'CashTL'))) TL</div></div>
<div class="kpi"><div class="lab">Anlık Giriş Fırsatı</div><div class="val">$(@($entryOpportunities).Count)</div><div class="sub">bugünkü sinyal</div></div>
<div class="kpi $(if ($null -ne $signalPerfSummary.HitRatePct -and [double]$signalPerfSummary.HitRatePct -ge 50) { 'good' } elseif ($null -ne $signalPerfSummary.HitRatePct) { 'bad' } else { 'gold' })"><div class="lab">Skor İsabet Oranı</div><div class="val">$(if ($null -ne $signalPerfSummary.HitRatePct) { "%$($signalPerfSummary.HitRatePct)" } else { 'veri yok' })</div><div class="sub">$($signalPerfSummary.SampleCount) gün · ort. fark $(if ($null -ne $signalPerfSummary.AvgEdgePct) { "%$($signalPerfSummary.AvgEdgePct)" } else { '-' })</div></div>
</div>
<div class="section">
<h2>Makro Görünüm</h2>
<p class="muted">$($macroSnapshot.MeasurementNote)</p>
$(New-HtmlTable -Rows $macroRows)
<h2>Anlık Giriş Fırsatı</h2>
<p class="muted">Bu bölüm, temeli geçen hisselerde skor 85+ ve backtestte fake oranını düşüren teknik koşulu arar: MACD yeni sıfır kesişimi veya pozitif ivme + 52H %20-50 bandı. Liste sayısı sabit değildir; bugün koşul yoksa boş gelebilir.</p>
$(New-HtmlTable -Rows $entryOpportunityRows)
<h2>Anlık Fırsat Portföyü</h2>
<p class="muted">Bu portföy <b>kapalı döngü</b> çalışır: toplam <b>$([string]::Format('{0:N0}', $instantEntryPortfolioInitialCapitalTL)) TL</b> sermaye, günde en fazla <b>$([string]::Format('{0:N0}', $instantEntryPortfolioDailyBudgetTL)) TL</b> yeni alım. Her gün 18:15 kapanışında yalnızca çok güçlü sinyal varsa teorik alım yapar; risk kuralıyla (stop/kâr-al/iz-süren) pozisyon kapatır. <b>Satış hasılatı + kâr nakde döner</b> ve sonraki günlerde tekrar girişte kullanılabilir; <b>nakit bitince</b> (sermaye tamamen pozisyonlarda) yeni alım durur, bir satış nakit serbest bırakınca devam eder. Aynı gün tekrar çalışırsa ikinci kez alım yapmaz. Gerçek emir göndermez.</p>
$(New-HtmlTable -Rows $instantEntryPortfolioSummaryRows)
<h3>Anlık Fırsat Açık Pozisyonları</h3>
$(New-HtmlTable -Rows $instantEntryPortfolioHoldingRows)
<h3>Anlık Fırsat Alış Geçmişi</h3>
$(New-HtmlTable -Rows $instantEntryPortfolioTransactionRows)
<h2>Tüm Teyitli / Teknik Teyitli Adaylar</h2>
<p class="muted">Bu tablo, temel ve teknik bacakları birlikte güçlü olanları öne alır. Liste boş ise bugün tüm koşulları aynı anda sağlayan aday yok demektir; bu durumda kademeli giriş yerine teyit beklemek daha disiplinlidir.</p>
$(New-HtmlTable -Rows $confirmedRows)
<h2>Neden Güçlü İzlenir? Detaylı Hisse Notları</h2>
<p class="muted">Her kart Makro, Temel ve Teknik bacaklarini ayri okur. Teknik bolumde gunluk, haftalik ve aylik RSI/MACD degerleri ayrica yazilir.</p>
$detailedCardsHtml
<h2>Top $topCount Radar</h2>
<p class="muted">Veri kalitesi: $dqTotal hissenin $dqFlaggedCount tanesinde kritik veri sorunu (geçersiz fiyat / çok düşük likidite) işaretlendi; bunlar model portföy seçiminde elenir. Kalan alanlar geçerli veri akışından gelir.</p>
$(New-HtmlTable -Rows $topRows)
<h2>Skor İsabet Takibi (Öz-Değerlendirme)</h2>
<p class="muted">Bot, her çalışmada o günkü Top $topCount seçimini ve fiyatlarını saklar; bir sonraki çalışmada bu seçimlerin gerçekleşen getirisini tüm taranan evrenin ortalama getirisiyle karşılaştırır. <b>İsabet oranı</b>, seçimlerin evren ortalamasını geçtiği gün yüzdesidir; <b>ortalama fark (edge)</b> ise seçimlerin evrene kıyasla ortalama getiri üstünlüğüdür. Bu, skorlama mantığının zaman içinde gerçekten ayrıştırıcı olup olmadığını ölçen kendi kendine öğrenme/denetim sinyalidir. $(if ($null -ne $signalPerfSummary.HitRatePct) { "Şu ana kadar $($signalPerfSummary.SampleCount) değerlendirme gününde isabet oranı %$($signalPerfSummary.HitRatePct), ortalama fark %$($signalPerfSummary.AvgEdgePct)." } else { 'Henüz karşılaştırılacak önceki seçim yok; ilk isabet ölçümü bir sonraki çalışmada üretilecek.' })</p>
<!--EMAIL-DROP-START--><h2>Akademik Çok-Faktör Skoru (AFS)</h2>
<p class="muted">AFS, akademik literatürde getiriyi kesitsel olarak en tutarlı açıklayan faktörlerin standartlaştırılmış (z-skor) bir karışımıdır ve bağımsız bir beklenen-getiri sıralamasıdır (mevcut Skor'u değiştirmez). Bileşenler ve yönleri: <b>Momentum 12-1</b> (Jegadeesh-Titman 1993; son ay hariç 12 aylık getiri, kısa vadeli ters dönüşten arındırılmış), <b>Kalite</b> (Novy-Marx 2013 / Fama-French RMW; yüksek ROE, düşük borç, FAVÖK ardışık artışı), <b>Değer</b> (düşük FD/FAVÖK, PD/DD, F/K), <b>Düşük Volatilite</b> (Frazzini-Pedersen 2014; düşük volatilite primi) ve <b>Boyut</b> (küçük piyasa değeri hafif prim). Ağırlıklar momentum 0.30 · kalite 0.25 · değer 0.20 · düşük-vol 0.20 · boyut 0.05. "Getiri/Risk", momentum 12-1'in yıllıklandırılmış volatiliteye oranıdır (Sharpe benzeri). Tüm metrikler teoriktir; işlem maliyeti/kayma içermez.</p>
$(New-HtmlTable -Rows $academicRows)<!--EMAIL-DROP-END-->
<h2>USD Güçlü Bilanço</h2>
$(New-HtmlTable -Rows $strongUsdRows)
<h2>Yaklaşan Bilanço Takvimi</h2>
<p class="muted">Skora göre öne çıkan hisselerin bir sonraki bilanço/finansal rapor açıklama tarihi (TradingView takviminden; tahmini olabilir) ve son açıklanan bilanço tarihi. "Kalan Gün" 7 ve altındaysa olay riski yüksektir: bilanço öncesi oynaklık artar, kademeli giriş veya bilanço sonrası teyit beklemek daha disiplinlidir. Bilançoya 0-7 gün kalan hisselere skorda olay-riski cezası uygulanır. Açıklanan rakamlar bir sonraki taramada otomatik olarak skorlara yansır.</p>
$(New-HtmlTable -Rows $earningsCalendarRows)
<!--EMAIL-DROP-START--><h2>Bilanço Öncesi İvme Radarı (Anticipation)</h2>
<p class="muted">Geniş örneklemli olay çalışması (~1600 çeyrek-olayı) iyi bilanço gelen hisselerde açıklama öncesi ılımlı bir fiyat yükselişi (run-up) gösterir; etki ortalamada zayıftır (sürpriz↔ön run-up r≈0,08) ama yönü pozitiftir. Bu bölüm, bilançosuna 8-25 gün kalan ve fiyat/hacmi güçlenen (fiyat>SMA20≥SMA50, görece hacim≥1,1x, aylık getiri pozitif) hisseleri öncü aday olarak listeler ve skora bilanço öncesi bonus (+$([string]$activeCalibration.PreEarningsRunupBonus)) verir. Yeni açıklamış aşırı uzamış pozitif-sürpriz hisselere bilanço sonrası ayar ($([string]$activeCalibration.PostEarningsAdjustment)) uygulanır; geniş örneklemde bilanço sonrası eğilim hafif pozitif (PEAD, long-short ≈+%2,4) çıktığından bu ayar küçük tutulur ve canlı veriyle güncellenir. <b>Kendini öğrenen kalibrasyon:</b> $($activeCalibration.Note) Bu ayar, canlı PEAD takibi yeterli örnek biriktikçe ($(if ($activeCalibration.Calibrated) { 'şu an veriyle kalibre edilmiş durumda' } else { 'henüz tarihsel varsayılan; ~30 yönlü örnek sonrası otomatik kalibre olacak' })) veriye göre otomatik güncellenir.</p>
$(if ($preEarningsRows.Count -gt 0) { New-HtmlTable -Rows $preEarningsRows } else { '<p class="muted">Bugün bilanço öncesi ivme kriterini sağlayan hisse yok.</p>' })
<h2>Bilanço Sonrası Sürüklenme (PEAD) Takibi</h2>
<p class="muted">Akademik PEAD bulgusu (Bernard-Thomas 1989): hisseler bilanço sürprizinin yönünde haftalarca sürüklenir. Bot, yeni bilanço açıklayan hisseleri tespit anındaki fiyat ve sürpriz proxy'siyle (USD net kâr/FAVÖK Y/Y + FAVÖK <b>trendi</b>; 0-100, 50 nötr) kaydeder; <b>not:</b> gerçek analist konsensüsü ücretsiz veride olmadığından bu bir <b>trend-temelli vekildir</b>, klasik anlamda "konsensüs sürprizi" değildir; ~28 gün sonra tespit fiyatına göre getiriyi ölçer ve "pozitif sürpriz → pozitif sürüklenme" isabet oranını biriktirir. $(if ($null -ne $earningsReactionSummary.PeadHitRatePct) { "Şu ana kadar $($earningsReactionSummary.DirectionalCount) yönlü örnekte isabet %$($earningsReactionSummary.PeadHitRatePct); pozitif sürpriz ortalama sürüklenmesi %$($earningsReactionSummary.AvgPositiveSurpriseDriftPct). Halen izlenen $($earningsReactionSummary.TrackedCount) hisse." } else { "Henüz tamamlanmış sürüklenme örneği yok; halen izlenen $($earningsReactionSummary.TrackedCount) hisse. İlk isabet ölçümü açıklamalardan ~28 gün sonra üretilecek." })</p>
$(New-HtmlTable -Rows $peadTrackedRows)<!--EMAIL-DROP-END-->
<h2>KAP Son Gün Bildirimleri (Deneysel — gözlem)</h2>
<p class="muted">Kaynak: <b>$kapMeta</b>. Bildirimler ayrı bir işle (borsapy üzerinden BIST evreni için, dönüşümlü/biriktirerek) toplanıp depolanır; bu rapor <b>son gün</b> içindekileri gösterir. "Yorum" sütunu, izlenen (Top/portföy/anlık giriş) hisselerin önemli açıklamaları için <b>Claude (LLM) ile içerikten üretilmiş özet + etki skoru (1-5)</b>'dur; LLM yorumu olmayan satırlarda başlık görünür. Yön ikonu: 🟢 olumlu · 🔴 olumsuz · 🟡 karışık · ⚪ nötr · ❔ belirsiz. Piyasa mekaniği gürültüsü (devre kesici, likidite, endeks) elenir; Top radar hisseleri öne alınır. <b>Tümü otomatik; karar etkisi yoktur.</b> Özel durum açıklamaları işlem öncesi mutlaka KAP'tan birinci elden doğrulanmalıdır.</p>
$(if ($kapRows.Count -gt 0) { New-HtmlTable -Rows $kapRows } else { '<p class="muted">KAP bildirimleri bu çalışmada alınamadı (depolanmış dosya yok ve canlı kaynak erişilemedi).</p>' })
<h2>Sektor Rotasyonu</h2>
<p class="muted">Fark sütunları sektör endeksi/proxy getirisi eksi BIST100 getirisi olarak okunur. Pozitif değer sektörün BIST100'e göre daha güçlü aktığını gösterir.</p>
$(New-HtmlTable -Rows $sectorRows)
<h2>Model Portföyler</h2>
<p class="muted">Portföyler her çalışmada sadece değerlenir; ay sonu son işlem günü 18:10 sonrası tamamlanmış dönem varsa yeniden sıralanır ve AL/SAT/EŞİTLEME işlemleri state dosyasına yazılır. <b>Dengeli / Değer / Momentum / Kalite</b> portföyleri strateji skoruna (Get-BistScore) göre seçilir ve eşit ağırlıklı kalır. <b>RFS100</b> portföyü ise — backtest bulgusuna dayanarak — aynı uygunluk filtresini geçen hisseleri, eşik puanlaması yerine ham teknik faktörlerin kesitsel z-skor karışımı olan <b>RawFactorScore100</b> ile sıralayıp seçer. <b>Risk Dengeli</b> portföy ayrı izlenir: seçimi Dengeli skorla yapar ama ağırlıkları günlük oynaklık tersine göre dağıtır; normal model portföylerin ağırlığını değiştirmez. Her portföyün kuruluştan beri getirisi BIST100 ile kıyaslanır; <b>Alfa = portföy getirisi − BIST100 getirisi</b>. Tablo ayrıca <b>maksimum düşüşü</b> gösterir. Ay sonu işlemlerinde <b>işlem maliyeti + kayma</b> ($([string]$modelCostBps) bps) düşülür. <b>$leaderText</b></p>
$(New-HtmlTable -Rows $portfolioRows)
$portfolioCommentaryHtml
<h2>Model Portföy Hisse Dağılımı</h2>
<p class="muted">Her model portföydeki güncel hisse ağırlıkları pasta grafik olarak gösterilir.</p>
$portfolioDistributionPieHtml
<h2>Model Portföy Aktif Hisse Detayları</h2>
<p class="muted">İlk alış fiyatı işlem geçmişindeki ilk AL kaydından, satış fiyatı varsa ilk SAT/EŞİTLEME SAT kaydından gelir. Rebalance getirisi son portföy ayarlamasından bu yana, ilk alıştan getiri ilk AL fiyatına göre hesaplanır.</p>
$portfolioHoldingGroupsHtml
<!--EMAIL-DROP-START--><h2>Model Portföy Son İşlemler</h2>
<p class="muted">Her portföy için son 12 işlem gösterilir; ilk kurulum, AL, SAT ve ay sonu eşitleme kayıtları fiyat/adet/tutar/not alanlarıyla izlenir.</p>
$(New-HtmlTable -Rows $portfolioTransactionRows)
<h2>Portföyler-Arası Yoğunlaşma (gözlem)</h2>
<p class="muted">Aynı hissenin <b>6 model portföyün tamamı</b> üzerindeki toplam ağırlığı. Tek portföy içi sektör tavanı portföyler-arası örtüşmeyi görmez; bu tablo, bir ismin tüm defterdeki gizli yoğunlaşmasını izler. ⚠️ = defterin %12'sini aşan isim (tek bir şoka aşırı maruziyet riski).$(if ($crossConcWarnCount -gt 0) { " <b>$crossConcWarnCount isim eşiği aşıyor.</b>" })</p>
$(if ($crossConcRows.Count -gt 0) { New-HtmlTable -Rows $crossConcRows } else { '<p class="muted">Portföyler arası örtüşen isim yok.</p>' })
<h2>Emir Niyetleri (Kağıt — gerçek emir değildir)</h2>
<p class="muted">Bu bölüm gerçek emir değildir. Model portföy ve anlık fırsat portföyünün bu koşuda ürettiği teorik AL/SAT niyetlerini ayrı bir kağıt-broker defterine yazar; ileride aracı kurum entegrasyonu gerekirse execution katmanı bu niyet formatından beslenebilir.</p>
$(if ($orderIntentRows.Count -gt 0) { New-HtmlTable -Rows $orderIntentRows } else { '<p class="muted">Bu çalışmada yeni emir niyeti oluşmadı.</p>' })
<h2>Kağıt Broker Pozisyon Defteri</h2>
<p class="muted">Kağıt broker, emir niyeti kayıtlarını kağıt üzerinde doldurulmuş varsayan denetim defteridir; gerçek portföy veya emir sistemi değildir.</p>
$(if ($paperBrokerPositionRows.Count -gt 0) { New-HtmlTable -Rows $paperBrokerPositionRows } else { '<p class="muted">Kağıt broker defterinde açık pozisyon yok.</p>' })<!--EMAIL-DROP-END-->
</div>
$perfChartSectionHtml
$observationSectionHtml
<div class="warn">
<b>Karar mekanizması:</b> makro zemin (TCMB EVDS faiz/TÜFE + CDS/DXY/VIX) → sektör rotasyonu → bilanço gücü (USD bazlı) → çok-zamanlı teknik teyit → kademeli giriş. Buna ek olarak <b>RawFactorScore100</b> (kesitsel ham-faktör; backtestte botun ~2 katı IC) bağımsız bir sıralama sinyali olarak raporlanır.<br>
CDS, DXY, VIX izleme metrikleri ücretsiz/gecikmeli kaynaklardandır. İşlem kararı öncesi TCMB, Borsa İstanbul/MKK/KAP ve lisanslı veri kaynaklarıyla doğrulayın.
</div>
<div class="footer mono">BIST Kantitatif Rapor Motoru · $($runAt.ToString('yyyy-MM-dd HH:mm')) · otomatik üretildi · <a href="https://neccoju.github.io/bist-rapor-botu/" style="color:#6e8bff;text-decoration:none">Web panelinde aç →</a></div>
</div>
</body>
</html>
"@

    # Hisse kisaltmalarini Midas linkine cevir (yalniz gecerli sembol kumesi -> guvenli).
    $validSymbols = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($s in @($scored)) {
        $sy = ([string](Get-ObjectPropertyValue -Object $s -Name 'Symbol')).Trim().ToUpperInvariant()
        if ($sy) { [void]$validSymbols.Add($sy) }
    }
    $htmlBody = Add-MidasLinks -Html $htmlBody -Symbols $validSymbols

    # Gmail ~102 KB ustu HTML mailleri "kirpar" (tam icerik ekte kalir). Icerik
    # KAYBETMEDEN boyutu kucult: etiketler arasi girinti/satir-sonu bosluklarini sil
    # (metin ici bosluklar korunur). Bu ~%20-35 kazandirir, klipe takilmayi azaltir.
    $htmlBefore = $htmlBody.Length
    $htmlBody = [regex]::Replace($htmlBody, '>[ \t]*\r?\n[ \t]*<', '><')

    $stageStartedAt = Get-Date
    # TAM rapor (ek/arsiv) -> dosyaya yazilir; e-postaya giden sip surum ise
    # <!--EMAIL-DROP-START/END--> ile isaretli agir/dusuk-gunluk-deger bolumler
    # (akademik faktor, bilanco oncesi ivme + PEAD, islem gecmisi, paper broker)
    # cikarilarak Gmail klip sinirinin (~102 KB) altina indirilir. Tam icerik ekte.
    [IO.File]::WriteAllText($htmlPath, $htmlBody, [Text.UTF8Encoding]::new($true))
    $emailHtml = [regex]::Replace($htmlBody, '(?s)<!--EMAIL-DROP-START-->.*?<!--EMAIL-DROP-END-->',
        '<p class="muted">— Bu araştırma/denetim bölümü, e-posta boyutu için ekteki tam HTML raporuna taşındı.</p>')
    Write-Host ("HTML boyutu: tam {0:N0} bayt -> e-posta {1:N0} bayt (Gmail klip ~102.000)" -f $htmlBody.Length, $emailHtml.Length)
    Write-TimingLog -Step 'HTML rapor yazimi' -StartedAt $stageStartedAt

    $sendMessages = [System.Collections.Generic.List[string]]::new()
    if (-not $NoSend) {
        if ([bool](Get-ConfigValue -Object $settings.Send -Name 'EmailEnabled' -Default $false)) {
            $stageStartedAt = Get-Date
            Send-EmailReport -Settings $settings -Subject $subject -HtmlBody $emailHtml -HtmlPath $htmlPath -CsvPath $csvPath
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
    $hitRateText = if ($null -ne $signalPerfSummary.HitRatePct) { "$($signalPerfSummary.HitRatePct)% ($($signalPerfSummary.SampleCount)g)" } else { 'NA' }
    $result = "OK $($runAt.ToString('s')) | Hisse=$($stocks.Count) | Isabet=$hitRateText | HTML=$htmlPath | CSV=$csvPath | $($sendMessages -join ' ')"
    Add-Content -Path $logPath -Value $result -Encoding UTF8
    Write-Host $result
}
catch {
    $message = "ERROR $((Get-Date).ToString('s')) | $($_.Exception.Message)"
    try { Add-Content -Path $logPath -Value $message -Encoding UTF8 } catch { }

    # Sessiz basarisizligi gorunur kil: best-effort hata bildirimi gonder.
    if (-not $NoSend) {
        try {
            if ([bool](Get-ConfigValue -Object $settings.Send -Name 'EmailEnabled' -Default $false)) {
                $failSubjectPrefix = [string](Get-ConfigValue -Object $settings.Email -Name 'SubjectPrefix' -Default 'BIST Gunluk Rapor')
                $failSubject = '{0} - HATA - {1}' -f $failSubjectPrefix, (Get-Date).ToString('dd.MM.yyyy HH:mm')
                $failBody = @"
<p>BIST gunluk rapor uretimi basarisiz oldu.</p>
<p><b>Hata:</b> $([System.Net.WebUtility]::HtmlEncode([string]$_.Exception.Message))</p>
<p>Zaman: $((Get-Date).ToString('o'))</p>
<p>Ayrintilar icin GitHub Actions kayitlarini ve rapor log dosyasini kontrol edin.</p>
"@
                Send-EmailReport -Settings $settings -Subject $failSubject -HtmlBody $failBody -HtmlPath $htmlPath -CsvPath $csvPath
                try { Add-Content -Path $logPath -Value "INFO $((Get-Date).ToString('s')) | Hata bildirimi e-postasi gonderildi." -Encoding UTF8 } catch { }
            }
        }
        catch {
            try { Add-Content -Path $logPath -Value "WARN $((Get-Date).ToString('s')) | Hata bildirimi gonderilemedi: $($_.Exception.Message)" -Encoding UTF8 } catch { }
        }
    }

    Write-Error $message
    exit 1
}
