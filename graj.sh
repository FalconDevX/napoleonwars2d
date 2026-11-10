#!/usr/bin/env bash
# Uruchamia gre The Thin Line.
# Uzycie: ./graj.sh            - gra w tle
#         ./graj.sh --konsola  - z logami w terminalu (wersja konsolowa Godota)
#         ./graj.sh --server [--port 24567] [--scenario "Grand Battle"] [--map Highlands] [--size Large]
#                              - serwer dedykowany bez okna (gracze dołączają przez Menu > Multiplayer)
#         GODOT=/sciezka/do/godot ./graj.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$1" = "--server" ]; then
    shift
    KANDYDACI=(/c/game/Godot_v4.7.2-stable_win64_console.exe /c/Lalka/Godot_v4.7.2-stable_win64_console.exe)
    SERWER=1
elif [ "$1" = "--konsola" ]; then
    shift
    KANDYDACI=(/c/game/Godot_v4.7.2-stable_win64_console.exe /c/Lalka/Godot_v4.7.2-stable_win64_console.exe)
    KONSOLA=1
else
    KANDYDACI=(/c/game/Godot_v4.7.2-stable_win64.exe /c/Lalka/Godot_v4.7.2-stable_win64.exe)
fi

if [ -z "$GODOT" ]; then
    for g in "${KANDYDACI[@]}"; do
        [ -x "$g" ] && GODOT="$g" && break
    done
fi
[ -z "$GODOT" ] && GODOT="$(command -v godot || command -v godot4)"

if [ -z "$GODOT" ] || [ ! -e "$GODOT" ]; then
    echo "Godot not found. Set the GODOT variable or fix the paths in graj.sh" >&2
    exit 1
fi

if [ -n "$SERWER" ]; then
    exec "$GODOT" --path "$DIR" --headless -- --server "$@"
elif [ -n "$KONSOLA" ]; then
    exec "$GODOT" --path "$DIR" "$@"
else
    "$GODOT" --path "$DIR" "$@" >/dev/null 2>&1 &
    disown
    echo "Game started."
fi
