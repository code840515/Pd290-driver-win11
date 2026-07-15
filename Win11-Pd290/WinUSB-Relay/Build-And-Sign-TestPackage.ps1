[CmdletBinding(DefaultParameterSetName = 'Unsigned')]
param(
    [Parameter(Mandatory, ParameterSetName = 'ExistingCertificate')]
    [string] $CertificateThumbprint,

    [Parameter(Mandatory, ParameterSetName = 'CreateCertificate')]
    [switch] $CreateAndTrustTestCertificate
)

$ErrorActionPreference = 'Stop'

function Find-WdkTool {
    param([Parameter(Mandatory)][string] $Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $kitsBin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path -LiteralPath $kitsBin) {
        $tool = Get-ChildItem -LiteralPath $kitsBin -Filter $Name -File -Recurse |
            Sort-Object `
                @{ Expression = { if ($_.FullName -match '\\x64\\') { 0 } elseif ($_.FullName -match '\\x86\\') { 1 } else { 2 } } },
                @{ Expression = 'FullName'; Descending = $true } |
            Select-Object -First 1
        if ($tool) { return $tool.FullName }
    }
    throw "$Name was not found. Install the Windows Driver Kit first."
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run Windows PowerShell as Administrator.'
    }
}

$inf = Join-Path $PSScriptRoot 'PL2305-WinUSB.inf'
$catalog = Join-Path $PSScriptRoot 'PL2305-WinUSB.cat'
if (-not (Test-Path -LiteralPath $inf -PathType Leaf)) {
    throw "INF not found: $inf"
}

$inf2cat = Find-WdkTool -Name 'Inf2Cat.exe'
Write-Host "Creating catalog with $inf2cat"
& $inf2cat "/driver:$PSScriptRoot" '/os:10_X64' '/uselocaltime' '/verbose'
if ($LASTEXITCODE -ne 0) {
    throw "Inf2Cat failed with exit code $LASTEXITCODE"
}
if (-not (Test-Path -LiteralPath $catalog -PathType Leaf)) {
    throw 'Inf2Cat did not create PL2305-WinUSB.cat.'
}

$certificate = $null
if ($PSCmdlet.ParameterSetName -eq 'CreateCertificate') {
    Assert-Administrator
    $subject = 'CN=Pd290-Win11 Driver Test'
    $certificate = Get-ChildItem -LiteralPath Cert:\LocalMachine\My |
        Where-Object Subject -eq $subject |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1

    if (-not $certificate -or $certificate.NotAfter -lt (Get-Date).AddDays(30)) {
        $certificate = New-SelfSignedCertificate `
            -Type CodeSigningCert `
            -Subject $subject `
            -CertStoreLocation Cert:\LocalMachine\My `
            -HashAlgorithm SHA256 `
            -KeyExportPolicy NonExportable `
            -NotAfter (Get-Date).AddYears(1)
    }

    $cerPath = Join-Path $PSScriptRoot 'Pd290-WinUSB-Test.cer'
    Export-Certificate -Cert $certificate -FilePath $cerPath -Force | Out-Null
    Import-Certificate -FilePath $cerPath -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    Import-Certificate -FilePath $cerPath -CertStoreLocation Cert:\LocalMachine\TrustedPublisher | Out-Null
    Set-Content -LiteralPath (Join-Path $PSScriptRoot 'test-certificate-thumbprint.txt') `
        -Value $certificate.Thumbprint -Encoding ASCII
}
elseif ($PSCmdlet.ParameterSetName -eq 'ExistingCertificate') {
    $thumbprint = $CertificateThumbprint -replace '\s', ''
    $certificate = Get-ChildItem Cert:\LocalMachine\My, Cert:\CurrentUser\My |
        Where-Object Thumbprint -eq $thumbprint |
        Select-Object -First 1
    if (-not $certificate) {
        throw "Code-signing certificate was not found: $thumbprint"
    }
}

if ($certificate) {
    $signTool = Find-WdkTool -Name 'SignTool.exe'
    $arguments = @('sign', '/v', '/fd', 'SHA256', '/sha1', $certificate.Thumbprint)
    if ($certificate.PSParentPath -match 'LocalMachine') { $arguments += '/sm' }
    $arguments += $catalog
    Write-Host "Signing catalog with $($certificate.Subject)"
    & $signTool @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "SignTool failed with exit code $LASTEXITCODE"
    }
}
else {
    Write-Warning 'Catalog created but not signed. Re-run with -CreateAndTrustTestCertificate for local testing.'
}

Get-AuthenticodeSignature -LiteralPath $catalog |
    Format-List Path, Status, StatusMessage, SignerCertificate
