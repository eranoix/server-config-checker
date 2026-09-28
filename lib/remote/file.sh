#!/bin/sh
set -u
p="${DRIFT_ROOT:-}$1"
[ -e "$p" ] || [ -L "$p" ] || exit 3
[ -f "$p" ] || exit 5
[ -r "$p" ] || exit 4
m=$(stat -c %a "$p" 2>/dev/null) || m=$(stat -f %Lp "$p") || exit 4
printf 'mode %s\n' "$m"
cat "$p"
