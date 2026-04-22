#!/usr/bin/env bash
# Cheatsheet de keybindings — Super+F1
# Pesquisável: digite para filtrar

binds=(
    "  Super + Enter            →  Terminal"
    "  Super + Shift + Enter    →  Navegador"
    "  Super + E                →  Arquivos (yazi)"
    "  Super + R                →  Launcher (rofi)"
    "  Super + Q                →  Fechar janela"
    "  Super + V                →  Toggle flutuante"
    "  Super + Tab              →  Próxima janela"
    "  Super + L                →  Travar tela"
    "  Super + M                →  Sair do Hyprland"
    "  Super + Shift + R        →  Recarregar Hyprland"
    "━━━━━━━━━━━━━━━  Foco e janelas  ━━━━━━━━━━━━━━━"
    "  Super + ←/→/↑/↓         →  Mover foco"
    "  Super + Shift + ←/→     →  Mover janela (com wrap)"
    "  Super + Shift + ↑/↓     →  Trocar janela"
    "  Super + Ctrl + ←/→      →  Mover janela p/ área adjacente"
    "  Super + P                →  Pseudo-tile (dwindle)"
    "  Super + J                →  Toggle split"
    "━━━━━━━━━━━━  Áreas de trabalho  ━━━━━━━━━━━━━"
    "  Super + 1-9              →  Ir para área"
    "  Super + Shift + 1-9      →  Mover janela para área"
    "  Super + S                →  Área especial (toggle)"
    "  Super + Shift + S        →  Mover janela p/ área especial"
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
)

printf '%s\n' "${binds[@]}" | rofi -dmenu \
    -i \
    -no-custom \
    -p "󰌌 binds" \
    -theme-str 'window { width: 700px; } listview { lines: 20; }'
