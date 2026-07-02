#requires -Version 5.1
<#
    TCMB EVDS metadata kesfi #2 (EVDS3): yurt disi yerlesiklerin HISSE SENEDI
    saklama / net islem serilerinin gercek kodlarini bulur. EVDS gec-2025'te
    evds3.tcmb.gov.tr'ye tasindi (evds2 uclari SPA'ya yonleniyor; onceki iki
    kosuda HTML donmesinin nedeni bu). Yeni sozlesme:
      - Taban: https://evds3.tcmb.gov.tr/igmevdsms-dis  (anahtar 'key' header'inda)
      - serieList: /serieList/type=json&code=<datagrup>   (path-style)
      - searchResults: /searchResults?searchVal=<terim>   (tam metin arama)
    Sonuclar LOGA yazilir; rapor/state'e dokunmaz.
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
        $r = Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 25 -UseBasicParsing -ErrorAction Stop
        $raw = [string]$r.Content
        if ($raw -match '^\s*<') { Write-Host ("  [tani] HTML dondu: {0}" -f $url); return $null }
        return ($raw | ConvertFrom-Json)
    }
    catch { Write-Host "  ! istek hatasi: $url -> $($_.Exception.Message)"; return $null }
}

Write-Host '=== 1) bie_yssk seri listesi (yurt disi yerlesik saklama bakiyeleri) ==='
$series = Inv ("{0}/serieList/type=json&code=bie_yssk" -f $base)
foreach ($s in @($series)) {
    Write-Host ("  SERI: {0}  |  {1}  |  freq={2}" -f $s.SERIE_CODE, $s.SERIE_NAME, $s.FREQUENCY_STR)
}

Write-Host ''
Write-Host '=== 2) Tam metin arama ==='
foreach ($term in @('yurt disi yerlesik hisse', 'hisse senedi net', 'saklama hisse')) {
    Write-Host ("--- arama: '{0}' ---" -f $term)
    $res = Inv ("{0}/searchResults?searchVal={1}" -f $base, [uri]::EscapeDataString($term))
    if ($null -eq $res) { continue }
    foreach ($g in @($res.veriGruplari) | Select-Object -First 8) {
        Write-Host ("  GRUP: {0}  |  {1}" -f $g.DATAGROUP_CODE, $g.DATAGROUP_NAME)
    }
    foreach ($s in @($res.seriler) | Select-Object -First 15) {
        Write-Host ("  SERI: {0}  |  {1}" -f $s.SERIE_CODE, $s.SERIE_NAME)
    }
}
Write-Host '=== EVDS3 yabanci-akis kesfi tamam ==='
