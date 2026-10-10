@echo off
rem Dedicated server: no game window. Players connect to this computer's address.
rem Change the port or the number of wandering bots here:
set PORT=24500
set BOTS=0
chcp 65001 >nul
cd /d "%~dp0"
if not exist "SpacePrototype.exe" goto noexe
"SpacePrototype.console.exe" --headless -- --server port=%PORT% bots=%BOTS%
pause
exit /b
:noexe
echo.
echo  Сначала один раз запустите play.bat: он соберёт игру из двух частей.
echo.
pause
exit /b
