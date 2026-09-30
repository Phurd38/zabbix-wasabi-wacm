<#
.SYNOPSIS
    Verifie les cles Wasabi et les endpoints de la Stats API avant d'importer
    le template Zabbix "Wasabi Cloud Storage by HTTP".

.EXAMPLE
    .\Test-WasabiStatsApi.ps1 -AccessKey XXXX -SecretKey YYYY
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$AccessKey,
    [Parameter(Mandatory = $true)][string]$SecretKey,
    [string]$BaseUrl = 'https://stats.wasabisys.com'
)

$headers = @{ Authorization = "$AccessKey`:$SecretKey"; Accept = 'application/json' }

function Invoke-Stats {
    param([string]$Path)
    try {
        $r = Invoke-WebRequest -Uri ($BaseUrl + $Path) -Headers $headers -Method Get -UseBasicParsing
        return [pscustomobject]@{ Status = [int]$r.StatusCode; Body = ($r.Content | ConvertFrom-Json) }
    }
    catch {
        $code = 0
        if ($null -ne $_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        return [pscustomobject]@{ Status = $code; Body = $null }
    }
}

Write-Host "== 1. Utilisation du compte ==" -ForegroundColor Cyan
$acct = Invoke-Stats '/v1/standalone/utilizations?latest=true&pageSize=1'
Write-Host "HTTP $($acct.Status)"
if ($acct.Status -eq 401 -or $acct.Status -eq 403) {
    Write-Host "Cle refusee. Il faut une cle ROOT ou une cle avec la permission billing." -ForegroundColor Red
    exit 1
}
if ($acct.Status -ne 200) { Write-Host "Echec inattendu." -ForegroundColor Red; exit 1 }
$acct.Body.Records | Select-Object -First 1 |
    Format-List AcctNum, StartTime, EndTime, RawStorageSizeBytes, PaddedStorageSizeBytes,
                DeletedStorageSizeBytes, NumBillableObjects, NumAPICalls, UploadBytes, DownloadBytes

Write-Host "== 2. Endpoint tous-buckets (/utilizations/buckets) ==" -ForegroundColor Cyan
$all = Invoke-Stats '/v1/standalone/utilizations/buckets?latest=true&pageSize=100&pageNum=0'
Write-Host "HTTP $($all.Status)"
if ($all.Status -eq 200) {
    Write-Host "OK - la decouverte automatique fonctionnera. Buckets sur cette page : $($all.Body.Records.Count)" -ForegroundColor Green
    $all.Body.Records | Select-Object -First 5 Bucket, Region, EndTime, RawStorageSizeBytes | Format-Table -AutoSize
    Write-Host "PageInfo :"; $all.Body.PageInfo | Format-List
}
else {
    Write-Host "Indisponible sur ce compte (HTTP $($all.Status))." -ForegroundColor Yellow
    Write-Host "=> Renseignez la macro {`$WASABI.BUCKETS} avec la liste des buckets, separes par des virgules." -ForegroundColor Yellow
    Write-Host "   Le template basculera automatiquement sur /utilizations/bucket/<nom>."
}

Write-Host "== 3. Champs presents dans un enregistrement bucket ==" -ForegroundColor Cyan
$sample = $null
if ($all.Status -eq 200 -and $all.Body.Records.Count -gt 0) { $sample = $all.Body.Records[0] }
if ($sample) {
    ($sample.PSObject.Properties | Select-Object -ExpandProperty Name) -join ', '
}
else {
    Write-Host "Aucun echantillon - relancez apres avoir renseigne un bucket." -ForegroundColor Yellow
}
