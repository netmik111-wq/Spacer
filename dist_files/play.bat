@echo off
rem Assembles SpacePrototype.exe from game.001 + game.002 whenever both parts are here
rem (first run, or a newer version unpacked over the old one), then starts the game.
chcp 65001 >nul
cd /d "%~dp0"
if exist "game.001" if exist "game.002" goto build
if exist "SpacePrototype.exe" goto run
goto missing
:build
copy /b /y "game.001"+"game.002" "SpacePrototype.exe" >nul
if errorlevel 1 goto failed
for %%F in ("SpacePrototype.exe") do if not "%%~zF"=="110981968" goto failed
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
echo  Не получилось собрать игру. Если игра сейчас запущена, закройте её и попробуйте снова.
echo  Иначе похоже, что один из архивов скачался не полностью.
echo  Скачайте оба архива ещё раз и распакуйте их в эту папку.
echo.
pause
exit /b
