@echo off
setlocal EnableExtensions
cd /d "%~dp0" || exit /b 1
title Scan3D - sikker installationskontrol
echo Scan3D: kontrollerer IPA og eksisterende AltServer.
echo Ingen automatisk installation af nye programmer.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Scan3D.ps1" -PackageFolder "%~dp0."
set "result=%ERRORLEVEL%"
echo.
if not "%result%"=="0" (
  echo Kontrol stoppet. Fejlkode: %result%. Bevar IPA-filen.
) else (
  echo Kontrol afsluttet. Laes status ovenfor. Appen er IKKE automatisk installeret.
)
pause
exit /b %result%
