# Validates the Larik add-on index. Runs in CI and locally:
#
#   pwsh ./scripts/validate.ps1                 # offline: structure and rules
#   pwsh ./scripts/validate.ps1 -VerifyDownloads # also download, hash and inspect each zip
#
# Keep the rules in this file and schema/index.schema.json in sync.

[CmdletBinding()]
param(
    [string[]] $IndexFiles = @('index.json', 'official.json'),
    [switch] $VerifyDownloads
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$errors = [System.Collections.Generic.List[string]]::new()

function Add-Error([string] $message) {
    $script:errors.Add($message)
}

function Test-AddonEntry {
    param(
        $Addon,
        [string] $File,
        [int] $Position,
        [System.Collections.Generic.HashSet[string]] $SeenIds,
        [System.Collections.Generic.HashSet[string]] $SeenProviders
    )

    $where = "$File[$Position]"

    if (-not $Addon.id) {
        Add-Error "${where}: id is missing."
    }
    elseif ($Addon.id -cnotmatch '^[a-z0-9]+(\.[a-z0-9-]+)+$') {
        Add-Error "${where}: id '$($Addon.id)' must be reverse-DNS lowercase (for example larik.mysql)."
    }
    else {
        $where = "$File[$Position] ($($Addon.id))"
        if (-not $SeenIds.Add($Addon.id)) {
            Add-Error "${where}: id appears twice in this file."
        }
    }

    if (-not $Addon.name) { Add-Error "${where}: name is missing." }
    if (-not $Addon.publisher) { Add-Error "${where}: publisher is missing." }
    if (-not $Addon.summary) { Add-Error "${where}: summary is missing." }
    elseif ($Addon.summary.Length -gt 200) { Add-Error "${where}: summary is longer than 200 characters." }

    if ($Addon.version -cnotmatch '^\d+\.\d+\.\d+$') {
        Add-Error "${where}: version '$($Addon.version)' must be MAJOR.MINOR.PATCH."
    }

    if ($Addon.contract -cnotmatch '^>=\d+(\.\d+){0,3} <\d+(\.\d+){0,3}$') {
        Add-Error "${where}: contract '$($Addon.contract)' must look like '>=1.0 <2.0'."
    }

    if ($Addon.minAppVersion -cnotmatch '^\d+\.\d+\.\d+$') {
        Add-Error "${where}: minAppVersion '$($Addon.minAppVersion)' must be MAJOR.MINOR.PATCH."
    }

    $platforms = @($Addon.platforms)
    if ($platforms.Count -eq 0) {
        Add-Error "${where}: platforms is empty."
    }

    foreach ($platform in $platforms) {
        if ($platform -notin @('win-x64', 'win-arm64')) {
            Add-Error "${where}: platform '$platform' is not supported."
        }
    }

    $providerIds = @($Addon.providerIds)
    if ($providerIds.Count -eq 0) {
        Add-Error "${where}: providerIds is empty."
    }

    foreach ($providerId in $providerIds) {
        if ($providerId -cnotmatch '^[a-z0-9][a-z0-9-]*$') {
            Add-Error "${where}: provider id '$providerId' is invalid."
        }
        elseif (-not $SeenProviders.Add($providerId)) {
            Add-Error "${where}: provider id '$providerId' is claimed twice in this file."
        }
    }

    if (-not $Addon.url) {
        Add-Error "${where}: url is missing."
    }
    else {
        if ($Addon.url -notmatch '^https://') {
            Add-Error "${where}: url must be https."
        }

        if ($Addon.url -match '/latest/') {
            Add-Error "${where}: url must point at an immutable release, not 'latest'."
        }

        if ($Addon.url -notmatch '\.zip($|\?)') {
            Add-Error "${where}: url must point at a .zip."
        }
    }

    if ($Addon.sha256 -cnotmatch '^[a-f0-9]{64}$') {
        Add-Error "${where}: sha256 must be 64 lowercase hex characters."
    }

    if ($null -ne $Addon.sizeBytes -and [int] $Addon.sizeBytes -le 0) {
        Add-Error "${where}: sizeBytes must be a positive integer."
    }

    if (-not $Addon.license) { Add-Error "${where}: license is missing." }
    if (-not $Addon.homepage) { Add-Error "${where}: homepage is missing." }
    elseif ($Addon.homepage -notmatch '^https://') { Add-Error "${where}: homepage must be https." }

    if ($null -ne $Addon.signature) {
        if (-not $Addon.signature.keyId) { Add-Error "${where}: signature.keyId is missing." }
        if (-not $Addon.signature.value) { Add-Error "${where}: signature.value is missing." }
    }

    if ($VerifyDownloads -and $Addon.url -and $Addon.sha256) {
        Test-Download $Addon $where
    }
}

function Test-Download {
    param($Addon, [string] $Where)

    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("larik-addon-" + [guid]::NewGuid().ToString('N') + '.zip')

    try {
        Invoke-WebRequest -Uri $Addon.url -OutFile $temp -MaximumRedirection 5
    }
    catch {
        Add-Error "${Where}: download failed: $($_.Exception.Message)"
        return
    }

    try {
        $actual = (Get-FileHash -Path $temp -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $Addon.sha256) {
            Add-Error "${Where}: sha256 mismatch (index $($Addon.sha256), download $actual)."
        }

        if ($null -ne $Addon.sizeBytes -and (Get-Item $temp).Length -ne [long] $Addon.sizeBytes) {
            Add-Error "${Where}: sizeBytes says $($Addon.sizeBytes), download is $((Get-Item $temp).Length)."
        }

        Test-Archive $Addon $Where $temp
    }
    finally {
        Remove-Item $temp -ErrorAction SilentlyContinue
    }
}

function Test-Archive {
    param($Addon, [string] $Where, [string] $Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)

    try {
        $manifestEntry = $archive.Entries |
            Where-Object { $_.FullName -eq 'larik-addon.json' } |
            Select-Object -First 1

        if (-not $manifestEntry) {
            Add-Error "${Where}: the zip has no larik-addon.json at its root."
        }
        else {
            $stream = $manifestEntry.Open()
            try {
                $reader = [System.IO.StreamReader]::new($stream)
                try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json }
                finally { $reader.Dispose() }
            }
            finally { $stream.Dispose() }

            if ($manifest.id -ne $Addon.id) {
                Add-Error "${Where}: the manifest id '$($manifest.id)' does not match the index."
            }

            if ($manifest.version -ne $Addon.version) {
                Add-Error "${Where}: the manifest version '$($manifest.version)' does not match the index."
            }

            $manifestProviders = @($manifest.providerIds)
            foreach ($providerId in @($Addon.providerIds)) {
                if ($providerId -notin $manifestProviders) {
                    Add-Error "${Where}: provider id '$providerId' is not declared in the manifest."
                }
            }

            if ($manifest.entryAssembly -and -not ($archive.Entries | Where-Object { $_.FullName -eq $manifest.entryAssembly })) {
                Add-Error "${Where}: entry assembly '$($manifest.entryAssembly)' is not in the zip."
            }
        }

        if (-not ($archive.Entries | Where-Object { $_.FullName -match '^LICENSE($|\.)' })) {
            Add-Error "${Where}: the zip has no LICENSE file."
        }

        if (-not ($archive.Entries | Where-Object { $_.FullName -match '^THIRD-PARTY-NOTICES($|\.)' })) {
            Add-Error "${Where}: the zip has no THIRD-PARTY-NOTICES file."
        }
    }
    finally {
        $archive.Dispose()
    }
}

foreach ($file in $IndexFiles) {
    $path = Join-Path $root $file
    if (-not (Test-Path $path)) {
        Add-Error "${file}: missing."
        continue
    }

    try {
        $index = Get-Content -Raw -Path $path | ConvertFrom-Json
    }
    catch {
        Add-Error "${file}: invalid JSON: $($_.Exception.Message)"
        continue
    }

    if ($index.schemaVersion -ne 1) {
        Add-Error "${file}: schemaVersion must be 1."
    }

    $expectedChannel = if ($file -eq 'official.json') { 'official' } else { 'all' }
    if ($index.channel -ne $expectedChannel) {
        Add-Error "${file}: channel must be '$expectedChannel'."
    }

    if (-not $index.generatedAt) {
        Add-Error "${file}: generatedAt is missing."
    }
    else {
        try { [datetimeoffset]::Parse($index.generatedAt, [System.Globalization.CultureInfo]::InvariantCulture) | Out-Null }
        catch { Add-Error "${file}: generatedAt is not a date-time." }
    }

    $seenIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $seenProviders = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $addons = @($index.addons)

    for ($position = 0; $position -lt $addons.Count; $position++) {
        Test-AddonEntry $addons[$position] $file $position $seenIds $seenProviders
    }

    Write-Host "${file}: $($addons.Count) add-on(s), channel '$($index.channel)'"
}

if ($errors.Count -gt 0) {
    Write-Host ''
    foreach ($errorMessage in $errors) {
        Write-Host "ERROR: $errorMessage" -ForegroundColor Red
    }

    Write-Host ''
    Write-Host "$($errors.Count) problem(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'OK' -ForegroundColor Green


