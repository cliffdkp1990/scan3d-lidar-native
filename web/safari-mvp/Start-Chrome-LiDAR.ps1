param([switch]$NoBrowser)
$ErrorActionPreference='Stop'
Set-Location -LiteralPath $PSScriptRoot
$nodeCommand=Get-Command node -ErrorAction SilentlyContinue
if(-not $nodeCommand){throw 'Installer Node.js 22 eller nyere. Appen ændrer ikke din computer automatisk.'}
$version=& $nodeCommand.Source -p 'process.versions.node.split(".")[0]'
if([int]$version -lt 22){throw 'Node.js 22 eller nyere kræves.'}
$chromePaths=@(
  (Join-Path ${env:ProgramFiles} 'Google/Chrome/Application/chrome.exe'),
  (Join-Path ${env:ProgramFiles(x86)} 'Google/Chrome/Application/chrome.exe'),
  (Join-Path $env:LOCALAPPDATA 'Google/Chrome/Application/chrome.exe')
)
$chrome=$chromePaths | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
if(-not $NoBrowser -and -not $chrome){throw 'Google Chrome blev ikke fundet. Installer Chrome eller start med -NoBrowser.'}
$env:PORT='4173'
Write-Host 'Scan3D starter kun på 127.0.0.1:4173. Luk med Ctrl+C. Ingen firewallændring.'
if(-not $NoBrowser){$env:SCAN3D_CHROME_EXE=$chrome}
$launchArgs=@('tools/serve.mjs','--record3d');if(-not $NoBrowser){$launchArgs+='--open-chrome'}
& $nodeCommand.Source @launchArgs
exit $LASTEXITCODE
