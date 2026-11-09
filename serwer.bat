@echo off
rem Serwer dedykowany Napoleon Wars 2D (bez okna). Gracze dolaczaja: Menu - Multiplayer - JOIN (IP tego komputera).
rem Opcje: --port 24567  --scenario "Grand Battle"  --map Highlands  --size Large
rem Bitwa startuje, gdy wszyscy gracze klikna READY (co najmniej 1 gracz po stronie Francji).
setlocal
set "GODOT=C:\game\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" set "GODOT=C:\Lalka\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
    echo Nie znaleziono Godota. Popraw sciezke GODOT w pliku serwer.bat
    pause
    exit /b 1
)
"%GODOT%" --path "%~dp0." --headless -- --server %*
pause
