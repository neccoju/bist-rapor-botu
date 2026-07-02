#requires -Version 5.1
<#
    TCMB EVDS metadata kesfi #2: yurt disi yerlesiklerin HISSE SENEDI net islem /
    saklama serilerinin gercek kodlarini bulur (Smart Money: piyasa geneli yabanci
    akis gostergesi icin). Metadata uclari icin iki varyant denenir (anahtar
    header'da / path'te) ve ham yanit ozeti loglanir — onceki kosuda path'li
    varyant bos dondugu icin taniya oncelik verildi. Sonuclar LOGA yazilir;
    rapor/state'e dokunmaz.
#>
$ErrorActionPreference = 'Continue'
$key = $env:BIST_EVDS_API_KEY
if ([string]::IsNullOrWhiteSpace($key)) { Write-Host 'EVDS anahtari yok (BIST_EVDS_API_KEY).'; return }
$headers = @{ key = $key; 'User-Agent' = 'Mozilla/5.0' }

function Inv-Raw($url) {
    try {
        $r = Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 20 -UseBasicParsing -ErrorAction Stop
        return [string]$r.Content
    }
    catch { Write-Host "  ! istek hatasi: $url -> $($_.Exception.Message)"; return $null }
}

function Inv-Json($urls) {
    # Ilk JSON parse edilebilen ve bos olmayan yaniti dondurur; hepsi bosarsa tani yazar.
    foreach ($u in @($urls)) {
        $raw = Inv-Raw $u
        if ([string]::IsNullOrWhiteSpace($raw)) { Write-Host "  [tani] bos govde: $u"; continue }
        try { $j = $raw | ConvertFrom-Json } catch { Write-Host ("  [tani] JSON degil ({0}): {1}" -f $u, $raw.Substring(0, [Math]::Min(200, $raw.Length))); continue }
        if ($null -eq $j -or (@($j)).Count -eq 0) { Write-Host "  [tani] bos JSON: $u"; continue }
        Write-Host "  [ok] $u"
        return $j
    }
    return $null
}

function Show-SeriesOfGroup([string]$gcode, [string]$filter = '') {
    $series = Inv-Json @(
        ("https://evds2.tcmb.gov.tr/service/evds/serieList/type=json&code={0}" -f $gcode),
        ("https://evds2.tcmb.gov.tr/service/evds/serieList/key={0}/type=json/code={1}" -f $key, $gcode)
    )
    if ($null -eq $series) { return }
    foreach ($s in @($series)) {
        $name = "$($s.SERIE_NAME) $($s.SERIE_NAME_ENG)"
        if ($filter -and $name -notmatch $filter) { continue }
        Write-Host ("      SERI: {0}  |  {1}  |  freq={2}" -f $s.SERIE_CODE, $s.SERIE_NAME, $s.FREQUENCY_STR)
    }
}

Write-Host '=== 1) Bilinen aday veri gruplari (tum seriler) ==='
foreach ($gcode in @('bie_yssk')) {
    Write-Host ("  VeriGrubu [{0}]" -f $gcode)
    Show-SeriesOfGroup $gcode
}

Write-Host ''
Write-Host '=== 2) Kategori taramasi (yabanci/menkul/saklama/portfoy) ==='
$cats = Inv-Json @(
    'https://evds2.tcmb.gov.tr/service/evds/categories/type=json',
    ("https://evds2.tcmb.gov.tr/service/evds/categories/key={0}/type=json" -f $key)
)
if ($null -eq $cats) { Write-Host 'Kategori metadata alinamadi (iki varyant da bos).'; return }
$gkw = 'YABANCI|YURT DI|YURTDI|SAKLAMA|MENKUL|SECURIT|NON-RESIDENT|PORTF|CUSTODY'
$skw = 'HISSE|HİSSE|EQUITY|NET'
foreach ($c in @($cats)) {
    $ctitle = "$($c.TOPIC_TITLE_TR) $($c.TOPIC_TITLE_ENG)"
    if ($ctitle -notmatch 'Menkul|Securit|Odemeler|Ödemeler|Payment|Dis |Dış|Finans|Piyasa|Market') { continue }
    Write-Host ("--- Kategori [{0}] {1} ---" -f $c.CATEGORY_ID, $c.TOPIC_TITLE_TR)
    $groups = Inv-Json @(
        ("https://evds2.tcmb.gov.tr/service/evds/datagroups/mode=2&code={0}&type=json" -f $c.CATEGORY_ID),
        ("https://evds2.tcmb.gov.tr/service/evds/datagroups/key={0}/mode=2/code={1}/type=json" -f $key, $c.CATEGORY_ID)
    )
    if ($null -eq $groups) { continue }
    foreach ($g in @($groups)) {
        if ("$($g.DATAGROUP_NAME) $($g.DATAGROUP_NAME_ENG)" -notmatch $gkw) { continue }
        Write-Host ("  VeriGrubu [{0}] {1}" -f $g.DATAGROUP_CODE, $g.DATAGROUP_NAME)
        Show-SeriesOfGroup $g.DATAGROUP_CODE $skw
    }
}
Write-Host '=== EVDS yabanci-akis kesfi tamam ==='
