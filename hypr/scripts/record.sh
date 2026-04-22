#!/usr/bin/env bash
# Toggle screen recording. F10 abre menu de áudio e inicia; F10 de novo para.

PIDFILE=/tmp/gsr.pid

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill -SIGINT "$(cat "$PIDFILE")"
    rm -f "$PIDFILE"
    notify-send "Gravação salva" "~/Videos/" -t 3000
    exit 0
fi

choice=$(printf "Mudo\nMicrofone\nÁudio do PC\nMicrofone + PC" \
    | rofi -dmenu -l 4 -theme-str 'window { width: 300px; } inputbar { children: [entry]; }')

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
gpu-screen-recorder -w eDP-1 -f 30 -c mp4 -fallback-cpu-encoding yes \
    "${audio_args[@]}" -o "$output" &
echo $! > "$PIDFILE"
notify-send "Gravando..." "$choice · F10 para parar" -t 3000
