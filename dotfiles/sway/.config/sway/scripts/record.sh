#!/usr/bin/env bash
# Toggle screen recording. F10 opens the audio menu and starts; F10 again
# stops. Rewritten from rofi to wofi --dmenu; capture goes through the wlr
# screencast portal (-w portal), the right path under Sway.

set -euo pipefail

PIDFILE=/tmp/gsr.pid

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill -SIGINT "$(cat "$PIDFILE")"
    rm -f "$PIDFILE"
    notify-send "Gravação salva" "~/Videos/" -t 3000
    exit 0
fi

if ! command -v gpu-screen-recorder >/dev/null 2>&1; then
    notify-send "Gravação indisponível" "gpu-screen-recorder não está instalado" -t 5000
    exit 1
fi

choice=$(printf 'Mudo\nMicrofone\nÁudio do PC\nMicrofone + PC' \
    | wofi --dmenu --lines 4 --prompt 'áudio da gravação')

[[ -z "$choice" ]] && exit 0

case "$choice" in
    "Microfone")       audio_args=(-a default_input) ;;
    "Áudio do PC")     audio_args=(-a default_output) ;;
    "Microfone + PC")  audio_args=(-a default_input -a default_output) ;;
    *)                 audio_args=() ;;
esac

rm -f "$PIDFILE"
mkdir -p "$HOME/Videos"
output="$HOME/Videos/$(date +%Y%m%d_%H%M%S).mp4"
gpu-screen-recorder -w portal -f 30 -c mp4 \
    "${audio_args[@]}" -o "$output" &
echo $! > "$PIDFILE"
notify-send "Gravando..." "$choice · F10 para parar" -t 3000
