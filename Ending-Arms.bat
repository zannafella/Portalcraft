@echo off
rem Double-click to pose your Minecraft arms on Chell's in Portal 2's ending (tools\chellpose, opens in the browser).
rem Needs Python 3 (python.org) and Portal 2. Close this window to stop it.
where python >nul 2>nul
if errorlevel 1 goto nopython
python "%~dp0tools\chellpose\server.py" %*
if errorlevel 1 pause
exit /b
:nopython
echo Ending Arms needs Python 3: get it from python.org (tick "Add python.exe to PATH"), then double-click this again.
pause
