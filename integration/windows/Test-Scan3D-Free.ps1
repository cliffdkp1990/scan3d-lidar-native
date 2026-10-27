$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Start-Scan3D-Free.ps1') -LibraryOnly
$checks = 0
function Check($Actual, $Expected) {
    if ($Actual -cne $Expected) { throw "Expected $Expected, got $Actual" }
    $script:checks++
}
function Reject([scriptblock]$Action) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw 'Expected rejection' }
    $script:checks++
}
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('scan3d-free-test-' + [guid]::NewGuid().ToString('N') + '.txt')
try {
    [IO.File]::WriteAllText($fixture, 'verified-package')
    $expected = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToLowerInvariant()
    Check (Assert-Scan3DHash $fixture $expected) $expected
    Reject { Assert-Scan3DHash $fixture ('0' * 64) }
    Reject { Assert-Scan3DHash $fixture 'not-a-sha256' }
    [IO.File]::AppendAllText($fixture, 'changed')
    Reject { Assert-Scan3DHash $fixture $expected }
    Check (Get-Scan3DNextStep $false $true $true $true) 'package-required'
    Check (Get-Scan3DNextStep $true $false $true $true) 'install-altserver'
    Check (Get-Scan3DNextStep $true $true $false $true) 'check-apple-dependencies'
    Check (Get-Scan3DNextStep $true $true $true $false) 'connect-and-trust-iphone'
    Check (Get-Scan3DNextStep $true $true $true $null) 'connect-and-trust-iphone'
    Check (Get-Scan3DNextStep $true $true $null $true) 'check-apple-dependencies'
    Check (Get-Scan3DNextStep $true $true $true $true) 'user-sign-in-and-device-test-required'
    # Readiness deliberately never becomes 'LiDAR works' without a physical test.
    Write-Output "$checks hash/readiness checks passed. No installer or Apple login invoked."
} finally { if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture } }
