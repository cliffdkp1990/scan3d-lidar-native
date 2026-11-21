@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Scan3D - klargoer iPhone-installation
echo.
echo Scan3D sikker installation - IPA-kontrol og officiel AltServer
echo Apple-login, enhedstilladelser og sidste iPhone-installation
echo skal altid godkendes af dig. Ingen data slettes.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Scan3D.ps1" -InstallAltServer
set result=%ERRORLEVEL%
echo.
if not "%result%"=="0" (
  echo Scan3D blev IKKE automatisk installeret. Fejlkode: %result%
  echo Bevar IPA-filen. Læs fejlbeskeden ovenfor.
) else (
  echo Klargoering gennemfoert. Afslut i AltStore Classic paa iPhone.
)
echo.
pause
exit /b %result%
