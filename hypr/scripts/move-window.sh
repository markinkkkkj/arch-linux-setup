#!/bin/bash
# Moves window left/right within workspace; wraps to adjacent workspace at edge.
direction=$1

active=$(hyprctl activewindow -j)
[ -z "$active" ] || [ "$active" = "{}" ] && exit 0

read workspace_id active_x < <(python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
print(d['workspace']['id'], d['at'][0])
" <<< "$active")

clients=$(hyprctl clients -j)

case $direction in
    r)
        has_right=$(python3 -c "
import json, sys
wins = [w for w in json.loads(sys.stdin.read())
        if w['workspace']['id'] == $workspace_id and not w['floating']]
print('true' if any(w['at'][0] > $active_x for w in wins) else 'false')
" <<< "$clients")
        if [ "$has_right" = "true" ]; then
            hyprctl dispatch swapwindow r
        else
            hyprctl dispatch movetoworkspace r+1
        fi
        ;;
    l)
        has_left=$(python3 -c "
import json, sys
wins = [w for w in json.loads(sys.stdin.read())
        if w['workspace']['id'] == $workspace_id and not w['floating']]
print('true' if any(w['at'][0] < $active_x for w in wins) else 'false')
" <<< "$clients")
        if [ "$has_left" = "true" ]; then
            hyprctl dispatch swapwindow l
        elif [ "$workspace_id" -gt 1 ]; then
            hyprctl dispatch movetoworkspace r-1
        fi
        ;;
esac
