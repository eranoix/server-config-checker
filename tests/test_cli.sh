#!/bin/sh
# Behaviour of the command line: exit codes, host filter, fail-closed errors.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

fx_init
declare_file /etc/app/app.conf 0644 "a=1
"
verify
check "clean fixture exits 0" [ "$RC" -eq 0 ]
check "summary line is printed" contains "$OUT" "1 checks: 1 passed, 0 drifted, 0 could not run"

# An unreachable host is an ERROR, never a PASS. ProxyCommand=false makes ssh
# fail at once without sending a single packet anywhere.
printf 'h2 ssh nobody@192.0.2.10:22\n' >>"$STATE/inventory.tsv"
mkdir -p "$STATE/files/h2/etc/app" && cp "$STATE/files/h1/etc/app/app.conf" "$STATE/files/h2/etc/app/"
printf 'h2 file /etc/app/app.conf 0644\n' >>"$STATE/checks.tsv"
OUT=$(DRIFT_SSH_OPTS="-F /dev/null -o ProxyCommand=false" "$DV" -s "$STATE" 2>&1); RC=$?
check "unreachable host makes the run INCOMPLETE (exit 2)" [ "$RC" -eq 2 ]
check "unreachable host is reported as ERROR" matches "$OUT" "^ERROR h2"

OUT=$("$DV" -s "$STATE" h1 2>&1); RC=$?
check "host filter limits the run to h1" [ "$RC" -eq 0 ]

printf 'h1 bogus /etc/x -\n' >>"$STATE/checks.tsv"
OUT=$("$DV" -s "$STATE" h1 2>&1); RC=$?
check "unknown check kind is an error, not a pass" rc_contains "$RC" 2 "$OUT" "unknown check kind: bogus"

fx_init
printf 'h1 file /etc/../etc/shadow 0600\n' >"$STATE/checks.tsv"
verify
check "path with .. is refused" rc_contains "$RC" 2 "$OUT" "invalid path"

printf 'h1 file /etc/x;reboot 0600\n' >"$STATE/checks.tsv"
verify
check "path with shell metacharacters is refused" [ "$RC" -eq 2 ]

printf 'h1 unit ../../x.service enabled\n' >"$STATE/checks.tsv"
verify
check "unit name with a slash is refused" [ "$RC" -eq 2 ]

printf 'nohost file /etc/x 0644\n' >"$STATE/checks.tsv"
verify
check "host missing from the inventory is an error" [ "$RC" -eq 2 ]

OUT=$("$DV" -s "$TD/does-not-exist" 2>&1); RC=$?
check "missing state directory is a usage error" [ "$RC" -eq 2 ]

# Read-only: a full run must not change a single byte of the live tree.
fx_init
declare_file /etc/app/app.conf 0644 "a=1
"
declare_unit app.service enabled "[Service]
ExecStart=/bin/true
"
declare_env /etc/app/app.env "K=v
" K
before=$(cd "$LIVE" && find . -exec ls -ld {} + | sort | cksum)
sum_before=$(cd "$LIVE" && find . -type f -exec cat {} + | cksum)
verify
after=$(cd "$LIVE" && find . -exec ls -ld {} + | sort | cksum)
sum_after=$(cd "$LIVE" && find . -type f -exec cat {} + | cksum)
check "verifier run exits 0 on the full fixture" [ "$RC" -eq 0 ]
check "verifier run leaves the host tree unchanged (listing)" same "$before" "$after"
check "verifier run leaves the host tree unchanged (content)" same "$sum_before" "$sum_after"

finish
