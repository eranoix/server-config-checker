#!/bin/sh
# shellcheck disable=SC2016 # break snippets expand later, in the shell that runs them
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

UNIT='[Unit]
Description=Example worker

[Service]
ExecStart=/usr/local/bin/worker --queue jobs
Restart=on-failure

[Install]
WantedBy=multi-user.target
'
W="etc/systemd/system/multi-user.target.wants"

fx_init; declare_unit worker.service enabled "$UNIT"
negative unit "a disabled unit that should be enabled" \
  "rm \"\$LIVE/$W/worker.service\"" \
  'state: declared enabled, live disabled'

fx_init; declare_unit worker.service disabled "$UNIT"
negative unit "an enabled unit that should be disabled" \
  "mkdir -p \"\$LIVE/$W\" && ln -s /etc/systemd/system/worker.service \"\$LIVE/$W/worker.service\"" \
  'state: declared disabled, live enabled'

fx_init; declare_unit worker.service enabled "$UNIT"
negative unit "an edited ExecStart is shown as a diff" \
  'sed -i.bak "s/--queue jobs/--queue jobs --unsafe/" "$LIVE/etc/systemd/system/worker.service" && rm -f "$LIVE/etc/systemd/system/worker.service.bak"' \
  '+ExecStart=/usr/local/bin/worker --queue jobs --unsafe'

fx_init; declare_unit worker.service enabled "$UNIT"
negative unit "a removed unit file is drift" \
  'rm "$LIVE/etc/systemd/system/worker.service"' \
  'missing on host'

finish
