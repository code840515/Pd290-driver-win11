[CmdletBinding(DefaultParameterSetName = 'Store')]
param(
    [Parameter(ParameterSetName = 'Store')]
    [string] $CertificateThumbprint,

    [Parameter(Mandatory, ParameterSetName = 'Pfx')]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $PfxPath,

    [Parameter(ParameterSetName = 'Pfx')]
    [Security.SecureString] $PfxPassword
)

$ErrorActionPreference = 'Stop'
$package = $PSScriptRoot

function Find-WdkTool {
    param([Parameter(Mandatory)][string] $Name)

    $fromPath = Get-Command $Name -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }

    $kitsBin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path -LiteralPath $kitsBin) {
        $tool = Get-ChildItem -LiteralPath $kitsBin -Filter $Name -File -Recurse |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($tool) { return $tool.FullName }
    }

    throw "$Name was not found. Install the Windows Driver Kit (WDK), including signing tools."
}

foreach ($name in 'Pd290.inf', 'Pd290.gpd', 'T58.dll') {
    if (-not (Test-Path -LiteralPath (Join-Path $package $name) -PathType Leaf)) {
        throw "Required package file is missing: $name"
    }
}

$inf2cat = Find-WdkTool -Name 'Inf2Cat.exe'
Write-Host "Creating Pd290.cat with $inf2cat"
& $inf2cat "/driver:$package" '/os:10_X64' '/uselocaltime'
if ($LASTEXITCODE -ne 0) { throw "Inf2Cat failed with exit code $LASTEXITCODE" }

$catalog = Join-Path $package 'Pd290.cat'
if (-not (Test-Path -LiteralPath $catalog -PathType Leaf)) {
    throw 'Inf2Cat completed without producing Pd290.cat.'
}

if ($PSCmdlet.ParameterSetName -eq 'Pfx' -or $CertificateThumbprint) {
    $signTool = Find-WdkTool -Name 'SignTool.exe'
    $arguments = @('sign', '/fd', 'SHA256')

    if ($PSCmdlet.ParameterSetName -eq 'Pfx') {
        $arguments += @('/f', (Resolve-Path -LiteralPath $PfxPath).Path)
        if ($PfxPassword) {
            $plainPassword = [Net.NetworkCredential]::new('', $PfxPassword).Password
            $arguments += @('/p', $plainPassword)
        }
    }
    else {
        $arguments += @('/sha1', ($CertificateThumbprint -replace '\s', ''))
    }

    $arguments += $catalog
    Write-Host 'Signing Pd290.cat'
    & $signTool @arguments
    if ($plainPassword) { $plainPassword = $null }
    if ($LASTEXITCODE -ne 0) { throw "SignTool failed with exit code $LASTEXITCODE" }
}
else {
    Write-Warning 'Pd290.cat was created but not signed. Supply -CertificateThumbprint or -PfxPath for an installable package.'
}

Get-AuthenticodeSignature -LiteralPath $catalog |
    Format-List Path, Status, StatusMessage, SignerCertificate
