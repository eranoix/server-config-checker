#!/bin/sh
set -u
p="${DRIFT_ROOT:-}$1"
[ -e "$p" ] || [ -L "$p" ] || exit 3
[ -f "$p" ] || exit 5
[ -r "$p" ] || exit 4
LC_ALL=C awk -v sq="'" '
  open != "" { if (index($0, open)) open = ""; next }
  /^[[:space:]]*(#|$)/ { next }
  {
    line = $0
    sub(/^[[:space:]]*export[[:space:]]+/, "", line)
    if (!match(line, /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/)) next
    key = substr(line, 1, RLENGTH)
    sub(/[[:space:]]*=$/, "", key)
    val = substr(line, RLENGTH + 1)
    sub(/^[[:space:]]*/, "", val)
    q = substr(val, 1, 1)
    if ((q == "\"" || q == sq) && !index(substr(val, 2), q)) open = q
    print key
  }
' "$p" | LC_ALL=C sort -u
