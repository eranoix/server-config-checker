#!/bin/sh
# Runs ON the target host, over `ssh host sh -s`. Read-only.
#
#   envkeys.sh PATH
#
# Prints the KEY NAMES of an env file, one per line, sorted. Values never
# leave the host: they are dropped here, before anything is written to
# stdout, so not even the ssh channel carries them.
#
# Understands `KEY=value`, `export KEY=value`, blank lines, comments, and
# quoted values that span several lines. A continuation line of such a value
# is skipped entirely, even when it happens to look like KEY=value.
#
# Exit: 0 ok, 3 missing, 4 not readable, 5 not a regular file.
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
