#!/usr/bin/env bash
# Toggle screen recording with gpu-screen-recorder.
# F10  → inicia | Shift+F10 → para e salva.

if pgrep -x gpu-screen-recorder > /dev/null; then
    pkill -SIGINT gpu-screen-recorder
    notify-send "Gravação salva" "~/Videos/" -t 3000
else
    mkdir -p "$HOME/Videos"
    output="$HOME/Videos/$(date +%Y%m%d_%H%M%S).mp4"
    gpu-screen-recorder -w eDP-1 -f 30 -c mp4 -fallback-cpu-encoding yes -o "$output" &
    notify-send "Gravando..." "Pressione Shift+F10 para parar" -t 3000
fi
