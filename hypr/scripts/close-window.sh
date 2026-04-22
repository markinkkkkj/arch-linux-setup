#!/usr/bin/env bash
# Super+Q: fecha a janela ativa.
# Para yazi: manda 'q' diretamente (usa quit --no-confirm do keymap).
# Para o resto: killactive normal.

class=$(hyprctl activewindow -j | jq -r '.class')

if [[ "$class" == "yazi" ]]; then
    wtype -k q
else
    hyprctl dispatch killactive
fi
