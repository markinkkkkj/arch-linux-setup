#!/usr/bin/env bash
# Super+Q: fecha a janela ativa.
# Para yazi: manda 'q' diretamente (usa quit --no-confirm do keymap).
# Para o resto: killactive normal.

class=$(hyprctl activewindow -j | jq -r '.class')

if [[ "$class" == "yazi" ]]; then
    hyprctl dispatch sendshortcut "" q "class:^(yazi)$"
else
    hyprctl dispatch killactive
fi
