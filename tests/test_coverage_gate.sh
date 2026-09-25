#!/bin/sh
# shellcheck disable=SC2016 # break snippets expand later, in the shell that runs them
# The coverage rule has to be tested too, or it is just a comment. Two ways a
# check can slip through, and both must be caught:
#   1. a check kind with no negative test at all;
#   2. a check that never fails, whatever you do to the target.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

# A scratch copy of the project with one extra check kind.
cp -R "$ROOT/bin" "$ROOT/lib" "$ROOT/locks.conf" "$TD/"
mkdir -p "$TD/tests/checks"
cp "$ROOT"/tests/checks/*.sh "$TD/tests/checks/"
cat >"$TD/lib/checks/lazy.sh" <<'LAZY'
# shellcheck shell=sh
# A check that always passes. It must never count as covered.
check_lazy() { return 0; }
LAZY

led="$TD/ledger"
printf 'neg file x\nneg unit x\nneg envkeys x\n' >"$led"
out=$(sh "$ROOT/tests/coverage.sh" "$TD" "$led"); rc=$?
check "a kind without tests/checks/KIND.sh fails the gate" [ "$rc" -eq 1 ]
check "the gate names the uncovered kind" contains "$out" "UNCOVERED lazy"

echo '#!/bin/sh' >"$TD/tests/checks/lazy.sh"
out=$(sh "$ROOT/tests/coverage.sh" "$TD" "$led"); rc=$?
check "an empty test file with no passing negative case still fails" [ "$rc" -eq 1 ]

# The negative-test contract itself must reject a check that never fails.
fx_init
printf 'h1 lazy /etc/anything -\n' >"$STATE/checks.tsv"
# shellcheck disable=SC2034 # read by verify() in lib.sh
DV="$TD/bin/config-check"
if negative_core lazy "lazy check" 'rm -rf "$LIVE/etc"' 'anything' >/dev/null 2>&1; then
  not_ok "negative_core rejects a check that stays green after the break"
else
  ok "negative_core rejects a check that stays green after the break"
fi

printf 'neg file x\nneg unit x\nneg envkeys x\nneg lazy x\n' >"$led"
out=$(sh "$ROOT/tests/coverage.sh" "$TD" "$led"); rc=$?
check "with a recorded negative case the kind counts as covered" [ "$rc" -eq 0 ]

finish
