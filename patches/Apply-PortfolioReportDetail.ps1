Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$reportPath = Join-Path $repoRoot 'GunlukRapor.ps1'

if (-not (Test-Path $reportPath)) {
    throw "GunlukRapor.ps1 bulunamadi: $reportPath"
}

$text = Get-Content -Path $reportPath -Raw -Encoding UTF8

function Add-LiteralRegexReplacement {
    param(
        [string]$InputText,
        [string]$Pattern,
        [string]$Replacement,
        [string]$Name
    )

    if (-not [regex]::IsMatch($InputText, $Pattern)) {
        throw "$Name icin hedef blok bulunamadi."
    }

    return [regex]::Replace(
        $InputText,
        $Pattern,
        [Text.RegularExpressions.MatchEvaluator] { param($match) $Replacement },
        1
    )
}

if ($text -notmatch 'function Get-ModelPortfolioHoldingRows') {
    $helperBlock = @'
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

'@

    $text = Add-LiteralRegexReplacement `
        -InputText $text `
        -Pattern '(?m)^function Save-JsonFile \{' `
        -Replacement ($helperBlock + [Environment]::NewLine + 'function Save-JsonFile {') `
        -Name 'portfoy yardimci fonksiyonlari'
}

if ($text -notmatch '\$portfolioHoldingRows = Get-ModelPortfolioHoldingRows') {
    $portfolioRowsBlock = @'
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

    $topRows | Export-Csv
'@

    $text = Add-LiteralRegexReplacement `
        -InputText $text `
        -Pattern '(?s)    \$portfolioRows = @\(\$updatedPortfolioSet\.Portfolios \| ForEach-Object \{.*?    \$topRows \| Export-Csv' `
        -Replacement $portfolioRowsBlock `
        -Name 'portfoy satir bloklari'
}

if ($text -notmatch '<h2>Model Portfoy Aktif Hisse Detaylari</h2>') {
    $modelPortfolioHtml = @'
<h2>Model Portfoyler</h2>
<p class="muted">Portföyler her çalışmada sadece değerlenir; ay sonu son işlem günü 18:10 sonrası tamamlanmış dönem varsa yeniden sıralanır ve AL/SAT/EŞİTLEME işlemleri state dosyasına yazılır.</p>
$(New-HtmlTable -Rows $portfolioRows)
<h2>Model Portfoy Aktif Hisse Detaylari</h2>
<p class="muted">İlk alış fiyatı işlem geçmişindeki ilk AL kaydından, satış fiyatı varsa ilk SAT/EŞİTLEME SAT kaydından gelir. Rebalance getirisi son portföy ayarlamasından bu yana, ilk alıştan getiri ilk AL fiyatına göre hesaplanır.</p>
$(New-HtmlTable -Rows $portfolioHoldingRows)
<h2>Model Portfoy Son Islemler</h2>
<p class="muted">Her portföy için son 12 işlem gösterilir; ilk kurulum, AL, SAT ve ay sonu eşitleme kayıtları fiyat/adet/tutar/not alanlarıyla izlenir.</p>
$(New-HtmlTable -Rows $portfolioTransactionRows)
'@

    $text = Add-LiteralRegexReplacement `
        -InputText $text `
        -Pattern '<h2>Model Portfoyler</h2>\r?\n\$\((New-HtmlTable -Rows \$portfolioRows)\)' `
        -Replacement $modelPortfolioHtml `
        -Name 'portfoy html bloklari'
}

[IO.File]::WriteAllText($reportPath, $text, [Text.UTF8Encoding]::new($true))
Write-Host "Portfolio detail overlay applied to $reportPath"