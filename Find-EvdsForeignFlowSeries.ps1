#requires -Version 5.1
<#
    TCMB EVDS metadata kesfi #2: yurt disi yerlesiklerin HISSE SENEDI net islem /
    saklama serilerinin gercek kodlarini bulur (Smart Money: piyasa geneli yabanci
    akis gostergesi icin). Iki yol:
      1) Bilinen aday veri gruplarinin (bie_yssk vb.) seri listesini dogrudan doker.
      2) Kategori -> veri grubu taramasinda 'yabanci/menkul/saklama' esleyenleri gezer.
    Anahtar $env:BIST_EVDS_API_KEY'den okunur. Sonuclar LOGA yazilir; rapor/state'e
    dokunmaz (tanilama amacli, Find-EvdsBondSeries.ps1 ile ayni desen).
#>
$ErrorActionPreference = 'Continue'
$key = $env:BIST_EVDS_API_KEY
if ([string]::IsNullOrWhiteSpace($key)) { Write-Host 'EVDS anahtari yok (BIST_EVDS_API_KEY).'; return }
$headers = @{ key = $key; 'User-Agent' = 'Mozilla/5.0' }

function Inv($url) {
    try { return Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 20 -ErrorAction Stop }
    catch { Write-Host "  ! istek hatasi: $url -> $($_.Exception.Message)"; return $null }
}

function Show-SeriesOfGroup([string]$gcode) {
    $series = Inv ("https://evds2.tcmb.gov.tr/service/evds/serieList/key={0}/type=json/code={1}" -f $key, $gcode)
    if ($null -eq $series) { return }
    foreach ($s in @($series)) {
        Write-Host ("      SERI: {0}  |  {1}  |  freq={2}" -f $s.SERIE_CODE, $s.SERIE_NAME, $s.FREQUENCY_STR)
    }
}

Write-Host '=== 1) Bilinen aday veri gruplari ==='
foreach ($gcode in @('bie_yssk')) {
    Write-Host ("  VeriGrubu [{0}]" -f $gcode)
    Show-SeriesOfGroup $gcode
}

Write-Host ''
Write-Host '=== 2) Kategori taramasi (yabanci/menkul/saklama/portfoy) ==='
$cats = Inv ("https://evds2.tcmb.gov.tr/service/evds/categories/key={0}/type=json" -f $key)
if ($null -eq $cats) { Write-Host 'Kategori alinamadi; cikiliyor.'; return }
$gkw = 'YABANCI|YURT DI|YURTDI|SAKLAMA|MENKUL|SECURIT|NON-RESIDENT|PORTF|CUSTODY'
$skw = 'HISSE|HİSSE|EQUITY|NET'
foreach ($c in @($cats)) {
    if ("$($c.TOPIC_TITLE_TR) $($c.TOPIC_TITLE_ENG)" -notmatch 'Menkul|Securit|Odemeler|Ödemeler|Payment|Dis Denge|Dış|Finans|Piyasa') { continue }
    $groups = Inv ("https://evds2.tcmb.gov.tr/service/evds/datagroups/key={0}/mode=2/code={1}/type=json" -f $key, $c.CATEGORY_ID)
    if ($null -eq $groups) { continue }
    foreach ($g in @($groups)) {
        if ("$($g.DATAGROUP_NAME) $($g.DATAGROUP_NAME_ENG)" -notmatch $gkw) { continue }
        Write-Host ("  [{0}] VeriGrubu [{1}] {2}" -f $c.CATEGORY_ID, $g.DATAGROUP_CODE, $g.DATAGROUP_NAME)
        $series = Inv ("https://evds2.tcmb.gov.tr/service/evds/serieList/key={0}/type=json/code={1}" -f $key, $g.DATAGROUP_CODE)
        if ($null -eq $series) { continue }
        foreach ($s in @($series)) {
            if ("$($s.SERIE_NAME) $($s.SERIE_NAME_ENG)" -match $skw) {
                Write-Host ("      SERI: {0}  |  {1}  |  freq={2}" -f $s.SERIE_CODE, $s.SERIE_NAME, $s.FREQUENCY_STR)
            }
        }
    }
}
Write-Host '=== EVDS yabanci-akis kesfi tamam ==='
