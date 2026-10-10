@echo off
rem Assembles SpacePrototype.exe from game.001 + game.002 on the first run, then starts the game.
chcp 65001 >nul
cd /d "%~dp0"
if exist "SpacePrototype.exe" goto run
if not exist "game.001" goto missing
if not exist "game.002" goto missing
copy /b "game.001"+"game.002" "SpacePrototype.exe" >nul
if errorlevel 1 goto failed
for %%F in ("SpacePrototype.exe") do if not "%%~zF"=="109350424" goto failed
del "game.001" "game.002"
:run
start "" "SpacePrototype.exe"
exit /b
:missing
echo.
echo  Не хватает файла game.001 или game.002.
echo  Распакуйте ОБА архива и положите оба файла в эту папку, рядом с play.bat.
echo.
pause
exit /b
:failed
del "SpacePrototype.exe" 2>nul
echo.
echo  Не получилось собрать игру: похоже, один из архивов скачался не полностью.
echo  Скачайте оба архива ещё раз и распакуйте их в эту папку.
echo.
pause
exit /b
