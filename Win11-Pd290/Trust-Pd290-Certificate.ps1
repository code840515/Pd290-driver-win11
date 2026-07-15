[CmdletBinding()]
param(
    [switch] $ConfirmCertificateTrust
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run Windows PowerShell as Administrator.'
}
if (-not $ConfirmCertificateTrust) {
    throw 'Re-run with -ConfirmCertificateTrust to trust the Pd290 test certificate in LocalMachine Root and TrustedPublisher.'
}

$certificatePath = Join-Path $PSScriptRoot 'WinUSB-Relay\Pd290-WinUSB-Test.cer'
if (-not (Test-Path -LiteralPath $certificatePath -PathType Leaf)) {
    throw "Certificate not found: $certificatePath"
}

$certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($certificatePath)
if ($certificate.Subject -ne 'CN=Pd290-Win11 Driver Test') {
    throw "Unexpected certificate subject: $($certificate.Subject)"
}
if ($certificate.NotAfter -le (Get-Date)) {
    throw "The Pd290 test certificate expired on $($certificate.NotAfter)."
}

foreach ($store in 'Root', 'TrustedPublisher') {
    $target = "Cert:\LocalMachine\$store\$($certificate.Thumbprint)"
    if (-not (Test-Path -LiteralPath $target)) {
        Import-Certificate -FilePath $certificatePath -CertStoreLocation "Cert:\LocalMachine\$store" | Out-Null
        Write-Host "Trusted Pd290 certificate in LocalMachine\$store"
    }
}

[pscustomobject]@{
    Subject    = $certificate.Subject
    Thumbprint = $certificate.Thumbprint
    NotAfter   = $certificate.NotAfter
    Root       = Test-Path "Cert:\LocalMachine\Root\$($certificate.Thumbprint)"
    Publisher  = Test-Path "Cert:\LocalMachine\TrustedPublisher\$($certificate.Thumbprint)"
} | Format-List
