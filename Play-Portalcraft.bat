@echo off
rem Double-click to play Portalcraft (see README.md).
if not exist "%~dp0Play-Portalcraft.ps1" goto unzip
if not exist "%~dp0tools\portalcraft.ps1" goto unzip
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Play-Portalcraft.ps1" -Pause %*
rem (PowerShell itself couldn't run the script, e.g. scripts are blocked on this PC: keep its message on screen)
if errorlevel 1 pause
exit /b
:unzip
echo Portalcraft: this file was started without the rest of the Portalcraft folder.
echo Unzip the whole zip first (right-click it, Extract All...), then double-click Play-Portalcraft.bat in the unzipped folder.
pause
exit /b 1
