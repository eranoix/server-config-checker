#!/bin/sh
set -u
d="${DRIFT_ROOT:-}/etc/systemd/system"
f="$d/$1"
[ -f "$f" ] || exit 3
[ -r "$f" ] || exit 4
state=disabled
for w in "$d"/*.wants/"$1"; do
  if [ -L "$w" ] || [ -e "$w" ]; then
    state=enabled
  fi
done
printf 'state %s\n' "$state"
cat "$f"
