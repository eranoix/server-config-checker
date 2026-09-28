#!/bin/sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
ledger=$(mktemp "${TMPDIR:-/tmp}/drift-ledger.XXXXXX") || exit 2
trap 'rm -f "$ledger"' EXIT
DRIFT_TEST_LEDGER=$ledger
export DRIFT_TEST_LEDGER

failed=0
files=0
for t in "$here"/checks/*.sh "$here"/test_*.sh; do
  [ -f "$t" ] || continue
  files=$((files + 1))
  name=${t#"$root"/}
  echo "== $name"
  if sh "$t"; then :; else
    echo "!! $name FAILED"
    failed=$((failed + 1))
  fi
done

echo "== coverage: every check needs a passing negative test"
if ! sh "$here/coverage.sh" "$root" "$ledger"; then
  failed=$((failed + 1))
fi

echo
if [ "$failed" -eq 0 ]; then
  echo "suite: $files files passed, all checks covered"
else
  echo "suite: $failed failure(s)"
  exit 1
fi
