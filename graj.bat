@echo off
rem Uruchamia gre Wings of Empire (dwuklik). Godot pobierze sie sam, jesli go nie ma.
setlocal
call "%~dp0_godot.bat" || (pause & exit /b 1)
start "" "%GODOT%" --path "%~dp0."
