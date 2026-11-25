[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$InstallAltServer,
    [switch]$SkipOpen,
    [switch]$LibraryOnly,
    [string]$PackageFolder
)

# One-click Windows *preparation*, not a signature bypass.
# The user must personally authorize Apple ID, device trust, Developer Mode,
# and the final AltStore Classic import on iPhone. Never store credentials.
$ErrorActionPreference = 'Stop'
$Scan3DCommit = '3863502b6aa9929bbe6fb204e0c71ed05e1ef0bb'
$Scan3DSHA256 = '8c1987f7a3bae83742d95025c2c7ee219b711ab446a02948141871747e536fac'
$AltServerSHA256 = '944186a28493b628a7702c514155140d530dfadc31f4279033ae576f1403cd5f'
$AltServerURL = 'https://cdn.altstore.io/file/altstore/altserver-windows/1_8.msi'
$HelpURL = 'https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows'

$InstallerScriptDirectory = $PSScriptRoot

function Resolve-Scan3DPackageFolder([string]$Requested, [string]$Fallback) {
    if ([string]::IsNullOrWhiteSpace($Requested)) { $Requested = $Fallback }
    if ([string]::IsNullOrWhiteSpace($Requested)) { throw 'Pakkemappe mangler. Udpak hele pakken og brug Start-Scan3D.cmd.' }
    if (-not (Test-Path -LiteralPath $Requested -PathType Container)) { throw 'Pakkemappen findes ikke.' }
    return (Get-Item -LiteralPath $Requested -ErrorAction Stop).FullName
}

function Get-Scan3DSignatureStatus([string]$File) {
    if ([string]::IsNullOrWhiteSpace($File) -or -not (Test-Path -LiteralPath $File -PathType Leaf)) { return 'Missing' }
    try { return [string](Get-AuthenticodeSignature -LiteralPath $File -ErrorAction Stop).Status }
    catch { return 'Unknown' }
}

function Test-Scan3DLaunchAllowed([string]$SignatureStatus) {
    return ($SignatureStatus -ceq 'Valid')
}

function Assert-Scan3DHash([string]$Path, [string]$Expected) {
    if ($Expected -notmatch '^[a-f0-9]{64}$') { throw 'Ugyldig forventet SHA-256.' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Filen findes ikke: $Path" }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $Expected) { throw 'SHA-256 matcher ikke; filen bruges IKKE.' }
    return $actual
}

function Assert-Scan3DManifest($M) {
    if ($M.schemaVersion -ne 1 -or
        $M.sourceCommit -cne $Scan3DCommit -or
        $M.bundleIdentifier -cne 'dk.scan3dstudio.lidar' -or
        $M.platform -cne 'iOS-device-arm64' -or
        $M.configuration -cne 'Release' -or
        $M.marketingVersion -cne '0.1.0' -or
        $M.buildVersion -cne '1' -or
        $M.documentsVisibleInFilesApp -ne $true -or
        $M.file -cne 'Scan3D-unsigned.ipa' -or
        $M.sha256 -cne $Scan3DSHA256 -or
        $M.installableAsIs -ne $false -or
        $M.physicalDeviceTested -ne $false) {
        throw 'Forkert version eller usikker IPA-pakkemetadata.'
    }
}

function Assert-Scan3DPackage([string]$Folder) {
    $manifestPath = Join-Path $Folder 'SCAN3D_PACKAGE.json'
    $ipa = Join-Path $Folder 'Scan3D-unsigned.ipa'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'SCAN3D_PACKAGE.json mangler. Brug den samlede officielle Scan3D-testpakke.'
    }
    $m = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Scan3DManifest $m
    $null = Assert-Scan3DHash $ipa $Scan3DSHA256
    if ((Get-Item -LiteralPath $ipa).Length -ne [long]$m.bytes) {
        throw 'IPA-stoerrelse stemmer ikke med manifestet.'
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ipa)
    try {
        $records = @($m.files)
        if ($records.Count -eq 0 -or $records.Count -gt 10000 -or
            $archive.Entries.Count -ne $records.Count) {
            throw 'IPA-indhold matcher ikke pakkemanifest.'
        }
        $seen = @{}
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName
            if ($seen.ContainsKey($name) -or -not $name.StartsWith('Payload/Scan3DLiDAR.app/')) {
                throw 'Uventet eller duplikeret indhold i IPA.'
            }
            $seen[$name] = $true
            if ($name -match '\.(p12|p8|pem|key|mobileprovision)$') {
                throw 'IPA indeholder privat signeringsmateriale.'
            }
            $record = @($records | Where-Object { $_.path -ceq $name })
            if ($record.Count -ne 1 -or [long]$record[0].bytes -ne $entry.Length) {
                throw 'Fil mangler eller har forkert stoerrelse inde i IPA.'
            }
            $stream = $entry.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                $actual = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
            } finally { $sha.Dispose(); $stream.Dispose() }
            if ($actual -cne $record[0].sha256) {
                throw 'Intern IPA-fils SHA-256 stemmer ikke.'
            }
        }
    } finally { $archive.Dispose() }

    return [pscustomobject]@{
        verified = $true
        sourceCommit = $m.sourceCommit
        version = $m.marketingVersion
        ipa = $ipa
        signed = $false
        installedOnPhone = $false
        realLiDARVerified = $false
    }
}

function Find-AltServer {
    foreach ($root in @([Environment]::GetFolderPath('ProgramFilesX86'),
                         [Environment]::GetFolderPath('ProgramFiles'))) {
        if (-not $root) { continue }
        $candidate = Join-Path $root 'AltServer\AltServer.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

if ($LibraryOnly) { return }
if ($env:OS -ne 'Windows_NT') { throw 'Denne startpakke koeres paa Windows. iPhone kan bruge AltStore Classic direkte.' }

$PackageFolder = Resolve-Scan3DPackageFolder $PackageFolder $InstallerScriptDirectory
$package = Assert-Scan3DPackage $PackageFolder
Write-Host ''
Write-Host 'SCAN3D | INSTALLATIONSKLARGORING' -ForegroundColor Cyan
Write-Host '--------------------------------'
Write-Host "Godkendt iPhone-IPA: $($package.version) / $($package.sourceCommit.Substring(0,10))"
Write-Host 'Signatur: mangler. Apple-godkendelser kan IKKE omgaas.'
Write-Host ''

if ($CheckOnly) {
    Write-Host 'PASS: IPA, manifest og interne SHA-256-kontrolsummer stemmer.'
    return
}

$altServer = Find-AltServer
$altServerResult = 'allerede installeret'
if (-not $altServer -and $InstallAltServer) {
    $stateRoot = Join-Path $env:LOCALAPPDATA 'Scan3D\Installationskontrol'
    New-Item -Path $stateRoot -ItemType Directory -Force | Out-Null
    $installer = Join-Path $stateRoot 'AltServer-1.8.00.msi'
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
        $temporary = Join-Path $stateRoot ('download-' + [guid]::NewGuid().ToString('N') + '.msi')
        try {
            Write-Host 'Henter AltServer fra AltStores officielle HTTPS-server...'
            Invoke-WebRequest -Uri $AltServerURL -OutFile $temporary -UseBasicParsing
            $null = Assert-Scan3DHash $temporary $AltServerSHA256
            Move-Item -LiteralPath $temporary -Destination $installer
        } finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        }
    }
    $null = Assert-Scan3DHash $installer $AltServerSHA256
    $installerSignature = Get-Scan3DSignatureStatus $installer
    if (-not (Test-Scan3DLaunchAllowed $installerSignature)) {
        $altServerResult = "Installer signature: $installerSignature - automatic installation stopped"
        Write-Warning $altServerResult
    } else {
    Write-Host 'Windows beder muligvis om administratorgodkendelse til AltServer.'
    try {
        $install = Start-Process -FilePath 'msiexec.exe' -ArgumentList @(
            '/i', ('"' + $installer + '"'), '/passive', '/norestart'
        ) -Verb RunAs -Wait -PassThru
        $altServerResult = 'msiexec afsluttede med kode ' + $install.ExitCode
        if ($install.ExitCode -notin @(0,3010)) {
            Write-Warning "AltServer blev ikke bekræftet installeret: $altServerResult"
        }
    } catch {
        $altServerResult = 'Windows-godkendelse mangler eller installation mislykkedes'
        Write-Warning $altServerResult
    }
    $altServer = Find-AltServer
    }
}
elseif (-not $altServer) {
    $altServerResult = 'Not installed; no automatic installation attempted.'
}

$serverSignature = Get-Scan3DSignatureStatus $altServer
$serverLaunchAllowed = Test-Scan3DLaunchAllowed $serverSignature
if ($altServer -and -not $serverLaunchAllowed) {
    $altServerResult = "Installed executable signature: $serverSignature - automatic start stopped"
}
$serverRunning = [bool](Get-Process -Name AltServer -ErrorAction SilentlyContinue)
$serverStartAttempted = $false
if (-not $SkipOpen -and $serverLaunchAllowed -and -not $serverRunning) {
    $serverStartAttempted = $true
    try { Start-Process -FilePath $altServer -ErrorAction Stop | Out-Null }
    catch { $altServerResult = 'Windows did not start AltServer; inspect security notification.' }
    $serverRunning = [bool](Get-Process -Name AltServer -ErrorAction SilentlyContinue)
}

$appleSupport = $false
foreach ($root in @([Environment]::GetFolderPath('CommonProgramFilesX86'),
                    [Environment]::GetFolderPath('CommonProgramFiles'))) {
    if (-not $root) { continue }
    $apple = Join-Path $root 'Apple'
    $aos = Join-Path $apple 'Internet Services\AOSKit.dll'
    $foundation = Join-Path $apple 'Apple Application Support\Foundation.dll'
    if ((Test-Path -LiteralPath $aos) -and (Test-Path -LiteralPath $foundation)) { $appleSupport = $true }
}
$phoneDetected = $null
try {
    $phoneDetected = @(
        Get-PnpDevice -PresentOnly -ErrorAction Stop |
        Where-Object { $_.FriendlyName -match 'iPhone|Apple Mobile Device' -and $_.Status -eq 'OK' }
    ).Count -gt 0
} catch {
    # Windows device enumeration is advisory, not proof of pairing.
}
$stateRoot = Join-Path $env:LOCALAPPDATA 'Scan3D\Installationskontrol'
New-Item -Path $stateRoot -ItemType Directory -Force | Out-Null
$status = [ordered]@{
    schemaVersion = 1
    checkedAtUtc = [DateTime]::UtcNow.ToString('o')
    ipaSHA256Verified = $true
    exactSourceCommit = $Scan3DCommit
    altServerInstalled = [bool]$altServer
    altServerAttempt = $altServerResult
    altServerAuthenticodeStatus = $serverSignature
    altServerAutomaticLaunchAllowed = $serverLaunchAllowed
    altServerStartAttempted = $serverStartAttempted
    altServerProcessObserved = $serverRunning
    defaultAppleLibrariesPresent = $appleSupport
    windowsDetectsIPhone = $phoneDetected
    appleSigningCompleted = $false
    installedOnIPhone = $false
    realLiDARTested = $false
    nextManualStep = $(if ($serverLaunchAllowed -and $serverRunning) { 'Confirm actual AltStore connection, then import IPA and approve Apple signing.' } else { 'Signing route blocked or unverified; preserve IPA and Windows protection. Check existing paired Remote AltServer or use official Apple signing.' })
}
$statusFile = Join-Path $stateRoot 'scan3d-readiness.json'
$status | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statusFile -Encoding UTF8

if (-not $SkipOpen) {
    Start-Process -FilePath explorer.exe -ArgumentList ('"' + $PackageFolder + '"') | Out-Null
}
Write-Host ''
Write-Host ('AltServer: ' + $(if ($altServer) {'Fundet'} else {'Mangler'}))
Write-Host "AltServer signatur: $serverSignature"
Write-Host "AltServer proces registreret: $serverRunning"
Write-Host ('Apple-biblioteker: ' + $(if ($appleSupport) {'Fundet'} else {'Kontroller iTunes/iCloud'}))
Write-Host ('iPhone tilsluttet: ' + $(if ($phoneDetected -eq $true) {'Ja'} elseif ($phoneDetected -eq $false) {'Ikke fundet'} else {'Ukendt'}))
Write-Host "Status gemt: $statusFile"
Write-Host ''
if ($serverLaunchAllowed -and $serverRunning) {
    Write-Host 'Confirm connection in AltStore Classic; import Scan3D-unsigned.ipa and approve Apple signing.'
    Write-Host 'After installation: Test min LiDAR, save and reopen a project.'
} else {
    Write-Warning 'Signing route not ready. Do not repeat installs or disable Windows security.'
    Write-Host 'Existing paired Remote AltServer requires Wi-Fi and LocalDevVPN; otherwise official Apple signing is needed.'
}
if (-not $appleSupport) { Write-Host "Apple libraries not confirmed. Official instructions: $HelpURL" }
