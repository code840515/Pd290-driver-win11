[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$package = $PSScriptRoot
$errors = [Collections.Generic.List[string]]::new()
$warnings = [Collections.Generic.List[string]]::new()

function Require-File([string] $Name) {
    $path = Join-Path $package $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $errors.Add("Missing file: $Name")
    }
    return $path
}

$infPath = Require-File 'Pd290.inf'
$gpdPath = Require-File 'Pd290.gpd'
$dllPath = Require-File 'T58.dll'
$rootCatalog = Join-Path $package 'Pd290.cat'
$packagedCatalog = Join-Path $package 'Printer-Driver\Pd290.cat'
$catPath = if (Test-Path -LiteralPath $packagedCatalog -PathType Leaf) { $packagedCatalog } else { $rootCatalog }

if (Test-Path -LiteralPath $infPath) {
    $inf = Get-Content -LiteralPath $infPath -Raw
    foreach ($requiredText in @(
        'CatalogFile=Pd290.cat',
        'DriverVer=07/16/2026,2.0.0.2',
        'Pd290Model="Pd290-Win11"',
        'DriverIsolation=0',
        'CoreDriverSections=',
        '[PrinterPackageInstallation.amd64]',
        'PackageAware=TRUE'
    )) {
        if ($inf -notmatch [regex]::Escape($requiredText)) {
            $errors.Add("INF is missing: $requiredText")
        }
    }
    if ($inf -match '(?im)^\s*(Include|Needs|DataSection)\s*=') {
        $errors.Add('INF still contains legacy Ntprint Include/Needs/DataSection directives.')
    }
}

if (Test-Path -LiteralPath $gpdPath) {
    $gpd = Get-Content -LiteralPath $gpdPath -Raw
    if ($gpd -match 'PAIR\(384\s+160\)') {
        $errors.Add('GPD contains the old malformed custom-size PAIR(384 160).')
    }
    if ($gpd -notmatch '\*MasterUnits:\s*PAIR\(203,\s*203\)') {
        $warnings.Add('Expected 203 DPI master units were not found.')
    }
}

if (Test-Path -LiteralPath $dllPath) {
    $bytes = [IO.File]::ReadAllBytes($dllPath)
    if ($bytes.Length -lt 256 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) {
        $errors.Add('T58.dll is not a valid PE file.')
    }
    else {
        $pe = [BitConverter]::ToInt32($bytes, 0x3c)
        $machine = [BitConverter]::ToUInt16($bytes, $pe + 4)
        $entryPoint = [BitConverter]::ToUInt32($bytes, $pe + 40)
        $optionalHeader = $pe + 24
        $importRva = [BitConverter]::ToUInt32($bytes, $optionalHeader + 120)
        $resourceRva = [BitConverter]::ToUInt32($bytes, $optionalHeader + 128)

        if ($machine -ne 0x8664) { $errors.Add(('T58.dll is not x64 (machine 0x{0:X4}).' -f $machine)) }
        if ($entryPoint -ne 0) { $warnings.Add('T58.dll has an executable entry point; resource-only was expected.') }
        if ($importRva -ne 0) { $warnings.Add('T58.dll imports executable code; resource-only was expected.') }
        if ($resourceRva -eq 0) { $errors.Add('T58.dll has no resource directory.') }
    }
}

if (Test-Path -LiteralPath $catPath -PathType Leaf) {
    $signature = Get-AuthenticodeSignature -LiteralPath $catPath
    if ($signature.Status -ne 'Valid') {
        $warnings.Add("Pd290.cat signature status: $($signature.Status)")
    }
}
else {
    $warnings.Add('Pd290.cat has not been generated. Run Build-Catalog.ps1 on a computer with the WDK.')
}

if ($warnings.Count) {
    Write-Host 'Warnings:' -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
if ($errors.Count) {
    Write-Host 'Errors:' -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

Write-Host 'Package structure check passed.' -ForegroundColor Green
