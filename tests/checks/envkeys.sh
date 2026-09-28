#!/bin/sh
# shellcheck disable=SC2016 # break snippets expand later, in the shell that runs them
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

ENV='# app settings
DATABASE_URL=postgres://app:placeholder@db.example.com/app
export QUEUE_URL=amqp://queue.example.com
LOG_LEVEL = info
'

fx_init; declare_env /etc/app/app.env "$ENV" DATABASE_URL QUEUE_URL LOG_LEVEL
negative envkeys "a removed key is reported by name" \
  'grep -v "^export QUEUE_URL" "$LIVE/etc/app/app.env" >"$LIVE/t" && mv "$LIVE/t" "$LIVE/etc/app/app.env"' \
  'declared but missing on host: QUEUE_URL'

fx_init; declare_env /etc/app/app.env "$ENV" DATABASE_URL QUEUE_URL LOG_LEVEL
negative envkeys "an undeclared key is reported by name" \
  'echo "FEATURE_FLAG_X=on" >>"$LIVE/etc/app/app.env"' \
  'on host but not declared:     FEATURE_FLAG_X'

fx_init; declare_env /etc/app/app.env "$ENV" DATABASE_URL QUEUE_URL LOG_LEVEL
negative envkeys "a key commented out counts as missing" \
  'sed -i.bak "s/^LOG_LEVEL/# LOG_LEVEL/" "$LIVE/etc/app/app.env" && rm -f "$LIVE/etc/app/app.env.bak"' \
  'declared but missing on host: LOG_LEVEL'

fx_init; declare_env /etc/app/app.env "$ENV" DATABASE_URL QUEUE_URL LOG_LEVEL
negative envkeys "a deleted env file is drift" \
  'rm "$LIVE/etc/app/app.env"' \
  'missing on host'

fx_init; declare_env /etc/app/app.env "$ENV" DATABASE_URL QUEUE_URL LOG_LEVEL
sed -i.bak 's/info/debug/' "$LIVE/etc/app/app.env" && rm -f "$LIVE/etc/app/app.env.bak"
verify
check "a changed value alone is not reported (values are never compared)" [ "$RC" -eq 0 ]

finish
