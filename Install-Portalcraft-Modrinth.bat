@echo off
rem Double-click after creating a "Portalcraft" instance (Fabric, Minecraft 26.3) in the Modrinth App.
if not exist "%~dp0Install-Portalcraft-Modrinth.ps1" goto unzip
if not exist "%~dp0tools\portalcraft.ps1" goto unzip
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Portalcraft-Modrinth.ps1" -Pause %*
rem (PowerShell itself couldn't run the script, e.g. scripts are blocked on this PC: keep its message on screen)
if errorlevel 1 pause
exit /b
:unzip
echo Portalcraft: this file was started without the rest of the Portalcraft folder.
echo Unzip the whole zip first (right-click it, Extract All...), then double-click Install-Portalcraft-Modrinth.bat in the unzipped folder.
pause
exit /b 1
