#requires -Version 5.1
<#
    TCMB EVDS3 metadata kesfi #2: yurt disi yerlesiklerin HISSE SENEDI saklama /
    net islem serilerini bulur. Tam kategori agaci tek cagrida cekilir
    (/categories/withDatagroups), anahtar kelimeyle esleyen veri gruplarinin
    seri listeleri (/serieList/fe) dokulur. searchResults ham JSON ile loglanir
    (alan adlari onceki kosuda bilinmiyordu). Rapor/state'e dokunmaz.
#>
$ErrorActionPreference = 'Continue'
$key = $env:BIST_EVDS_API_KEY
if ([string]::IsNullOrWhiteSpace($key)) { Write-Host 'EVDS anahtari yok (BIST_EVDS_API_KEY).'; return }
$base = 'https://evds3.tcmb.gov.tr/igmevdsms-dis'
$headers = @{
    key = $key
    'User-Agent' = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36'
    Accept = 'application/json, text/plain, */*'
    Origin = 'https://evds3.tcmb.gov.tr'
    Referer = 'https://evds3.tcmb.gov.tr/tumSeriler'
}

function Inv($url) {
    try {
        $r = Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop
        $raw = [string]$r.Content
        if ($raw -match '^\s*<') { Write-Host ("  [tani] HTML dondu: {0}" -f $url); return $null }
        return ($raw | ConvertFrom-Json)
    }
    catch { Write-Host "  ! istek hatasi: $url -> $($_.Exception.Message)"; return $null }
}

Write-Host '=== 1) Kategori agaci: yabanci/saklama/menkul esleyen veri gruplari ==='
$tree = Inv ("{0}/categories/withDatagroups/type=json" -f $base)
if ($null -eq $tree) { Write-Host 'Kategori agaci alinamadi.'; return }
$gkw = 'YABANCI|YURT DI|YURTDI|SAKLAMA|MENKUL KIY|MENKUL KIY|NON-RESIDENT|CUSTODY|PORTFOLIO FLOW|SECURITIES STAT'
$hits = @()
foreach ($c in @($tree)) {
    foreach ($g in @($c.DATAGROUPS)) {
        $nm = "$($g.DATAGROUP_NAME) $($g.DATAGROUP_NAME_ENG)"
        if ($nm -match $gkw) {
            $hits += $g.DATAGROUP_CODE
            Write-Host ("  [{0}] {1}  |  {2}" -f $g.DATAGROUP_CODE, $g.DATAGROUP_NAME, $c.TOPIC_TITLE_TR)
        }
    }
}

Write-Host ''
Write-Host '=== 2) Esleyen gruplarin serileri (hisse/equity/net filtreli) ==='
foreach ($gcode in ($hits | Select-Object -First 20)) {
    Write-Host ("--- VeriGrubu [{0}] ---" -f $gcode)
    $series = Inv ("{0}/serieList/fe/type=json&code={1}" -f $base, $gcode)
    foreach ($s in @($series)) {
        $nm = "$($s.SERIE_NAME) $($s.SERIE_NAME_ENG)"
        if ($nm -match 'HISSE|HİSSE|EQUITY|NET|STOK|STOCK') {
            Write-Host ("      SERI: {0}  |  {1}  |  freq={2}" -f $s.SERIE_CODE, $s.SERIE_NAME, $s.FREQUENCY_STR)
        }
    }
}

Write-Host ''
Write-Host '=== 3) searchResults ham dokum (alan adlari icin) ==='
$res = Inv ("{0}/searchResults?searchVal={1}" -f $base, [uri]::EscapeDataString('hisse senedi net'))
if ($null -ne $res) {
    $json = ($res | ConvertTo-Json -Depth 4)
    Write-Host $json.Substring(0, [Math]::Min(2500, $json.Length))
}
Write-Host '=== EVDS3 kesif v4 tamam ==='
