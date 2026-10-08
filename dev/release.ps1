# BiS Gamba :: release.ps1
# Zips the addon and pushes it to CurseForge through the upload API.
#
#   .\release.ps1                 -> zip + upload as alpha (the default)
#   .\release.ps1 -Type beta      -> zip + upload as beta
#   .\release.ps1 -Type release   -> zip + upload as release
#   .\release.ps1 -ZipOnly        -> just the zip, no upload
#
# Needs, once:
#   * the API token in %USERPROFILE%\Downloads\curseforge-token.txt
#     (CurseForge -> My Account -> API Tokens). One line, nothing else.
#   * the project id below (the number on the project's CurseForge page).
#
# The zip lands in Downloads. The changelog sent is the top entry of
# CHANGELOG.md; the version is the TOC's ## Version. Game version is looked
# up live so a client patch never needs a code change here.

param(
    [ValidateSet("release", "beta", "alpha")] [string] $Type = "alpha",
    [switch] $ZipOnly
)

$ErrorActionPreference = "Stop"

$ProjectId = 1682133          # <-- put the CurseForge project id here
$AddonName = "BiSGamba"
$Root      = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)   # ..\BiSGamba
# On Arn's PC the zip lands in Downloads. GitHub's release workflow (bisdev .github/workflows/release.yml)
# sets RELEASE_OUT instead - no Downloads folder on a build machine.
$Downloads = if ($env:RELEASE_OUT) { $env:RELEASE_OUT } else { Join-Path $env:USERPROFILE "Downloads" }
$TokenFile = Join-Path $Downloads "curseforge-token.txt"

# version from the TOC
$toc = Get-Content (Join-Path $Root "$AddonName.toc")
$version = ($toc | Where-Object { $_ -match '^## Version:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() })
if (-not $version) { throw "no ## Version in the TOC" }

# the top entry of the changelog: from the first "## x.y.z" to the next one
$lines = Get-Content (Join-Path $Root "CHANGELOG.md")
$entry = @(); $inside = $false
foreach ($l in $lines) {
    if ($l -match '^## ') { if ($inside) { break }; $inside = $true; continue }
    if ($inside) { $entry += $l }
}
$changelog = ($entry -join "`n").Trim()

# embedded libs must be byte-identical to their canonical copies, or a release
# ships an old lib (10 Sep 2026: minor 4 still in three addons while minor 5
# fixed the phantom summon). ..\_bisdev\sync.ps1 copies them; -Check just looks.
$canon = @{
    "Libs\LibBiSComm-1.0\LibBiSComm-1.0.lua" = "..\_bisdev\LibBiSComm-1.0\LibBiSComm-1.0.lua"
    "Libs\RezComm-1.0\RezComm-1.0.lua"       = "..\_bisdev\RezComm-1.0\RezComm-1.0.lua"
    "Libs\BiSTheme\Console.lua"              = "..\BiSTheme\Console.lua"
    "Libs\BiSTheme\Options.lua"              = "..\BiSTheme\Options.lua"
}
foreach ($k in $canon.Keys) {
    $mine = Join-Path $Root $k
    $ref  = Join-Path $Root $canon[$k]
    if ((Test-Path $mine) -and (Test-Path $ref)) {
        $a = (Get-FileHash $mine -Algorithm MD5).Hash
        $b = (Get-FileHash $ref  -Algorithm MD5).Hash
        if ($a -ne $b) { throw "embedded $k differs from its canonical copy - run ..\_bisdev\sync.ps1 first" }
    }
}

# the zip: everything but dev/, CLAUDE.md, .git* (.git, .github, .gitignore, .gitattributes)
# and this repo's local leftovers - desk debt 28, 16 Sep 2026
$zip = Join-Path $Downloads "$AddonName-$version.zip"
$stage = Join-Path ([System.IO.Path]::GetTempPath()) "$AddonName-release"   # $env:TEMP does not exist on Linux
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $stage $AddonName) | Out-Null
# Only what git TRACKS ships, minus the dev side - one shared list for every addon, in
# _bisdev/release/stage.ps1. A file nobody committed cannot reach CurseForge however it got into
# this folder (6 Oct 2026: FojjiCore shipped a "Claude outputs" folder the night before).
& (Join-Path $Root "..\_bisdev\release\stage.ps1") -Root $Root -Dest (Join-Path $stage $AddonName)
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $stage $AddonName) -DestinationPath $zip
Write-Host "zip: $zip"
if ($ZipOnly) { exit 0 }

if ($ProjectId -eq 0) { throw "set `$ProjectId at the top of this script first" }
# GitHub's release workflow hands the token over as CURSEFORGE_TOKEN (a repo secret); on Arn's PC it is the file
if ($env:CURSEFORGE_TOKEN) {
    $token = $env:CURSEFORGE_TOKEN.Trim()
} else {
    if (-not (Test-Path $TokenFile)) { throw "no token file at $TokenFile" }
    $token = (Get-Content $TokenFile -Raw).Trim()
}
$headers = @{ "X-Api-Token" = $token }

# game version: the TBC Classic entry, whatever its id is this month
$types = Invoke-RestMethod -Headers $headers -Uri "https://wow.curseforge.com/api/game/version-types"
$tbcType = $types | Where-Object { $_.name -match 'Burning Crusade|TBC' } | Select-Object -First 1
if (-not $tbcType) { throw "no TBC Classic version type found: " + (($types | ForEach-Object { $_.name }) -join ", ") }
$versions = Invoke-RestMethod -Headers $headers -Uri "https://wow.curseforge.com/api/game/versions"
$gv = $versions | Where-Object { $_.gameVersionTypeID -eq $tbcType.id } | Sort-Object name -Descending | Select-Object -First 1
if (-not $gv) { throw "no game version under type $($tbcType.name)" }
Write-Host "game version: $($gv.name) (id $($gv.id), type $($tbcType.name))"

# WoW Forever. A TOC that lists 16001 ships for that client as well, so the upload has to carry its
# CurseForge id too: the API takes CURSEFORGE'S OWN ids in gameVersions, never "1.60.1" and never an
# interface number, and an upload with only the TBC id lands on the wrong flavour.
#
# Looked up live, with _bisdev/release/versions.json as the pinned record and the fallback for a
# machine that cannot reach the API. Refresh it with _bisdev/release/fetch-versions.ps1 (Arn runs
# that: the token never passes through Claude).
$gameVersionIds = @($gv.id)
$ifaceLine = @($toc | Where-Object { $_ -match '^##\s*Interface\s*:\s*(.+)$' } | ForEach-Object { $Matches[1] })
if ($ifaceLine -and (($ifaceLine[0] -split '[,\s]+') -contains '16001')) {
    $pin = Join-Path $PSScriptRoot "..\..\_bisdev\release\versions.json"
    $typeId = 88568                      # the 1.60.x / Forever family on CurseForge
    $pinnedId = $null
    if (Test-Path $pin) {
        $doc = Get-Content $pin -Raw | ConvertFrom-Json
        if ($doc.typeId) { $typeId = [int]$doc.typeId }
        if ($doc.forever -and $doc.forever.id) { $pinnedId = [int]$doc.forever.id }
    }
    $fv = $versions | Where-Object { $_.gameVersionTypeID -eq $typeId -and $_.name -like '1.60*' } |
          Sort-Object name | Select-Object -Last 1
    $foreverId = if ($fv) { [int]$fv.id } elseif ($pinnedId) { $pinnedId } else { $null }
    if (-not $foreverId) {
        throw "the TOC claims 16001 but CurseForge has no 1.60.x under type ${typeId}. Run _bisdev/release/fetch-versions.ps1 and commit versions.json"
    }
    if ($gameVersionIds -notcontains $foreverId) { $gameVersionIds += $foreverId }
    if ($fv) { Write-Host "forever version: $($fv.name) (id $foreverId)" }
    else     { Write-Host "forever version: id $foreverId (pinned in versions.json)" }
}


$metadata = @{
    changelog     = $changelog
    changelogType = "markdown"
    displayName   = "$AddonName $version"
    gameVersions  = @($gameVersionIds)
    releaseType   = $Type
} | ConvertTo-Json -Compress

# multipart by hand: Invoke-RestMethod -Form needs PS 6+, this runs on 5.1 too
$boundary = [System.Guid]::NewGuid().ToString()
$bytes = [System.IO.File]::ReadAllBytes($zip)
$enc = [System.Text.Encoding]::UTF8
$head = "--$boundary`r`nContent-Disposition: form-data; name=`"metadata`"`r`nContent-Type: application/json`r`n`r`n$metadata`r`n" +
        "--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"$(Split-Path $zip -Leaf)`"`r`nContent-Type: application/zip`r`n`r`n"
$tail = "`r`n--$boundary--`r`n"
$body = New-Object System.IO.MemoryStream
$b = $enc.GetBytes($head); $body.Write($b, 0, $b.Length)
$body.Write($bytes, 0, $bytes.Length)
$b = $enc.GetBytes($tail); $body.Write($b, 0, $b.Length)

$resp = Invoke-RestMethod -Method Post -Headers $headers -ContentType "multipart/form-data; boundary=$boundary" `
    -Uri "https://wow.curseforge.com/api/projects/$ProjectId/upload-file" -Body $body.ToArray()
Write-Host "uploaded: file id $($resp.id) - $AddonName $version ($Type)"
