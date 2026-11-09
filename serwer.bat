@echo off
rem Serwer dedykowany Napoleon Wars 2D (bez okna). Gracze dolaczaja: Menu - Multiplayer - JOIN (IP tego komputera).
rem Opcje: --port 24567  --scenario "Grand Battle"  --map Highlands  --size Large
rem Bitwa startuje, gdy wszyscy gracze klikna READY (co najmniej 1 gracz po stronie Francji).
setlocal
call "%~dp0_godot.bat" || (pause & exit /b 1)
"%GODOT_CON%" --path "%~dp0." --headless -- --server %*
pause
