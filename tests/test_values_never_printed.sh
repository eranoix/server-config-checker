#!/bin/sh
# The core promise of `envkeys`: a VALUE from an env file never appears in
# any output, on the passing path or on the failing one. The failing path is
# the one that matters most, because that is where a naive comparator dumps a
# full diff to the terminal (and to the CI log, and to whoever reads it).
#
# A random sentinel is planted as a value in every shape the parser handles,
# and in shapes it does not handle, then every output is searched for it.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

S="sentinel$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
ALL="$TD/all-output"
: >"$ALL"

ENV="# owner: platform team, rotate with $S
API_TOKEN=$S
export DB_PASSWORD='$S'
SIGNING_KEY = \"$S\"
PRIVATE_BLOCK=\"-----line one $S
${S}_LOOKS_LIKE_KEY=$S
closing line $S\"
malformed line without equals $S
$S
"

record() { printf '%s\n' "$OUT" >>"$ALL"; }

fx_init; declare_env /etc/app/app.env "$ENV" API_TOKEN DB_PASSWORD SIGNING_KEY PRIVATE_BLOCK
verify; record
check "green path: all four keys found, exit 0" [ "$RC" -eq 0 ]

fx_init; declare_env /etc/app/app.env "$ENV" API_TOKEN DB_PASSWORD SIGNING_KEY PRIVATE_BLOCK EXPECTED_BUT_ABSENT
verify; record
check "red path (missing key): exit 1" [ "$RC" -eq 1 ]

fx_init; declare_env /etc/app/app.env "$ENV" API_TOKEN
verify; record
check "red path (undeclared keys): exit 1" [ "$RC" -eq 1 ]
check "multi-line value: its continuation line is not taken for a key" \
  lacks "$OUT" "LOOKS_LIKE_KEY"

fx_init; declare_env /etc/app/app.env "$ENV" API_TOKEN
rm -f "$STATE/envkeys/h1/etc/app/app.env.keys"
verify; record
check "error path (no declared keys): exit 2" [ "$RC" -eq 2 ]

# The same file declared as a plain `file` check must be refused before
# anything is read, so not even an error message can quote it.
fx_init; declare_file /etc/app/app.env 0600 "$ENV"
verify; record
check "file check on an env file is refused: exit 2" [ "$RC" -eq 2 ]

# Stronger than "not printed": the value does not even cross the transport.
# Run the remote half directly and look at everything it emits.
fx_init; declare_env /etc/app/app.env "$ENV" API_TOKEN
DRIFT_ROOT=$LIVE sh -s -- /etc/app/app.env <"$ROOT/lib/remote/envkeys.sh" >>"$ALL" 2>&1
keys=$(DRIFT_ROOT=$LIVE sh -s -- /etc/app/app.env <"$ROOT/lib/remote/envkeys.sh" | tr '\n' ' ')
check "remote script emits key names only" same "$keys" "API_TOKEN DB_PASSWORD PRIVATE_BLOCK SIGNING_KEY "

n=$(grep -c "$S" "$ALL")
check "sentinel appears 0 times across $(wc -l <"$ALL" | tr -d ' ') lines of output" [ "$n" -eq 0 ]
[ "$n" -eq 0 ] || grep -n "$S" "$ALL" | diag

# Guard against a vacuous pass: prove the sentinel really is in the file.
check "sentinel really is in the live file ($(grep -c "$S" "$LIVE/etc/app/app.env") lines)" \
  grep -q "$S" "$LIVE/etc/app/app.env"

finish
