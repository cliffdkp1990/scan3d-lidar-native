[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$PackageDirectory,
    [string]$StateDirectory = (Join-Path $PSScriptRoot '.state'),
    [switch]$Prepare,
    [switch]$InstallAltServer,
    [switch]$OpenAltServer,
    [switch]$LibraryOnly
)

# No Apple credentials, pairing records, certificates, security settings or app data
# are read or modified. Installation is opt-in; the default is a local preflight.
$ErrorActionPreference = 'Stop'
$AltServerVersion = '1.8.00'
$AltServerHash = '944186a28493b628a7702c514155140d530dfadc31f4279033ae576f1403cd5f'
$AltServerUrl = 'https://cdn.altstore.io/file/altstore/altserver-windows/1_8.msi'
$PackageHash = '5ebf4424203356d3ea672df1603ba60db0f26bb788e7038e986af164b9da799d'
$PackageCommit = 'de48b2cfd542ac341f9b168b5603e1e83fdb5786'

function Assert-Scan3DHash([string]$Path, [string]$Expected) {
    if ($Expected -notmatch '^[a-f0-9]{64}$' -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'Kontrolgrundlag eller fil mangler.'
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $Expected) { throw 'SHA-256 stemmer ikke. Filen bevares og bliver ikke brugt.' }
    return $actual
}

function Test-Scan3DPackage([string]$Directory) {
    $manifest = Get-Content -LiteralPath (Join-Path $Directory 'SCAN3D_PACKAGE.json') -Raw | ConvertFrom-Json
    if ($manifest.sourceCommit -cne $PackageCommit -or $manifest.sha256 -cne $PackageHash -or
        $manifest.bundleIdentifier -cne 'dk.scan3dstudio.lidar' -or
        $manifest.platform -cne 'iOS-device-arm64' -or $manifest.installableAsIs -ne $false -or
        $manifest.file -cne 'Scan3D-unsigned.ipa') { throw 'Pakken matcher ikke den kontrollerede native version.' }
    $ipa = Join-Path $Directory $manifest.file
    $null = Assert-Scan3DHash $ipa $PackageHash
    if ((Get-Item -LiteralPath $ipa).Length -ne $manifest.bytes) { throw 'Forkert IPA-stoerrelse.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ipa)
    try {
        $records = @($manifest.files)
        if ($archive.Entries.Count -ne 6 -or $records.Count -ne 6) { throw 'Uventet indhold i IPA.' }
        $seen = @{}
        foreach ($entry in $archive.Entries) {
            if ($seen.ContainsKey($entry.FullName)) { throw 'Dublet i IPA.' }
            $seen[$entry.FullName] = $true
            $record = @($records | Where-Object { $_.path -ceq $entry.FullName })
            if ($record.Count -ne 1 -or $entry.Length -ne $record[0].bytes) { throw 'IPA-filmanifest stemmer ikke.' }
            $stream = $entry.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
            finally { $stream.Dispose(); $sha.Dispose() }
            if ($hash -cne $record[0].sha256) { throw 'En fil inde i IPA stemmer ikke.' }
        }
    } finally { $archive.Dispose() }
    return [pscustomobject]@{ verified = $true; sourceCommit = $PackageCommit; sha256 = $PackageHash; signed = $false }
}

function Get-Scan3DNextStep($PackageVerified, $AltServerPresent, $DependenciesPresent, $PhonePresent) {
    if ($PackageVerified -ne $true) { return 'package-required' }
    if ($AltServerPresent -ne $true) { return 'install-altserver' }
    if ($DependenciesPresent -ne $true) { return 'check-apple-dependencies' }
    if ($PhonePresent -ne $true) { return 'connect-and-trust-iphone' }
    return 'user-sign-in-and-device-test-required'
}

if ($LibraryOnly) { return }
if ($env:OS -ne 'Windows_NT') { throw 'Denne startfil kraever Windows.' }
if (-not $PackageDirectory) {
    $PackageDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../Scan3D-device-review'))
}
$package = Test-Scan3DPackage $PackageDirectory
$null = New-Item -ItemType Directory -Path $StateDirectory -Force
$installer = Join-Path $StateDirectory 'AltServer-1.8.00.msi'
if (($Prepare -or $InstallAltServer) -and -not (Test-Path -LiteralPath $installer)) {
    if ($PSCmdlet.ShouldProcess($AltServerUrl, 'Hent officiel AltServer-installer')) {
        $partial = Join-Path $StateDirectory ('download-' + [guid]::NewGuid().ToString('N') + '.msi')
        $null = Invoke-WebRequest -Uri $AltServerUrl -OutFile $partial -MaximumRedirection 0 -UseBasicParsing
        $null = Assert-Scan3DHash $partial $AltServerHash
        Move-Item -LiteralPath $partial -Destination $installer
    }
}
$installerVerified = $false
if (Test-Path -LiteralPath $installer) { $null = Assert-Scan3DHash $installer $AltServerHash; $installerVerified = $true }
$altServer = $null
foreach ($candidate in @("${env:ProgramFiles(x86)}/AltServer/AltServer.exe", "$env:ProgramFiles/AltServer/AltServer.exe")) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $altServer = $candidate; break }
}
$installation = 'not-requested'
if ($InstallAltServer -and -not $altServer -and $PSCmdlet.ShouldProcess('AltServer 1.8.00', 'Installer uden at fjerne Apple-programmer')) {
    if (-not $installerVerified) { throw 'Ingen kontrolleret installer.' }
    $log = Join-Path $StateDirectory 'altserver-install.log'
    $process = Start-Process -FilePath msiexec.exe -ArgumentList @('/i', ('"' + $installer + '"'), '/passive', '/norestart', '/log', ('"' + $log + '"')) -PassThru -WindowStyle Hidden
    if ($process.WaitForExit(15000)) {
        $installation = 'exit-' + $process.ExitCode
        if ($process.ExitCode -notin @(0, 3010)) { Write-Warning "Installationen sluttede med kode $($process.ExitCode). Windows-godkendelse kan vaere noedvendig. Ingen sikkerhedsindstillinger aendres automatisk." }
    } else { $installation = 'pending-user-or-installer' }
    foreach ($candidate in @("${env:ProgramFiles(x86)}/AltServer/AltServer.exe", "$env:ProgramFiles/AltServer/AltServer.exe")) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $altServer = $candidate; break }
    }
}
$appleRoots = @("${env:CommonProgramFiles(x86)}/Apple", "$env:CommonProgramFiles/Apple")
$dependencies = $false
foreach ($appleRoot in $appleRoots) {
    if ((Test-Path -LiteralPath (Join-Path $appleRoot 'Internet Services/AOSKit.dll')) -and
        (Test-Path -LiteralPath (Join-Path $appleRoot 'Apple Application Support/Foundation.dll')) -and
        (Test-Path -LiteralPath (Join-Path $appleRoot 'Apple Application Support/objc.dll'))) { $dependencies = $true }
}
$storeITunes = $null
try { $storeITunes = @(Get-AppxPackage -Name AppleInc.iTunes -ErrorAction Stop).Count -gt 0 } catch { }
$phone = $null
try { $phone = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object { $_.FriendlyName -match 'iPhone|Apple Mobile Device' -and $_.Status -eq 'OK' }).Count -gt 0 } catch { }
$next = Get-Scan3DNextStep $package.verified ([bool]$altServer) $dependencies $phone
$report = [ordered]@{
    schemaVersion = 1; checkedAt = [DateTime]::UtcNow.ToString('o'); package = $package
    altServerTargetVersion = $AltServerVersion; installerVerified = $installerVerified
    altServerInstalled = [bool]$altServer; installationAttempt = $installation
    defaultAppleLibrariesPresent = $dependencies; storeITunesPresent = $storeITunes
    windowsDetectsPhone = $phone; phoneTrustVerified = $false; appleLoginInspected = $false
    nativeLaunchVerified = $false; physicalLiDARVerified = $false; renewalVerified = $false
    paidMembershipRequiredByThisRoute = $false; nextStep = $next
}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $StateDirectory 'readiness.json') -Encoding UTF8
Write-Output ($report | ConvertTo-Json -Depth 6)
if ($OpenAltServer) {
    if ($next -ne 'user-sign-in-and-device-test-required') { throw "AltServer startes ikke endnu: $next. Se docs/IPHONE_CONTINUOUS_USE_DA.md." }
    if ($PSCmdlet.ShouldProcess('AltServer', 'Aabn officiel lokal app; login foretages af brugeren')) {
        $null = Start-Process -FilePath $altServer -WindowStyle Hidden
    }
}
