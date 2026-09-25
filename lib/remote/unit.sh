#!/bin/sh
# Runs ON the target host, over `ssh host sh -s`. Read-only.
#
#   unit.sh UNIT
#
# Looks at /etc/systemd/system only, the place where locally managed units
# live. "enabled" means some *.wants/ directory links to the unit, which is
# exactly what `systemctl enable` creates. Reading the file system instead of
# calling systemctl keeps the check read-only and works on hosts where systemd
# is not PID 1 (containers, rescue shells).
#
# Prints "state enabled|disabled" on the first line, then the unit file.
# Exit: 0 ok, 3 unit file missing, 4 not readable.
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
