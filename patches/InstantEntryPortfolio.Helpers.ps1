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

function Update-InstantEntrySignalPortfolio {
    param(
        $Portfolio,
        [object[]]$Opportunities,
        [object[]]$Stocks,
        [datetime]$AsOf,
        [double]$DailyBudgetTL = 5000,
        [double]$MinBuyScore = 90,
        [int]$MaxBuysPerDay = 3
    )

    $stockMap = Get-StockLookup -Stocks $Stocks
    $holdingsBySymbol = @{}
    $transactions = [System.Collections.Generic.List[object]]::new()

    if ($null -ne $Portfolio) {
        foreach ($transaction in @(Get-ObjectPropertyValue -Object $Portfolio -Name 'Transactions')) {
            [void]$transactions.Add($transaction)
        }

        foreach ($holding in @(Get-ObjectPropertyValue -Object $Portfolio -Name 'Holdings')) {
            $symbol = [string](Get-ObjectPropertyValue -Object $holding -Name 'Symbol')
            if ([string]::IsNullOrWhiteSpace($symbol)) { continue }

            $stock = if ($stockMap.ContainsKey($symbol)) { $stockMap[$symbol] } else { $null }
            $freshPrice = Get-NumberValue -Object $stock -Name 'Price'
            $storedPrice = Get-NumberValue -Object $holding -Name 'CurrentPrice'
            $priceIsFresh = $null -ne $freshPrice -and $freshPrice -gt 0
            $currentPrice = if ($priceIsFresh) {
                [double]$freshPrice
            }
            elseif ($null -ne $storedPrice -and $storedPrice -gt 0) {
                [double]$storedPrice
            }
            else {
                0.0
            }

            $quantity = Get-NumberValue -Object $holding -Name 'Quantity'
            $costBasis = Get-NumberValue -Object $holding -Name 'CostBasisTL'
            if ($null -eq $quantity) { $quantity = 0.0 }
            if ($null -eq $costBasis) { $costBasis = 0.0 }

            $currentValue = [double]$quantity * [double]$currentPrice
            $gain = $currentValue - [double]$costBasis
            $gainPct = if ([double]$costBasis -gt 0) { ($gain / [double]$costBasis) * 100.0 } else { 0.0 }
            $averageBuyPrice = if ([double]$quantity -gt 0) { [double]$costBasis / [double]$quantity } else { $null }

            $holdingsBySymbol[$symbol] = [pscustomobject][ordered]@{
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
                FirstBuyAt = Get-ObjectPropertyValue -Object $holding -Name 'FirstBuyAt'
                FirstBuyAtText = Get-ObjectPropertyValue -Object $holding -Name 'FirstBuyAtText'
                LastBuyAt = Get-ObjectPropertyValue -Object $holding -Name 'LastBuyAt'
                LastBuyAtText = Get-ObjectPropertyValue -Object $holding -Name 'LastBuyAtText'
                BuyCount = Get-ObjectPropertyValue -Object $holding -Name 'BuyCount'
                LastSignalScore = Get-ObjectPropertyValue -Object $holding -Name 'LastSignalScore'
                LastSignalLabel = Get-ObjectPropertyValue -Object $holding -Name 'LastSignalLabel'
                LastReason = Get-ObjectPropertyValue -Object $holding -Name 'LastReason'
                PriceIsFresh = $priceIsFresh
            }
        }
    }

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

    $lastBuyDate = Get-ObjectPropertyValue -Object $Portfolio -Name 'LastBuyDate'
    $lastBuyDateText = Get-ObjectPropertyValue -Object $Portfolio -Name 'LastBuyDateText'
    $statusNote = ''

    if ($alreadyBoughtToday) {
        $statusNote = 'Bugün bu portföy için daha önce alım kaydı oluştu; tekrar 5.000 TL kullanılmadı.'
    }
    else {
        $maxBuys = [Math]::Max(1, [Math]::Min(3, $MaxBuysPerDay))
        $buyCandidates = @(
            @($Opportunities) |
                Where-Object { Test-InstantEntryPortfolioBuyCandidate -Opportunity $_ -MinScore $MinBuyScore } |
                Sort-Object @{ Expression = { Get-NumberValue -Object $_ -Name 'EntryOpportunityScore' }; Descending = $true } |
                Select-Object -First $maxBuys
        )

        if ($buyCandidates.Count -eq 0) {
            $statusNote = ('Bugün çok güçlü anlık giriş sinyali yok; {0:N0} TL günlük alım hakkı kullanılmadı.' -f $DailyBudgetTL)
        }
        else {
            $sequence = $transactions.Count + 1
            $remainingBudget = [Math]::Round($DailyBudgetTL, 2)
            $boughtSymbols = [System.Collections.Generic.List[string]]::new()

            for ($index = 0; $index -lt $buyCandidates.Count; $index++) {
                $candidate = $buyCandidates[$index]
                $symbol = [string](Get-ObjectPropertyValue -Object $candidate -Name 'Symbol')
                $price = Get-NumberValue -Object $candidate -Name 'Price'
                if ([string]::IsNullOrWhiteSpace($symbol) -or $null -eq $price -or $price -le 0) { continue }

                $amount = if ($index -eq ($buyCandidates.Count - 1)) {
                    $remainingBudget
                }
                else {
                    [Math]::Round($DailyBudgetTL / $buyCandidates.Count, 2)
                }
                $remainingBudget = [Math]::Round($remainingBudget - $amount, 2)
                if ($amount -le 0) { continue }

                $existing = if ($holdingsBySymbol.ContainsKey($symbol)) { $holdingsBySymbol[$symbol] } else { $null }
                $oldQuantity = Get-NumberValue -Object $existing -Name 'Quantity'
                $oldCost = Get-NumberValue -Object $existing -Name 'CostBasisTL'
                $oldBuyCount = Get-ObjectPropertyValue -Object $existing -Name 'BuyCount'
                if ($null -eq $oldQuantity) { $oldQuantity = 0.0 }
                if ($null -eq $oldCost) { $oldCost = 0.0 }
                if ($null -eq $oldBuyCount -or [string]::IsNullOrWhiteSpace([string]$oldBuyCount)) { $oldBuyCount = 0 }

                $quantity = [double]$amount / [double]$price
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

                $company = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $candidate -Name 'Company')
                $sector = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $candidate -Name 'SectorTR')
                $score = Get-NumberValue -Object $candidate -Name 'EntryOpportunityScore'
                $label = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $candidate -Name 'WeeklyHistogramLabel')
                $reason = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $candidate -Name 'Reason')

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
                $lastBuyDate = $todayKey
                $lastBuyDateText = $AsOf.ToString('dd.MM.yyyy HH:mm')
            }
            else {
                $statusNote = ('Aday bulundu ama fiyat/sembol eksikliği nedeniyle {0:N0} TL günlük alım hakkı kullanılmadı.' -f $DailyBudgetTL)
            }
        }
    }

    $finalHoldings = [System.Collections.Generic.List[object]]::new()
    $totalInvested = 0.0
    $totalValue = 0.0
    foreach ($holding in @($holdingsBySymbol.Values | Sort-Object CurrentValueTL -Descending)) {
        $cost = Get-NumberValue -Object $holding -Name 'CostBasisTL'
        $value = Get-NumberValue -Object $holding -Name 'CurrentValueTL'
        if ($null -eq $cost) { $cost = 0.0 }
        if ($null -eq $value) { $value = 0.0 }
        $totalInvested += [double]$cost
        $totalValue += [double]$value
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

    $totalGain = $totalValue - $totalInvested
    $totalReturnPct = if ($totalInvested -gt 0) { ($totalGain / $totalInvested) * 100.0 } else { 0.0 }
    $createdAt = Get-ObjectPropertyValue -Object $Portfolio -Name 'CreatedAt'
    if ($null -eq $createdAt -or [string]::IsNullOrWhiteSpace([string]$createdAt)) {
        $createdAt = $AsOf.ToString('o')
    }

    return [pscustomobject][ordered]@{
        Version = 1
        CreatedAt = $createdAt
        UpdatedAt = $AsOf.ToString('o')
        LastValuationAt = $AsOf.ToString('o')
        LastValuationAtText = $AsOf.ToString('dd.MM.yyyy HH:mm')
        DailyBudgetTL = [Math]::Round($DailyBudgetTL, 2)
        MinBuyScore = [Math]::Round($MinBuyScore, 1)
        MaxBuysPerDay = $MaxBuysPerDay
        TotalInvestedTL = [Math]::Round($totalInvested, 2)
        CurrentValueTL = [Math]::Round($totalValue, 2)
        TotalGainTL = [Math]::Round($totalGain, 2)
        TotalReturnPct = [Math]::Round($totalReturnPct, 2)
        LastBuyDate = $lastBuyDate
        LastBuyDateText = $lastBuyDateText
        StatusNote = $statusNote
        Notes = 'Anlık giriş fırsatı portföyü teorik modeldir. Her gün 18:15 kapanış taramasında yalnızca çok güçlü sinyal varsa günlük bütçe ile alım kaydı oluşturur; gerçek emir göndermez.'
        Holdings = $finalHoldings.ToArray()
        Transactions = $transactions.ToArray()
    }
}

function Get-InstantEntryPortfolioSummaryRows {
    param($Portfolio)

    return @(
        [pscustomobject][ordered]@{
            'Günlük Alım Hakkı' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $Portfolio -Name 'DailyBudgetTL') -Format 'N2' -Suffix ' TL'
            'Minimum Sinyal Skoru' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $Portfolio -Name 'MinBuyScore') -Format 'N1'
            'Toplam Yatırım' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $Portfolio -Name 'TotalInvestedTL') -Format 'N2' -Suffix ' TL'
            'Güncel Değer' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $Portfolio -Name 'CurrentValueTL') -Format 'N2' -Suffix ' TL'
            'Açık Kar/Zarar' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $Portfolio -Name 'TotalGainTL') -Format 'N2' -Suffix ' TL'
            'Getiri' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $Portfolio -Name 'TotalReturnPct') -Format 'N2' -Suffix '%'
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
                'Şirket' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Company')
                'Sektör' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'SectorTR')
                Adet = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'Quantity') -Format 'N4'
                'Ort. Maliyet' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'AverageBuyPrice') -Format 'N2' -Suffix ' TL'
                'Güncel Fiyat' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'CurrentPrice') -Format 'N2' -Suffix ' TL'
                Maliyet = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'CostBasisTL') -Format 'N2' -Suffix ' TL'
                'Güncel Değer' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'CurrentValueTL') -Format 'N2' -Suffix ' TL'
                'Ağırlık' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'WeightPct') -Format 'N2' -Suffix '%'
                'Anlık Getiri' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'UnrealizedGainPct') -Format 'N2' -Suffix '%'
                'Alım Sayısı' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'BuyCount')
                'İlk Alım' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'FirstBuyAtText')
                'Son Alım' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'LastBuyAtText')
                'Son Sinyal' = Format-ReportNumber -Value (Get-ObjectPropertyValue -Object $_ -Name 'LastSignalScore') -Format 'N1'
                Etiket = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'LastSignalLabel')
                'Gerekçe' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'LastReason')
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
                    'Sıra' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Sequence')
                    Tarih = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'ExecutionDateText')
                    'İşlem' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Action')
                    Sembol = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Symbol')
                    'Şirket' = ConvertTo-PlainText (Get-ObjectPropertyValue -Object $_ -Name 'Company')
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
