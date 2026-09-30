<#
.SYNOPSIS
    Teste la WACM Connect API et enregistre les reponses brutes, afin de
    construire le template Zabbix sur les champs reellement renvoyes.

.DESCRIPTION
    Authentification HTTP Basic :
      - identifiant = votre login WACM (ex. you@example.org)
      - mot de passe = la cle API generee dans Mon profil > WACM Connect

    Toutes les reponses de l'API sont enveloppees ainsi :
      { success, code, message, data: { items: [...], page, size, total }, errors }

.EXAMPLE
    .\Test-WacmConnectApi.ps1 -Username you@example.org -ApiKey YOUR_KEY...

.EXAMPLE
    .\Test-WacmConnectApi.ps1 -Username you@example.org -ApiKey YOUR_KEY... -SubAccountId 100001
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Username,
    [Parameter(Mandatory = $true)][string]$ApiKey,
    [int]$SubAccountId = 0,
    [switch]$IncludeDeleted,
    [string]$BaseUrl = 'https://api.wacm.wasabisys.com',
    [string]$OutDir  = '.\reponses-api'
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$pair    = "{0}:{1}" -f $Username, $ApiKey
$basic   = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
$headers = @{ Authorization = "Basic $basic"; Accept = 'application/json' }

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

function Invoke-Wacm {
    param([string]$Path, [string]$SaveAs)

    Write-Host "  GET $Path" -ForegroundColor DarkGray
    try {
        $r = Invoke-WebRequest -Uri ($BaseUrl + $Path) -Headers $headers -Method Get -UseBasicParsing
        if ($SaveAs) { $r.Content | Out-File -FilePath (Join-Path $OutDir $SaveAs) -Encoding utf8 }
        return [pscustomobject]@{ Status = [int]$r.StatusCode; Body = ($r.Content | ConvertFrom-Json) }
    }
    catch {
        $code = 0
        if ($null -ne $_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        Write-Host "  -> HTTP $code" -ForegroundColor Red
        return [pscustomobject]@{ Status = $code; Body = $null }
    }
}

# Extrait la liste utile quelle que soit la forme de l'enveloppe
function Get-Items {
    param($Body)
    if ($null -eq $Body) { return @() }
    if ($null -ne $Body.data) {
        if ($null -ne $Body.data.items)   { return @($Body.data.items) }
        if ($Body.data -is [array])       { return @($Body.data) }
        return @($Body.data)
    }
    if ($null -ne $Body.items)   { return @($Body.items) }
    if ($null -ne $Body.content) { return @($Body.content) }
    if ($Body -is [array])       { return @($Body) }
    return @($Body)
}

function Show-Fields {
    param($Object, [string]$Label)
    if ($null -eq $Object) { return }
    Write-Host "Champs disponibles ($Label) :" -ForegroundColor DarkGray
    ($Object.PSObject.Properties.Name) -join ', '
    Write-Host ''
}

# ------------------------------------------------------------------
Write-Host "`n== 1. Authentification / liste des sous-comptes ==" -ForegroundColor Cyan

$q = '/api/v1/sub-accounts/?page=0&size=100'
if ($IncludeDeleted) { $q += '&includeDeleted=true' }

$subs = Invoke-Wacm $q 'sub-accounts.json'

switch ($subs.Status) {
    200 { }
    401 { Write-Host "Identifiant ou cle incorrects. L'identifiant est votre LOGIN WACM, pas le nom de la cle." -ForegroundColor Red; exit 1 }
    403 { Write-Host "Cle valide mais droits insuffisants." -ForegroundColor Red; exit 1 }
    default { Write-Host "Echec (HTTP $($subs.Status))." -ForegroundColor Red; exit 1 }
}

Write-Host "Authentification OK." -ForegroundColor Green

# @() obligatoire : PowerShell deballe un tableau d'un seul element,
# et .Count sur un PSCustomObject renvoie vide, pas 1.
$accounts = @(Get-Items $subs.Body)
Write-Host "Sous-comptes retournes : $($subs.Body.data.total)"
Write-Host ''

$accounts | Select-Object id, name, status, wasabiAccountNumber,
    @{n='activeTB'; e={[math]::Round($_.activeStorage, 3)}},
    @{n='deletedTB'; e={[math]::Round($_.deletedStorage, 3)}},
    purchasedStorageTB | Format-Table -AutoSize

if ($accounts.Count -gt 0) { Show-Fields $accounts[0] 'sous-compte' }

# ------------------------------------------------------------------
Write-Host "== 2. Utilisation d'un sous-compte ==" -ForegroundColor Cyan

if ($SubAccountId -gt 0) {
    $id = $SubAccountId
}
elseif ($accounts.Count -gt 0) {
    $id = $accounts[0].id
}
else {
    Write-Host "Aucun sous-compte visible avec cette cle. Arret." -ForegroundColor Yellow
    Write-Host "Relancez avec -IncludeDeleted, ou verifiez le perimetre de la cle dans WACM."
    exit 0
}

$name = ($accounts | Where-Object { $_.id -eq $id } | Select-Object -First 1).name
Write-Host "Sous-compte teste : $name (id $id)"

$util = Invoke-Wacm "/api/v1/sub-accounts/$id/utilizations?latest=true" 'utilizations.json'
if ($util.Status -eq 200) {
    Write-Host "OK" -ForegroundColor Green
    $u = @(Get-Items $util.Body)
    if ($u.Count -gt 0) {
        $u[0] | Format-List
        Show-Fields $u[0] 'utilisation compte'
    }
    else { Write-Host "Reponse vide." -ForegroundColor Yellow }
}

# ------------------------------------------------------------------
Write-Host "== 3. Utilisation par bucket ==" -ForegroundColor Cyan

$buckets = Invoke-Wacm "/api/v1/sub-accounts/$id/buckets?latest=true&page=0&size=100" 'buckets.json'
if ($buckets.Status -eq 200) {
    Write-Host "OK" -ForegroundColor Green
    $b = @(Get-Items $buckets.Body)
    Write-Host "Buckets retournes : $($b.Count)"
    Write-Host ''
    @($b) | Select-Object name, region, endTime, activeStorage, deletedStorage,
        activeObjects, egress, ingress, apiCalls | Format-Table -AutoSize
    if (@($b).Count -gt 0) { Show-Fields @($b)[0] 'bucket' }
}

# ------------------------------------------------------------------
Write-Host "== Termine ==" -ForegroundColor Cyan
Write-Host "Reponses brutes enregistrees dans : $((Resolve-Path $OutDir).Path)"
