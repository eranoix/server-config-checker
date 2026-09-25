#!/bin/sh
# Runs ON the target host, over `ssh host sh -s`. Read-only.
#
#   file.sh PATH
#
# Prints "mode <octal>" on the first line, then the file content unchanged.
# Exit: 0 ok, 3 missing, 4 not readable, 5 not a regular file.
# DRIFT_ROOT is only set by the offline `local` transport used in tests.
set -u
p="${DRIFT_ROOT:-}$1"
[ -e "$p" ] || [ -L "$p" ] || exit 3
[ -f "$p" ] || exit 5
[ -r "$p" ] || exit 4
m=$(stat -c %a "$p" 2>/dev/null) || m=$(stat -f %Lp "$p") || exit 4
printf 'mode %s\n' "$m"
cat "$p"
