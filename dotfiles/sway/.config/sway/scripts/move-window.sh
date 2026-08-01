#!/usr/bin/env bash
# Window movement helpers (sway port of the old Hyprland move-window.sh).
#
#   l / r    -> move within the tiling layout; if already at the edge of the
#               workspace, wrap the window to the adjacent workspace instead.
#   ws-l / ws-r -> send the window straight to the adjacent workspace and
#               follow it (the old $mod+Ctrl+arrows movetoworkspace r-1/r+1).

set -euo pipefail

dir="${1:-}"

# Prints "<has_left> <has_right> <ws_num>" for the focused tiled window:
# whether any other tiled window in the same workspace is strictly to its
# left/right, and the current workspace number.
query() {
    swaymsg -t get_tree | python3 -c '
import json, sys

def walk(node, ws=None):
    if node.get("type") == "workspace":
        ws = node
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        yield node, ws, child
        yield from walk(child, ws)

tree = json.load(sys.stdin)
focused = ws_of = None
for parent, ws, node in walk(tree):
    if node.get("focused"):
        focused, ws_of = node, ws
        break

if focused is None or ws_of is None:
    print("none none 0")
    sys.exit(0)

def tiled_leaves(node):
    if not node.get("nodes"):
        yield node
    for child in node.get("nodes", []):
        yield from tiled_leaves(child)

x = focused["rect"]["x"]
others = [leaf for leaf in tiled_leaves(ws_of) if leaf["id"] != focused["id"]]
has_left = any(leaf["rect"]["x"] < x for leaf in others)
has_right = any(leaf["rect"]["x"] > x for leaf in others)
print(("true" if has_left else "false"),
      ("true" if has_right else "false"),
      ws_of.get("num", 0))
'
}

to_workspace() {
    local num="$1"
    swaymsg "move container to workspace number $num; workspace number $num"
}

read -r has_left has_right ws_num < <(query)
[[ "$has_left" == "none" ]] && exit 0

case "$dir" in
    l)
        if [[ "$has_left" == "true" ]]; then
            swaymsg move left
        elif [[ "$ws_num" -gt 1 ]]; then
            to_workspace "$((ws_num - 1))"
        fi
        ;;
    r)
        if [[ "$has_right" == "true" ]]; then
            swaymsg move right
        elif [[ "$ws_num" -lt 10 ]]; then
            to_workspace "$((ws_num + 1))"
        fi
        ;;
    ws-l)
        [[ "$ws_num" -gt 1 ]] && to_workspace "$((ws_num - 1))"
        ;;
    ws-r)
        [[ "$ws_num" -lt 10 ]] && to_workspace "$((ws_num + 1))"
        ;;
    *)
        echo "usage: $(basename "$0") l|r|ws-l|ws-r" >&2
        exit 1
        ;;
esac
