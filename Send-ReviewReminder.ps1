#requires -Version 5.1
<#
    Send-ReviewReminder.ps1 — GOLGE-MOD INCELEME DIGEST'i (kullanici istegi:
    "Agustosta bana hatirlat"). Biriken gozlem verisini ozetleyip e-postayla
    yollar: rejim/nakit-hedefi dagilimi, ayarlarin secimi kac kez degistirdigi,
    devre kesici tetiklenmeleri ve (varsa) signal-eval kararlari. Boylece
    hatirlatma bir NAG degil, "veri su ana kadar ne diyor" OZETI olur.

    Mevcut rapor mail yolunu DEGISTIRMEZ; ayni SMTP sirlariyla ayri, minimal
    gonderim. Veri yoksa "henuz yeterli gozlem yok" der. SMTP eksikse sessizce
    cikar (exit 0) — hatirlatma akisi hicbir seyi bozmaz.
#>
[CmdletBinding()]
param([string]$DataDir = (Join-Path $PSScriptRoot 'data'))

$ErrorActionPreference = 'Continue'

# Yerel null-guvenli ozellik okuyucu (bu script modulevel import ETMEZ).
function Get-Prop { param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -ne $p) { return $p.Value } else { return $null }
}

function Read-Jsonl {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $rows = @()
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $rows += ($line | ConvertFrom-Json) } catch { }
    }
    return $rows
}

$regime = Read-Jsonl (Join-Path $DataDir 'regime_log.jsonl')
$shadow = Read-Jsonl (Join-Path $DataDir 'shadow_selection.jsonl')
$breaker = Read-Jsonl (Join-Path $DataDir 'circuit_breaker.jsonl')

# --- Ozetler ---
$regimeDays = @($regime).Count
$cashDays = @($regime | Where-Object { [double](Get-Prop -Object $_ -Name 'cashTargetPct') -ge 20 }).Count
$regimeDist = @($regime | Group-Object { [string]$_.regime } | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '
$shadowDays = @($shadow).Count
$shadowChanged = @($shadow | Where-Object { [bool]$_.changed }).Count
$breakerHits = @($breaker).Count

$evalPath = Join-Path $DataDir 'signal_evaluation.json'
$evalText = 'signal-eval henuz karar uretmedi (yeterli bagimsiz donem birikmemis).'
if (Test-Path -LiteralPath $evalPath) {
    try {
        $ev = Get-Content -LiteralPath $evalPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $adj = @($ev.adjustments | ForEach-Object { "$($_.signal): $($_.verdict)" }) -join ' | '
        $overlay = Get-Prop -Object $ev.cashOverlay -Name 'verdict'
        $evalText = "Donem: $($ev.periodsUsed). Ayarlar: $adj. Nakit overlay: $overlay."
    }
    catch { }
}

$html = @"
<html><body style='font-family:Segoe UI,Arial,sans-serif;color:#1a1a1a'>
<h2>BIST Botu — Golge-Mod Inceleme Hatirlatmasi</h2>
<p>Faz 1 koruma mekanizmalari (rejim-nakit, USD-reel, devre kesici) golge modda
kuruldu. Su ana kadar biriken gozlem:</p>
<ul>
  <li><b>Rejim gunlugu:</b> $regimeDays gun (dagilim: $regimeDist). Nakit-onerilen (>=%20) gun: $cashDays.</li>
  <li><b>Ayar etki olcumu:</b> $shadowDays gun; ayarlar Dengeli secimini $shadowChanged gun degistirdi.</li>
  <li><b>Devre kesici:</b> $breakerHits kez NORMAL disi durum loglandi.</li>
  <li><b>Sinyal degerlendirme:</b> $evalText</li>
</ul>
<p><b>Ne yapmali:</b> data/signal_evaluation.json'daki verdict'lere bak. FAYDALI/KORU
cikan mekanizmalar RiskDengeli'de pilotlanabilir; KAPAT/FAYDASIZ cikanlar
kapatilmali. Tam IC guveni icin ~6 bagimsiz aylik donem gerekir (birikmediyse
bir sonraki ay tekrar bak).</p>
<p style='color:#888;font-size:12px'>Bu, golge-mod inceleme hatirlatmasidir; canli
tahsis su an degismiyor. Yatirim tavsiyesi degildir.</p>
</body></html>
"@

# --- SMTP (rapor ile ayni sirlar; eksikse sessiz cik) ---
$server = if ($env:BIST_SMTP_SERVER) { $env:BIST_SMTP_SERVER } else { 'smtp.gmail.com' }
$from = $env:BIST_EMAIL_FROM
$toRaw = $env:BIST_EMAIL_TO
$user = if ($env:BIST_SMTP_USERNAME) { $env:BIST_SMTP_USERNAME } else { $from }
$pass = $env:BIST_SMTP_PASSWORD
if ([string]::IsNullOrWhiteSpace($from) -or [string]::IsNullOrWhiteSpace($toRaw) -or [string]::IsNullOrWhiteSpace($pass)) {
    Write-Host 'SMTP ayarlari eksik; hatirlatma e-postasi atlandi (akis bozulmadi).'
    exit 0
}
$to = @($toRaw -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$port = if ($env:BIST_SMTP_PORT) { [int]$env:BIST_SMTP_PORT } else { 587 }

$msg = [Net.Mail.MailMessage]::new()
$client = [Net.Mail.SmtpClient]::new($server, $port)
try {
    $msg.From = [Net.Mail.MailAddress]::new($from)
    foreach ($a in $to) { [void]$msg.To.Add($a) }
    $msg.Subject = 'BIST Botu — Golge-mod inceleme hatirlatmasi (Agustos)'
    $msg.SubjectEncoding = [Text.Encoding]::UTF8
    $msg.Body = $html
    $msg.BodyEncoding = [Text.Encoding]::UTF8
    $msg.IsBodyHtml = $true
    $client.EnableSsl = $true
    $client.Credentials = [Net.NetworkCredential]::new($user, $pass)
    $client.Timeout = 30000
    $client.Send($msg)
    Write-Host "Hatirlatma e-postasi gonderildi: $($to -join ', ')"
}
catch { Write-Warning "Hatirlatma e-postasi gonderilemedi: $($_.Exception.Message)" }
finally { $msg.Dispose(); $client.Dispose() }
