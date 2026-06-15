#requires -Version 5.1
<#
    TCMB EVDS metadata kesfi: tahvil/DİBS/getiri/gösterge faiz serilerinin
    GERCEK seri kodlarini bulur (kategoriler -> veri gruplari -> seriler).
    Amac: makro tablosundaki "Türkiye 10Y tahvil faizi" icin dogru EVDS seri
    kodunu tespit etmek. Anahtar $env:BIST_EVDS_API_KEY'den okunur.
    Sonuclar loga yazilir; gunluk raporu/state'i ETKILEMEZ.
#>
$ErrorActionPreference = 'Continue'
$key = $env:BIST_EVDS_API_KEY
if ([string]::IsNullOrWhiteSpace($key)) { Write-Host 'EVDS anahtari yok (BIST_EVDS_API_KEY).'; return }
$headers = @{ key = $key; 'User-Agent' = 'Mozilla/5.0' }

function Inv($url) {
    try { return Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 20 -ErrorAction Stop }
    catch { Write-Host "  ! istek hatasi: $url -> $($_.Exception.Message)"; return $null }
}

$kw = 'TAHVIL|TAHVİL|DIBS|DİBS|GETIRI|GETİRİ|GOSTERGE|GÖSTERGE|BONO|HAZINE|HAZİNE|YIL|VADE|FAIZ|FAİZ|BOND|YIELD|BENCHMARK'

Write-Host '=== EVDS kategorileri ==='
$cats = Inv 'https://evds2.tcmb.gov.tr/service/evds/categories/type=json'
if ($null -eq $cats) { Write-Host 'Kategori alinamadi; cikiliyor.'; return }
$catList = if ($cats -is [array]) { $cats } else { @($cats) }
foreach ($c in $catList) {
    $cid = $c.CATEGORY_ID
    $cname = "$($c.TOPIC_TITLE_TR) / $($c.TOPIC_TITLE_ENG)"
    Write-Host ("[{0}] {1}" -f $cid, $cname)
}

# Faiz/finans ile ilgili kategorileri sec (faiz, finansal, piyasa, menkul).
$targetCats = @($catList | Where-Object {
        "$($_.TOPIC_TITLE_TR) $($_.TOPIC_TITLE_ENG)" -match 'Faiz|Finans|Piyasa|Menkul|Securit|Interest|Bond|Bono|Tahvil'
    })
Write-Host ""
Write-Host "=== Ilgili kategorilerde tahvil/getiri veri gruplari ve serileri ==="
foreach ($c in $targetCats) {
    $cid = $c.CATEGORY_ID
    Write-Host ("--- Kategori [{0}] {1} ---" -f $cid, $c.TOPIC_TITLE_TR)
    $groups = Inv ("https://evds2.tcmb.gov.tr/service/evds/datagroups/mode=2&code={0}&type=json" -f $cid)
    if ($null -eq $groups) { continue }
    $groupList = if ($groups -is [array]) { $groups } else { @($groups) }
    $matchGroups = @($groupList | Where-Object { "$($_.DATAGROUP_NAME) $($_.DATAGROUP_NAME_ENG)" -match $kw })
    foreach ($g in $matchGroups) {
        $gcode = $g.DATAGROUP_CODE
        Write-Host ("  VeriGrubu [{0}] {1}" -f $gcode, $g.DATAGROUP_NAME)
        $series = Inv ("https://evds2.tcmb.gov.tr/service/evds/serieList/type=json&code={0}" -f $gcode)
        if ($null -eq $series) { continue }
        $seriesList = if ($series -is [array]) { $series } else { @($series) }
        foreach ($s in $seriesList) {
            $sname = "$($s.SERIE_NAME) $($s.SERIE_NAME_ENG)"
            if ($sname -match $kw) {
                Write-Host ("      SERI: {0}  |  {1}" -f $s.SERIE_CODE, $s.SERIE_NAME)
            }
        }
    }
}
Write-Host '=== EVDS kesfi tamam ==='
