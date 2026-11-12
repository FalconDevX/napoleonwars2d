@echo off
rem Otwiera projekt Wings of Empire w edytorze Godota. Godot pobierze sie sam, jesli go nie ma.
setlocal
call "%~dp0_godot.bat" || (pause & exit /b 1)
start "" "%GODOT%" --editor --path "%~dp0."
