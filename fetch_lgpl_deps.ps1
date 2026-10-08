# fetch_lgpl_deps.ps1
#
# Fetches the LGPL builds of FFmpeg and libmpv used for distribution and
# installs them where the app/build expects them:
#   - FFmpeg (LGPL, static)  -> tools/ffmpeg/{ffmpeg,ffprobe,ffplay}.exe
#   - libmpv (LGPL, mpv)     -> tools/mpv/libmpv-2.dll
#
# Both sources publish a checksum file next to the artifact; this script
# verifies the download before unpacking. The GPL media_kit libmpv is never
# trusted: tools/mpv/libmpv-2.dll is what app/windows/CMakeLists.txt and
# pack_release.bat install.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File fetch_lgpl_deps.ps1
#   powershell -ExecutionPolicy Bypass -File fetch_lgpl_deps.ps1 -MpvTag <tag>

[CmdletBinding()]
param(
    # BtbN FFmpeg-Builds release tag ("latest" tracks the daily LGPL build).
    [string]$FfmpegTag = "latest",
    [string]$FfmpegAsset = "ffmpeg-master-latest-win64-lgpl.zip",
    # zhongfly/mpv-winbuild release tag + LGPL libmpv asset.
    [string]$MpvTag = "2026-09-21-e76a35ec95",
    [string]$MpvAsset = "mpv-dev-lgpl-x86_64-20260921-git-e76a35ec95.7z",
    # Skip the initial "no --enable-gpl" sanity check (not recommended).
    [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$work = Join-Path $env:TEMP "hc-lgpl-deps"
New-Item -ItemType Directory -Force -Path $work | Out-Null

function Get-File([string]$Url, [string]$Out) {
    Write-Host "  downloading $Url"
    & curl.exe -L --fail --retry 3 -o $Out $Url
    if ($LASTEXITCODE -ne 0) { throw "download failed: $Url" }
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function Assert-Checksum([string]$Path, [string]$ChecksumsText, [string]$Name) {
    $line = ($ChecksumsText -split "`n" | Where-Object { $_ -match [regex]::Escape($Name) } | Select-Object -First 1)
    if (-not $line) { throw "no checksum entry for $Name" }
    $want = ($line.Trim() -split '\s+')[0].ToLowerInvariant()
    $got = Get-Sha256 $Path
    if ($want -ne $got) { throw "checksum mismatch for $Name`n  want $want`n  got  $got" }
    Write-Host "  checksum OK: $Name"
}

# ---------------------------------------------------------------- FFmpeg ----
Write-Host "== FFmpeg (LGPL) =="
$ffZip = Join-Path $work $FfmpegAsset
$ffSum = Join-Path $work "ffmpeg-checksums.sha256"
Get-File "https://github.com/BtbN/FFmpeg-Builds/releases/download/$FfmpegTag/$FfmpegAsset" $ffZip
Get-File "https://github.com/BtbN/FFmpeg-Builds/releases/download/$FfmpegTag/checksums.sha256" $ffSum
Assert-Checksum $ffZip (Get-Content -Raw $ffSum) $FfmpegAsset

$ffDir = Join-Path $work "ffmpeg"
if (Test-Path $ffDir) { Remove-Item -Recurse -Force $ffDir }
New-Item -ItemType Directory -Force -Path $ffDir | Out-Null
& tar -xf $ffZip -C $ffDir
if ($LASTEXITCODE -ne 0) { throw "failed to extract $ffZip" }
$ffBin = Get-ChildItem $ffDir -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
if (-not $ffBin) { throw "ffmpeg.exe not found in archive" }
$ffSrc = $ffBin.Directory.FullName

$dstFf = Join-Path $repo "tools\ffmpeg"
New-Item -ItemType Directory -Force -Path $dstFf | Out-Null
foreach ($exe in @("ffmpeg.exe", "ffprobe.exe", "ffplay.exe")) {
    Copy-Item (Join-Path $ffSrc $exe) (Join-Path $dstFf $exe) -Force
}
$ffLicense = Get-ChildItem $ffDir -Recurse -Filter "LICENSE.txt" | Select-Object -First 1
if ($ffLicense) { Copy-Item $ffLicense.FullName (Join-Path $repo "licenses\FFmpeg-LGPLv3.txt") -Force }

if (-not $SkipVerify) {
    $config = (& (Join-Path $dstFf "ffmpeg.exe") -hide_banner -version 2>&1 | Out-String)
    if ($config -match "--enable-gpl") { throw "fetched FFmpeg still has --enable-gpl" }
    if ($config -notmatch "--enable-libopenh264") { throw "fetched FFmpeg lacks libopenh264 (required encoder)" }
    $filters = (& (Join-Path $dstFf "ffmpeg.exe") -hide_banner -filters 2>&1 | Out-String)
    foreach ($f in @("drawtext", "geq", "zoompan", "drawbox")) {
        if ($filters -notmatch " $f ") { throw "fetched FFmpeg lacks required filter: $f" }
    }
    Write-Host "  verified: no --enable-gpl, libopenh264 + drawtext/geq/zoompan present"
}

# --------------------------------------------------------------- libmpv ----
Write-Host "== libmpv (LGPL) =="
$mpv7z = Join-Path $work $MpvAsset
$mpvSum = Join-Path $work "mpv-sha256.txt"
Get-File "https://github.com/zhongfly/mpv-winbuild/releases/download/$MpvTag/$MpvAsset" $mpv7z
Get-File "https://github.com/zhongfly/mpv-winbuild/releases/download/$MpvTag/sha256.txt" $mpvSum
Assert-Checksum $mpv7z (Get-Content -Raw $mpvSum) $MpvAsset

$mpvDir = Join-Path $work "mpv"
if (Test-Path $mpvDir) { Remove-Item -Recurse -Force $mpvDir }
New-Item -ItemType Directory -Force -Path $mpvDir | Out-Null
& tar -xf $mpv7z -C $mpvDir
if ($LASTEXITCODE -ne 0) { throw "failed to extract $mpv7z (needs bsdtar/libarchive 7z support)" }
$mpvDll = Get-ChildItem $mpvDir -Recurse -Filter "libmpv-2.dll" | Select-Object -First 1
if (-not $mpvDll) { throw "libmpv-2.dll not found in archive" }

$dstMpv = Join-Path $repo "tools\mpv"
New-Item -ItemType Directory -Force -Path $dstMpv | Out-Null
Copy-Item $mpvDll.FullName (Join-Path $dstMpv "libmpv-2.dll") -Force

# Refresh the copy inside an existing Flutter release bundle, if present.
$rel = Join-Path $repo "app\build\windows\x64\runner\Release\libmpv-2.dll"
if (Test-Path $rel) {
    Copy-Item (Join-Path $dstMpv "libmpv-2.dll") $rel -Force
    Write-Host "  refreshed $rel"
}

Write-Host ""
Write-Host "Done."
Write-Host "  FFmpeg : $dstFf\ffmpeg.exe"
Write-Host "  libmpv : $dstMpv\libmpv-2.dll"
