#!/usr/bin/env bash
# Toggle screen recording. F10 inicia ou para a gravação.

PIDFILE=/tmp/gsr.pid

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill -SIGINT "$(cat "$PIDFILE")"
    rm -f "$PIDFILE"
    notify-send "Gravação salva" "~/Videos/" -t 3000
else
    rm -f "$PIDFILE"
    mkdir -p "$HOME/Videos"
    output="$HOME/Videos/$(date +%Y%m%d_%H%M%S).mp4"
    gpu-screen-recorder -w eDP-1 -f 30 -c mp4 -fallback-cpu-encoding yes -o "$output" &
    echo $! > "$PIDFILE"
    notify-send "Gravando..." "F10 para parar" -t 3000
fi
