$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Start-Scan3D.ps1') -LibraryOnly

$script:checks = 0
function Check([bool]$Value, [string]$Description) {
    if (-not $Value) { throw "FAILED: $Description" }
    $script:checks++
}
function Reject([scriptblock]$Action, [string]$Description) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Check $failed $Description
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('scan3d-installer-' + [guid]::NewGuid().ToString('N') + '.bin')
try {
    [IO.File]::WriteAllText($fixture, 'original-Scan3D-input')
    $hash = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToLowerInvariant()
    Check ((Assert-Scan3DHash $fixture $hash) -ceq $hash) 'SHA-256 must accept unchanged input'
    Reject { Assert-Scan3DHash $fixture ('0' * 64) } 'Wrong SHA-256 must fail closed'
    Reject { Assert-Scan3DHash $fixture 'invalid' } 'Malformed expected hash must fail closed'
    [IO.File]::AppendAllText($fixture, 'changed')
    Reject { Assert-Scan3DHash $fixture $hash } 'Changed file must fail closed'
    Reject { Assert-Scan3DHash ($fixture + '.missing') $hash } 'Missing file must fail closed'

    $good = [pscustomobject]@{
        schemaVersion=1; sourceCommit=$Scan3DCommit
        bundleIdentifier='dk.scan3dstudio.lidar'; platform='iOS-device-arm64'
        configuration='Release'; marketingVersion='0.1.0'; buildVersion='1'
        documentsVisibleInFilesApp=$true; file='Scan3D-unsigned.ipa'
        sha256=$Scan3DSHA256; installableAsIs=$false; physicalDeviceTested=$false
    }
    Assert-Scan3DManifest $good
    $script:checks++
    foreach ($mutation in @(
        @{key='sourceCommit';value=('f'*40)},
        @{key='bundleIdentifier';value='evil.fake.app'},
        @{key='platform';value='iOS-simulator-arm64'},
        @{key='marketingVersion';value='0.1.1'},
        @{key='documentsVisibleInFilesApp';value=$false},
        @{key='sha256';value=('1'*64)},
        @{key='installableAsIs';value=$true},
        @{key='physicalDeviceTested';value=$true}
    )) {
        $bad = $good.PSObject.Copy()
        $bad.($mutation.key) = $mutation.value
        Reject { Assert-Scan3DManifest $bad } ('Manifest rejects ' + $mutation.key)
    }
    Reject { Assert-Scan3DPackage ([IO.Path]::GetTempPath()) } 'Missing IPA manifest rejected'
    Write-Output "$script:checks safety/unit checks passed; no Apple ID, installation or device touched."
} finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Force }
}
