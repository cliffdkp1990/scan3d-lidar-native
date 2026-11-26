@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Scan3D - lokal installationsbro 1.2
set "REPORT=%TEMP%\Scan3D-bro-status.txt"
set "MODE=interactive"
if /i "%~1"=="--check" set "MODE=check"
> "%REPORT%" echo Scan3D lokal bro 1.2
>> "%REPORT%" echo Ingen automatisk Apple-login, sikkerhedsaendring eller fjernstyring.
echo.
echo Scan3D - lokal installationsbro
echo ===============================
echo Kontrollerer din PC. Intet installeres uden dit ja.
echo.

set "DISTRO="
set "WSLREADY=0"
where wsl.exe >nul 2>&1
if errorlevel 1 goto noUbuntu
rem Read only. Only choose known Ubuntu distributions using WSL2.
for /f "usebackq delims=" %%D in (`powershell.exe -NoProfile -Command "$p='HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'; foreach($n in @('Ubuntu-24.04','Ubuntu','Ubuntu-22.04')) { foreach($k in (Get-ChildItem -LiteralPath $p -ErrorAction SilentlyContinue)) { $v=Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue; if($v.DistributionName -eq $n -and $v.Version -eq 2){$n;exit 0} } }"`) do set "DISTRO=%%D"
if not defined DISTRO goto noUbuntu
set "WSLREADY=1"
>> "%REPORT%" echo WSL2: %DISTRO%
echo [OK] Ubuntu i WSL2: %DISTRO%
goto checkUSB

:noUbuntu
>> "%REPORT%" echo WSL2: ingen understottet Ubuntu fundet
echo [STOP] Ubuntu i WSL2 er ikke fundet.
if /i "%MODE%"=="check" goto checkUSB
where wsl.exe >nul 2>&1
if errorlevel 1 goto checkUSB
echo Microsoft WSL-installation kan kraeve administrator og genstart.
choice /c JN /n /m "Installer Ubuntu via Microsoft WSL nu? [J/N] "
if not "%ERRORLEVEL%"=="1" goto checkUSB
wsl.exe --install -d Ubuntu
set "INSTALLRC=%ERRORLEVEL%"
>> "%REPORT%" echo WSL-installation exitcode: %INSTALLRC%
echo Afslut eventuel genstart og Ubuntu-opsatning. Start derefter broen igen.
goto finish

:checkUSB
where usbipd.exe >nul 2>&1
if errorlevel 1 goto noUSB
usbipd.exe --version
if errorlevel 1 goto usbFailed
>> "%REPORT%" echo USBIPD: fundet
echo [OK] USBIPD fundet.
echo USB-oversigt vises lokalt. Ingen bus deles eller tilsluttes automatisk.
usbipd.exe list
if errorlevel 1 goto usbFailed
>> "%REPORT%" echo USBIPD liste: laesbar; fysisk iPhone ikke bekraeftet
goto stage

:usbFailed
>> "%REPORT%" echo USBIPD: kunne ikke laese version eller liste
echo [STOP] USBIPD virker ikke endnu.
goto finish

:noUSB
>> "%REPORT%" echo USBIPD: ikke fundet paa PATH
echo [STOP] USBIPD er ikke fundet.
if /i "%MODE%"=="check" goto finish
if not "%WSLREADY%"=="1" goto finish
where winget.exe >nul 2>&1
if errorlevel 1 goto finish
choice /c JN /n /m "Installer usbipd-win via Windows Package Manager? [J/N] "
if not "%ERRORLEVEL%"=="1" goto finish
winget.exe install --interactive --exact --id dorssel.usbipd-win --source winget
set "USBRC=%ERRORLEVEL%"
>> "%REPORT%" echo USBIPD installation exitcode: %USBRC%
echo Start broen igen fra et nyt CMD-vindue efter installation.
goto finish

:stage
if not "%WSLREADY%"=="1" goto finish
if /i "%MODE%"=="check" goto finish
echo.
echo Naeste trin: hent den fastlaaste Linux-version af xtool i Ubuntu.
echo Filen kontrolleres med SHA256 inden den koeres med --help.
echo Der bruges ingen Apple-konto, ingen sudo og ingen USB-parring.
choice /c JN /n /m "Klargor xtool 1.24.0 nu? [J/N] "
if not "%ERRORLEVEL%"=="1" goto finish
wsl.exe -d "%DISTRO%" --exec bash -lc "set -eu; test $(uname -m) = x86_64; command -v curl; command -v sha256sum; mkdir -p ~/.local/share/scan3d-bridge; cd ~/.local/share/scan3d-bridge; curl --fail --location --proto '=https' --max-time 180 https://github.com/xtool-org/xtool/releases/download/1.24.0/xtool-x86_64.AppImage -o xtool.AppImage.part; echo 'dbfd9d7216f077c84c171b688c4173c37c23ca76bf7fd185d1a9ae8a53dab59f  xtool.AppImage.part' | sha256sum --check --strict; mv -f xtool.AppImage.part xtool.AppImage; chmod u+x xtool.AppImage; APPIMAGE_EXTRACT_AND_RUN=1 timeout 60 ./xtool.AppImage install --help; APPIMAGE_EXTRACT_AND_RUN=1 timeout 60 ./xtool.AppImage auth --help"
if errorlevel 1 goto stageFailed
>> "%REPORT%" echo xtool: lokal SHA256 og CLI bestaaet
echo [OK] xtool klargjort.
if not exist "%~dp0Scan3D-Installer.sh" goto missingStage
echo.
echo Trin 2 bruger den medfoelgende, verificerede IPA og kontrollerer USB.
choice /c JN /n /m "Fortsat til installationsguiden nu? [J/N] "
if not "%ERRORLEVEL%"=="1" goto finish
wsl.exe -d "%DISTRO%" --cd "%~dp0." --exec bash ./Scan3D-Installer.sh
set "STAGERC=%ERRORLEVEL%"
>> "%REPORT%" echo Installationstrin exitcode: %STAGERC%
echo Se installationsguidens resultat ovenfor. Fysisk test afventer.
goto finish

:missingStage
echo [STOP] Scan3D-Installer.sh mangler. Udpak begge filer i samme mappe.
>> "%REPORT%" echo Installationsguide: fil mangler
goto finish

:stageFailed
>> "%REPORT%" echo xtool: lokal klargoering fejlede; se CMD fejl
echo [STOP] xtool kunne ikke klargores. Gentag ikke i blinde.

:finish
>> "%REPORT%" echo Apple-signering og fysisk installation: afventer
echo.
type "%REPORT%"
echo.
if /i "%MODE%"=="check" exit /b 0
echo Rapporten er gemt lokalt i midlertidig mappe.
choice /c JN /n /m "Kopier kun den korte statusrapport til udklipsholder? [J/N] "
if not "%ERRORLEVEL%"=="1" goto end
type "%REPORT%" | clip.exe
echo Indsaet status i ChatGPT.
:end
pause
exit /b 0
