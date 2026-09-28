#!/bin/sh
# shellcheck disable=SC2016 # break snippets expand later, in the shell that runs them
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

CONF='listen 8080
workers 4
'

fx_init; declare_file /etc/app/app.conf 0644 "$CONF"
negative file "a changed line is shown as a diff" \
  'sed -i.bak "s/workers 4/workers 16/" "$LIVE/etc/app/app.conf" && rm -f "$LIVE/etc/app/app.conf.bak"' \
  '+workers 16'

fx_init; declare_file /etc/app/app.conf 0644 "$CONF"
negative file "an appended line is drift" \
  'echo "debug true" >>"$LIVE/etc/app/app.conf"' \
  '+debug true'

fx_init; declare_file /etc/app/app.conf 0644 "$CONF"
negative file "a loosened mode is drift even with identical content" \
  'chmod 0666 "$LIVE/etc/app/app.conf"' \
  'mode: declared 0644, live 0666'

fx_init; declare_file /etc/app/app.conf 0644 "$CONF"
negative file "a deleted file is drift" \
  'rm "$LIVE/etc/app/app.conf"' \
  'missing on host'

fx_init; declare_file /etc/app/app.conf 0644 "$CONF"
negative file "a file replaced by a directory is not a pass" \
  'rm "$LIVE/etc/app/app.conf" && mkdir "$LIVE/etc/app/app.conf"' \
  'not a regular file'

fx_init; declare_file /etc/app/app.env 0600 "TOKEN=abc
"
verify
check "file refuses an env file (exit 2, points to envkeys)" \
  rc_contains "$RC" 2 "$OUT" "declare it as envkeys"

finish
