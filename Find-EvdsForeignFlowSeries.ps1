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

# v5 bulgusu: bie_mknethar = "Yurt Disi Yerlesikler Menkul Kiymet Portfoyu"
# (HAFTALIK CUMA; TCMB/TAKASBANK/MKK). Simdi bu grubun serileri dokulur.
Write-Host '=== 1) bie_mknethar seri listesi (tam dokum) ==='
foreach ($variant in @('/serieList/type=json&code=bie_mknethar', '/serieList/fe/type=json&code=bie_mknethar')) {
    $series = Inv ("{0}{1}" -f $base, $variant)
    if ($null -eq $series) { continue }
    foreach ($s in @($series)) {
        Write-Host ("  SERI: {0}  |  {1}  |  freq={2} agg={3}" -f $s.SERIE_CODE, $s.SERIE_NAME, $s.FREQUENCY_STR, $s.DEFAULT_AGG_METHOD)
    }
    break
}

Write-Host ''
Write-Host '=== 2) TP.MKNETHAR.M7 son haftalik veriler (canli dogrulama) ==='
$probe = Inv ("{0}/series=TP.MKNETHAR.M7&startDate=01-05-2026&endDate=02-07-2026&type=json&frequency=3&aggregationTypes=sum&formulas=0" -f $base)
if ($null -ne $probe) {
    $json = ($probe | ConvertTo-Json -Depth 4)
    Write-Host $json.Substring(0, [Math]::Min(1800, $json.Length))
}
Write-Host '=== EVDS3 kesif v7 tamam ==='
