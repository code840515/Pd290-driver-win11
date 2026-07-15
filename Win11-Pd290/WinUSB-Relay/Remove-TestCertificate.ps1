[CmdletBinding()]
param(
    [switch] $ConfirmCertificateRemoval
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run Windows PowerShell as Administrator.'
}
if (-not $ConfirmCertificateRemoval) {
    throw 'Re-run with -ConfirmCertificateRemoval to remove the Pd290 test certificate from this computer.'
}

$thumbprintFile = Join-Path $PSScriptRoot 'test-certificate-thumbprint.txt'
if (-not (Test-Path -LiteralPath $thumbprintFile -PathType Leaf)) {
    throw 'Test certificate thumbprint file was not found.'
}
$thumbprint = (Get-Content -LiteralPath $thumbprintFile -Raw).Trim()

foreach ($store in 'My', 'Root', 'TrustedPublisher') {
    $path = "Cert:\LocalMachine\$store\$thumbprint"
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
        Write-Host "Removed certificate from LocalMachine\$store"
    }
}

Write-Host 'Pd290 WinUSB test certificate removal completed.'
