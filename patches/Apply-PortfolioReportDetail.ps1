Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$reportPath = Join-Path $repoRoot 'GunlukRapor.ps1'
$corePath = Join-Path $repoRoot 'BistScanner.Core.psm1'

if (-not (Test-Path $reportPath)) {
    throw "GunlukRapor.ps1 bulunamadi: $reportPath"
}
if (-not (Test-Path $corePath)) {
    throw "BistScanner.Core.psm1 bulunamadi: $corePath"
}

$text = Get-Content -Path $reportPath -Raw -Encoding UTF8
$coreText = Get-Content -Path $corePath -Raw -Encoding UTF8

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

if ($coreText -notmatch 'MaxElapsedSec') {
    $instantEntryFunction = @'
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

'@

    $coreText = Add-LiteralRegexReplacement `
        -InputText $coreText `
        -Pattern '(?s)(function Get-InvestingInstrumentSnapshot.*?\[int\]\$TimeoutSec = )20' `
        -Replacement 'function Get-InvestingInstrumentSnapshot {
    param(
        [string]$Id,
        [string]$Name,
        [string[]]$Urls,
        [string]$Unit = '''',
        [bool]$LowerIsBetter = $true,
        [int]$TimeoutSec = 6' `
        -Name 'macro investing timeout'

    $coreText = Add-LiteralRegexReplacement `
        -InputText $coreText `
        -Pattern '\s*\$IndexSnapshot = \$null,\r?\n\s*\[datetime\]\$AsOf = \(Get-Date\)' `
        -Replacement "        `$IndexSnapshot = `$null,`r`n        [datetime]`$AsOf = (Get-Date),`r`n        [int]`$TimeoutSec = 6" `
        -Name 'macro snapshot timeout parametresi'

    $coreText = Add-LiteralRegexReplacement `
        -InputText $coreText `
        -Pattern '(?m)^        \$IndexSnapshot = Get-BistIndexBenchmarks$' `
        -Replacement '        $IndexSnapshot = Get-BistIndexBenchmarks -TimeoutSec $TimeoutSec' `
        -Name 'macro bist timeout'

    $coreText = Add-LiteralRegexReplacement `
        -InputText $coreText `
        -Pattern '(?m)^            -LowerIsBetter \$instrument\.LowerIsBetter$' `
        -Replacement ("            -LowerIsBetter `$instrument.LowerIsBetter " + '`' + [Environment]::NewLine + "            -TimeoutSec `$TimeoutSec") `
        -Name 'macro investing timeout kullanimi'

    $coreText = Add-LiteralRegexReplacement `
        -InputText $coreText `
        -Pattern '(?s)function Get-InstantEntryOpportunities \{.*?\r?\n\}\r?\n\r?\nfunction Get-ModelPortfolioDefinitions' `
        -Replacement ($instantEntryFunction + 'function Get-ModelPortfolioDefinitions') `
        -Name 'anlik giris fonksiyon limiti'
}

if ($text -match 'Send-MailMessage @mailParams') {
    $emailSendBlock = @'
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
'@

    $text = Add-LiteralRegexReplacement `
        -InputText $text `
        -Pattern '(?s)    \$mailParams = @\{.*?    Send-MailMessage @mailParams' `
        -Replacement $emailSendBlock `
        -Name 'smtp timeout gonderimi'
}

if ($text -notmatch 'function Write-TimingLog') {
    $timingBlock = @'
function Write-TimingLog {
    param(
        [string]$Step,
        [datetime]$StartedAt
    )

    $elapsed = [Math]::Round(((Get-Date) - $StartedAt).TotalSeconds, 1)
    Write-Host ("[timing] {0}: {1:N1}s" -f $Step, $elapsed)
}

'@

    $text = Add-LiteralRegexReplacement `
        -InputText $text `
        -Pattern '(?m)^\$settings = Load-ReportSettings' `
        -Replacement ($timingBlock + '$settings = Load-ReportSettings') `
        -Name 'timing helper'
}

if ($text -notmatch 'InstantEntryMaxElapsedSec') {
    $text = Add-LiteralRegexReplacement `
        -InputText $text `
        -Pattern '(?m)^\$detailedCount = \[int\]\(Get-ConfigValue -Object \$settings\.Report -Name ''DetailedCount'' -Default [0-9]+\)$' `
        -Replacement "`$detailedCount = [int](Get-ConfigValue -Object `$settings.Report -Name 'DetailedCount' -Default 5)`r`n`$macroTimeoutSec = [int](Get-ConfigValue -Object `$settings.Report -Name 'MacroTimeoutSec' -Default 6)`r`n`$instantEntryCandidateLimit = [int](Get-ConfigValue -Object `$settings.Report -Name 'InstantEntryCandidateLimit' -Default 40)`r`n`$instantEntryTimeoutSec = [int](Get-ConfigValue -Object `$settings.Report -Name 'InstantEntryTimeoutSec' -Default 5)`r`n`$instantEntryMaxElapsedSec = [int](Get-ConfigValue -Object `$settings.Report -Name 'InstantEntryMaxElapsedSec' -Default 75)" `
        -Name 'rapor performans ayarlari'
}

if ($text -notmatch 'Canli BIST taramasi') {
    $text = Add-LiteralRegexReplacement `
        -InputText $text `
        -Pattern '(?m)^try \{\r?\n    \$stocks = @\(Invoke-BistStockScan\)' `
        -Replacement "try {`r`n    `$reportStartedAt = Get-Date`r`n    `$stageStartedAt = Get-Date`r`n    `$stocks = @(Invoke-BistStockScan)`r`n    Write-TimingLog -Step 'Canli BIST taramasi' -StartedAt `$stageStartedAt" `
        -Name 'bist tarama timing'

    $text = Add-LiteralRegexReplacement `
        -InputText $text `
        -Pattern '(?m)^    \$scored = @\(Get-BistScores -Stocks \$stocks -Strategy \$strategy \| Sort-Object Score -Descending\)$' `
        -Replacement "    `$stageStartedAt = Get-Date`r`n    `$scored = @(Get-BistScores -Stocks `$stocks -Strategy `$strategy | Sort-Object Score -Descending)`r`n    Write-TimingLog -Step 'Skorlama' -StartedAt `$stageStartedAt" `
        -Name 'skorlama timing'

    $text = Add-LiteralRegexReplacement `
        -InputText $text `
        -Pattern '(?m)^    \$macroSnapshot = Get-MacroSnapshot -AsOf \$runAt$' `
        -Replacement "    `$stageStartedAt = Get-Date`r`n    `$macroSnapshot = Get-MacroSnapshot -AsOf `$runAt -TimeoutSec `$macroTimeoutSec`r`n    Write-TimingLog -Step 'Makro gorunum' -StartedAt `$stageStartedAt" `
        -Name 'makro timing'

    $entryBlock = @'
    $stageStartedAt = Get-Date
    $entryOpportunities = @(Get-InstantEntryOpportunities `
            -Stocks $scored `
            -CandidateLimit $instantEntryCandidateLimit `
            -TimeoutSec $instantEntryTimeoutSec `
            -MaxElapsedSec $instantEntryMaxElapsedSec)
    Write-TimingLog -Step 'Anlik giris firsati' -StartedAt $stageStartedAt
'@
    $text = Add-LiteralRegexReplacement `
        -InputText $text `
        -Pattern '(?m)^    \$entryOpportunities = @\(Get-InstantEntryOpportunities -Stocks \$scored -CandidateLimit 120\)$' `
        -Replacement $entryBlock `
        -Name 'anlik giris timing ve limit'

    $text = Add-LiteralRegexReplacement `
        -InputText $text `
        -Pattern '(?m)^    \[IO\.File\]::WriteAllText\(\$htmlPath, \$htmlBody, \[Text\.UTF8Encoding\]::new\(\$true\)\)$' `
        -Replacement "    `$stageStartedAt = Get-Date`r`n    [IO.File]::WriteAllText(`$htmlPath, `$htmlBody, [Text.UTF8Encoding]::new(`$true))`r`n    Write-TimingLog -Step 'HTML rapor yazimi' -StartedAt `$stageStartedAt" `
        -Name 'html timing'

    $text = Add-LiteralRegexReplacement `
        -InputText $text `
        -Pattern '(?m)^            Send-EmailReport -Settings \$settings -Subject \$subject -HtmlBody \$htmlBody -HtmlPath \$htmlPath -CsvPath \$csvPath$' `
        -Replacement "            `$stageStartedAt = Get-Date`r`n            Send-EmailReport -Settings `$settings -Subject `$subject -HtmlBody `$htmlBody -HtmlPath `$htmlPath -CsvPath `$csvPath`r`n            Write-TimingLog -Step 'E-posta gonderimi' -StartedAt `$stageStartedAt" `
        -Name 'email timing'

    $text = Add-LiteralRegexReplacement `
        -InputText $text `
        -Pattern '(?m)^            Send-TelegramSummary -Settings \$settings -Text \$telegramText$' `
        -Replacement "            `$stageStartedAt = Get-Date`r`n            Send-TelegramSummary -Settings `$settings -Text `$telegramText`r`n            Write-TimingLog -Step 'Telegram gonderimi' -StartedAt `$stageStartedAt" `
        -Name 'telegram timing'

    $text = Add-LiteralRegexReplacement `
        -InputText $text `
        -Pattern '(?m)^    \$result = "OK \$\(\$runAt\.ToString\(''s''\)\)' `
        -Replacement "    Write-TimingLog -Step 'Toplam rapor suresi' -StartedAt `$reportStartedAt`r`n    `$result = `"OK `$(`$runAt.ToString('s'))" `
        -Name 'toplam timing'
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

[IO.File]::WriteAllText($corePath, $coreText, [Text.UTF8Encoding]::new($true))
[IO.File]::WriteAllText($reportPath, $text, [Text.UTF8Encoding]::new($true))
Write-Host "Report overlay applied to $reportPath and $corePath"
