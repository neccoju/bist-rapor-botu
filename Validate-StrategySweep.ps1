#requires -Version 5.1
<#
    Parametre taramasi icin manuel validation runner.
    Gunluk raporu veya state dosyalarini degistirmez; Backtest-Realistic.ps1'i
    sinirli kombinasyonlarla kosturup markdown + JSON ozet uretir.
#>
param(
    [datetime]$StartDate = ([datetime]'2024-09-01'),
    [string]$TopNList = '5,7',
    [string]$CostBpsList = '20,50',
    [string]$MinAdvTlList = '3000000',
    [int]$MaxStocks = 180,
    [int]$MaxElapsedSec = 420,
    [string]$OutputDirectory = 'reports'
)

$ErrorActionPreference = 'Stop'

function Split-NumberList {
    param(
        [string]$Text,
        [ValidateSet('Int', 'Double')]
        [string]$Type = 'Int'
    )

    return @(
        $Text -split '[,; ]+' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object {
                if ($Type -eq 'Int') { [int]$_ } else { [double]$_ }
            }
    )
}

function Get-RegexValue {
    param(
        [string[]]$Lines,
        [string]$Pattern,
        [int]$Group = 1
    )

    foreach ($line in $Lines) {
        $match = [regex]::Match($line, $Pattern)
        if ($match.Success) {
            return $match.Groups[$Group].Value
        }
    }

    return $null
}

$topNs = Split-NumberList -Text $TopNList -Type Int
$costs = Split-NumberList -Text $CostBpsList -Type Double
$minAdvs = Split-NumberList -Text $MinAdvTlList -Type Double

$outDir = if ([IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory } else { Join-Path $PSScriptRoot $OutputDirectory }
if (-not (Test-Path -LiteralPath $outDir)) {
    [void](New-Item -ItemType Directory -Path $outDir -Force)
}

$startedAt = Get-Date
$results = [System.Collections.Generic.List[object]]::new()
$backtestPath = Join-Path $PSScriptRoot 'Backtest-Realistic.ps1'

foreach ($topN in $topNs) {
    foreach ($cost in $costs) {
        foreach ($minAdv in $minAdvs) {
            $comboName = 'TopN={0}, CostBps={1}, MinAdvTl={2:N0}' -f $topN, $cost, $minAdv
            Write-Host "=== Validation combo: $comboName ==="
            $comboStarted = Get-Date
            $status = 'Passed'
            $outputLines = @()
            try {
                $outputLines = @(& $backtestPath `
                        -StartDate $StartDate `
                        -TopN $topN `
                        -MaxStocks $MaxStocks `
                        -CostBps $cost `
                        -MinAdvTl $minAdv `
                        -MaxElapsedSec $MaxElapsedSec 2>&1 | ForEach-Object { [string]$_ })
                $outputLines | ForEach-Object { Write-Host $_ }
            }
            catch {
                $status = 'Failed'
                $outputLines += [string]$_.Exception.Message
                Write-Warning "Combo failed: $($_.Exception.Message)"
            }

            $results.Add([pscustomobject][ordered]@{
                    Combo = $comboName
                    Status = $status
                    TopN = $topN
                    CostBps = $cost
                    MinAdvTl = $minAdv
                    StartedAt = $comboStarted.ToString('o')
                    ElapsedSec = [Math]::Round(((Get-Date) - $comboStarted).TotalSeconds, 1)
                    StrategyReturnPct = Get-RegexValue -Lines $outputLines -Pattern 'getiri %([-0-9,\.]+)' -Group 1
                    AlphaPct = Get-RegexValue -Lines $outputLines -Pattern 'ALFA: %([-0-9,\.]+)' -Group 1
                    MaxDrawdownPct = Get-RegexValue -Lines $outputLines -Pattern 'maks dusus %([-0-9,\.]+)' -Group 1
                    Tail = @($outputLines | Select-Object -Last 24)
                })
        }
    }
}

$summary = [pscustomobject][ordered]@{
    Version = 1
    StartedAt = $startedAt.ToString('o')
    FinishedAt = (Get-Date).ToString('o')
    StartDate = $StartDate.ToString('yyyy-MM-dd')
    MaxStocks = $MaxStocks
    MaxElapsedSec = $MaxElapsedSec
    Results = $results.ToArray()
}

$jsonPath = Join-Path $outDir 'strategy_validation.json'
$mdPath = Join-Path $outDir 'strategy_validation.md'
[IO.File]::WriteAllText($jsonPath, ($summary | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($true))

$md = [System.Collections.Generic.List[string]]::new()
[void]$md.Add('# Strategy Validation Sweep')
[void]$md.Add('')
[void]$md.Add(('Generated: {0}' -f (Get-Date).ToString('o')))
[void]$md.Add(('Start date: `{0}` | Max stocks: `{1}` | Max elapsed per combo: `{2}s`' -f $StartDate.ToString('yyyy-MM-dd'), $MaxStocks, $MaxElapsedSec))
[void]$md.Add('')
[void]$md.Add('| Combo | Status | Return % | Alpha % | Max DD % | Elapsed s |')
[void]$md.Add('|---|---:|---:|---:|---:|---:|')
foreach ($result in $results) {
    [void]$md.Add(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $result.Combo, $result.Status, $result.StrategyReturnPct, $result.AlphaPct, $result.MaxDrawdownPct, $result.ElapsedSec))
}
[void]$md.Add('')
[void]$md.Add('## Tails')
foreach ($result in $results) {
    [void]$md.Add('')
    [void]$md.Add(('### {0}' -f $result.Combo))
    [void]$md.Add('```text')
    foreach ($line in @($result.Tail)) { [void]$md.Add($line) }
    [void]$md.Add('```')
}
[IO.File]::WriteAllText($mdPath, ($md -join [Environment]::NewLine), [Text.UTF8Encoding]::new($true))

if (@($results | Where-Object Status -eq 'Failed').Count -gt 0) {
    throw 'Bir veya daha fazla validation kombinasyonu basarisiz oldu.'
}

Write-Host "Validation raporlari yazildi: $mdPath, $jsonPath"
