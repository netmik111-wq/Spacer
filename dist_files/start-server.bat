@echo off
rem Dedicated server: no game window. Players connect to this computer's address.
rem Change the port or the number of wandering bots here:
set PORT=24500
set BOTS=0
rem continue = go on with the saved campaign (if any), new = start a new one:
set CAMPAIGN=continue
chcp 65001 >nul
cd /d "%~dp0"
if not exist "SpacePrototype.exe" goto noexe
"SpacePrototype.console.exe" --headless -- --server port=%PORT% bots=%BOTS% campaign=%CAMPAIGN%
pause
exit /b
:noexe
echo.
echo  Сначала один раз запустите play.bat: он соберёт игру из двух частей.
echo.
pause
exit /b
