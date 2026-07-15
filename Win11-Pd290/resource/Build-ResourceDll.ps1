[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$resourceDirectory = $PSScriptRoot
$outputDll = Join-Path (Split-Path $resourceDirectory -Parent) 'T58.dll'

$rc = (Get-Command rc.exe -ErrorAction SilentlyContinue).Source
$link = (Get-Command link.exe -ErrorAction SilentlyContinue).Source
if (-not $rc -or -not $link) {
    throw 'rc.exe and link.exe must be in PATH. Run from an x64 Native Tools Command Prompt for Visual Studio with the Windows SDK installed.'
}

$res = Join-Path $resourceDirectory 'T58.res'
& $rc /nologo "/fo$res" (Join-Path $resourceDirectory 'T58.rc')
if ($LASTEXITCODE -ne 0) { throw "rc.exe failed with exit code $LASTEXITCODE" }

& $link /nologo /dll /noentry /machine:x64 "/out:$outputDll" $res
if ($LASTEXITCODE -ne 0) { throw "link.exe failed with exit code $LASTEXITCODE" }

Remove-Item -LiteralPath $res
Write-Host "Created resource-only DLL: $outputDll"
