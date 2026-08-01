#!/usr/bin/env bash
# Keybinding cheatsheet -- Super+H. Type to filter (wofi --dmenu).
# Entries match the current sway config; update both together.

set -euo pipefail

binds=(
    "  Super + Enter            →  Terminal (foot)"
    "  Super + Shift + Enter    →  Navegador (zen)"
    "  Super + E                →  Arquivos (thunar)"
    "  Super + R                →  Launcher (wofi)"
    "  Super + Q                →  Fechar janela"
    "  Super + V                →  Toggle flutuante"
    "  Super + Tab              →  Próxima janela"
    "  Super + L                →  Travar tela"
    "  Super + M                →  Sair do Sway"
    "  Super + Shift + R        →  Recarregar Sway"
    "━━━━━━━━━━━━━━━  Foco e janelas  ━━━━━━━━━━━━━━━"
    "  Super + ←/→/↑/↓         →  Mover foco"
    "  Super + Shift + ←/→     →  Mover janela (com wrap)"
    "  Super + Shift + ↑/↓     →  Trocar janela"
    "  Super + Ctrl + ←/→      →  Mover janela p/ área adjacente"
    "  Super + J                →  Toggle split"
    "━━━━━━━━━━━━  Áreas de trabalho  ━━━━━━━━━━━━━"
    "  Super + 1-9              →  Ir para área"
    "  Super + Shift + 1-9      →  Mover janela para área"
    "  Super + S                →  Scratchpad (mostrar)"
    "  Super + Shift + S        →  Mover janela p/ scratchpad"
    "━━━━━━━━━━━━━━━  Clipboard  ━━━━━━━━━━━━━━━━━━"
    "  Super + C                →  Histórico de clipboard"
    "  Super + H                →  Keybind help (este menu)"
    "  Super + Shift + C        →  Color picker"
    "━━━━━━━━━━━━  Prints e gravação  ━━━━━━━━━━━━━"
    "  Print                    →  Screenshot de área → clipboard"
    "  Shift + Print            →  Screenshot completo → clipboard"
    "  F10                      →  Gravar tela (abre menu de áudio)"
    "  F10 (durante gravação)   →  Parar e salvar"
    "━━━━━━━━━━━━━━━  Sistema  ━━━━━━━━━━━━━━━━━━━"
    "  Vol+ / Vol-              →  Volume"
    "  Mute                     →  Mudo"
    "  Brilho+ / Brilho-        →  Brilho da tela"
    "  Fechar a tampa           →  Trava a tela"
)

printf '%s\n' "${binds[@]}" | wofi --dmenu \
    --insensitive \
    --prompt '󰌌 binds' \
    --width 700 \
    --lines 20
