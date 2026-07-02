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

function Inv($url, $timeout = 45) {
    try {
        $r = Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec $timeout -UseBasicParsing -ErrorAction Stop
        $raw = [string]$r.Content
        if ($raw -match '^\s*<') { Write-Host ("  [tani] HTML dondu: {0}" -f $url); return $null }
        return ($raw | ConvertFrom-Json)
    }
    catch { Write-Host "  ! istek hatasi: $url -> $($_.Exception.Message)"; return $null }
}

Write-Host '=== 1) searchResults ham dokumler (alan adlari + seri kodlari) ==='
foreach ($term in @('yabanci', 'yurt disi yerlesik', 'menkul kiymet istatistikleri', 'hisse senedi')) {
    Write-Host ("--- arama: '{0}' ---" -f $term)
    $res = Inv ("{0}/searchResults?searchVal={1}" -f $base, [uri]::EscapeDataString($term))
    if ($null -eq $res) { continue }
    $json = ($res | ConvertTo-Json -Depth 4)
    Write-Host $json.Substring(0, [Math]::Min(3000, $json.Length))
    Write-Host ''
}

Write-Host '=== 2) Kategori agaci (uzun timeout ile tek deneme) ==='
$tree = Inv ("{0}/categories/withDatagroups/type=json" -f $base) 110
if ($null -ne $tree) {
    $gkw = 'YABANCI|YURT DI|YURTDI|SAKLAMA|MENKUL KIY|NON-RESIDENT|CUSTODY|SECURITIES'
    foreach ($c in @($tree)) {
        foreach ($g in @($c.DATAGROUPS)) {
            if ("$($g.DATAGROUP_NAME) $($g.DATAGROUP_NAME_ENG)" -match $gkw) {
                Write-Host ("  [{0}] {1}  |  {2}" -f $g.DATAGROUP_CODE, $g.DATAGROUP_NAME, $c.TOPIC_TITLE_TR)
            }
        }
    }
}
Write-Host '=== EVDS3 kesif v5 tamam ==='
