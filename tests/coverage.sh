#!/bin/sh
# tests/coverage.sh ROOT LEDGER
#
# "A check without a failing test doesn't count." Every check kind in
# ROOT/lib/checks/ must have a test file tests/checks/KIND.sh AND at least one
# negative case recorded as passing in LEDGER during this run. Having the file
# is not enough: a file whose negative cases all fail, or that has none, still
# leaves the check unproven.
#
# Exit: 0 every kind covered · 1 some kind uncovered · 2 usage.
set -u
root=${1:?usage: coverage.sh ROOT LEDGER}
ledger=${2:?usage: coverage.sh ROOT LEDGER}
missing=0
for mod in "$root"/lib/checks/*.sh; do
  kind=$(basename "$mod" .sh)
  if [ ! -f "$root/tests/checks/$kind.sh" ]; then
    echo "UNCOVERED $kind: no tests/checks/$kind.sh"
    missing=$((missing + 1))
    continue
  fi
  n=$(grep -c "^neg $kind " "$ledger" 2>/dev/null)
  if [ "${n:-0}" -eq 0 ]; then
    echo "UNCOVERED $kind: no passing negative case in this run"
    missing=$((missing + 1))
  else
    echo "covered   $kind: $n negative case(s)"
  fi
done
[ "$missing" -eq 0 ]
