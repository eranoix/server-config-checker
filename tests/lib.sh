# shellcheck shell=sh
# tests/lib.sh: a small TAP-style harness in POSIX sh, plus fixture helpers.
#
# Each test file sources this, calls `ok`/`not_ok` (or the helpers built on
# them) and ends with `finish`. tests/run.sh runs every file and aggregates.
#
# Offline by design: fixtures are directories on disk and the inventory uses
# the `local` transport, which runs the SAME remote scripts the ssh transport
# sends to real hosts, just against a directory instead of `/`.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
while [ ! -f "$ROOT/locks.conf" ] && [ "$ROOT" != / ]; do ROOT=$(dirname "$ROOT"); done
DV=${DV:-$ROOT/bin/config-check}
LEDGER=${DRIFT_TEST_LEDGER:-/dev/null}

T_N=0
T_FAIL=0
TD=$(mktemp -d "${TMPDIR:-/tmp}/drift-test.XXXXXX") || exit 2
trap 'rm -rf "$TD"' EXIT
trap 'exit 2' INT TERM

ok() {
  T_N=$((T_N + 1))
  echo "ok $T_N - $*"
}

not_ok() {
  T_N=$((T_N + 1))
  T_FAIL=$((T_FAIL + 1))
  echo "not ok $T_N - $*"
}

# check LABEL COMMAND...: pass when the command succeeds.
check() {
  _l=$1
  shift
  if "$@"; then ok "$_l"; else not_ok "$_l"; fi
}

diag() { sed 's/^/# /'; }

# contains TEXT NEEDLE / lacks TEXT NEEDLE: fixed-string search.
contains() { printf '%s\n' "$1" | grep -qF -- "$2"; }
lacks() { ! contains "$1" "$2"; }
# matches TEXT REGEX: basic regular expression search.
matches() { printf '%s\n' "$1" | grep -q -- "$2"; }
# rc_contains RC WANT TEXT NEEDLE: exit code and output together.
rc_contains() { [ "$1" -eq "$2" ] && contains "$3" "$4"; }
# same A B...: every argument after the first equals the first.
same() {
  _a=$1
  shift
  for _b in "$@"; do [ "$_a" = "$_b" ] || return 1; done
}
# trace_of FILE: the lines of FILE joined by spaces.
trace_of() { tr '\n' ' ' <"$1"; }

finish() {
  echo "1..$T_N"
  [ "$T_FAIL" -eq 0 ]
}

# One host, "h1", whose file system root is $TD/live. The declared state is
# $TD/state. `declare_*` writes the same thing on both sides, so a fresh
# fixture always verifies green; a test then breaks the live side.

LIVE="$TD/live"
STATE="$TD/state"

fx_init() {
  rm -rf "$LIVE" "$STATE"
  mkdir -p "$LIVE/etc/systemd/system" "$STATE"
  printf '# name transport address\nh1  local  %s\n' "$LIVE" >"$STATE/inventory.tsv"
  : >"$STATE/checks.tsv"
}

# declare_file PATH MODE CONTENT
declare_file() {
  mkdir -p "$(dirname "$LIVE$1")" "$(dirname "$STATE/files/h1$1")"
  printf '%s' "$3" >"$LIVE$1"
  chmod "$2" "$LIVE$1"
  printf '%s' "$3" >"$STATE/files/h1$1"
  printf 'h1 file %s %s\n' "$1" "$2" >>"$STATE/checks.tsv"
}

# declare_unit NAME enabled|disabled CONTENT
declare_unit() {
  mkdir -p "$STATE/units/h1"
  printf '%s' "$3" >"$LIVE/etc/systemd/system/$1"
  printf '%s' "$3" >"$STATE/units/h1/$1"
  if [ "$2" = enabled ]; then
    mkdir -p "$LIVE/etc/systemd/system/multi-user.target.wants"
    ln -s "/etc/systemd/system/$1" "$LIVE/etc/systemd/system/multi-user.target.wants/$1"
  fi
  printf 'h1 unit %s %s\n' "$1" "$2" >>"$STATE/checks.tsv"
}

# declare_env PATH LIVE_CONTENT KEY...
declare_env() {
  _p=$1 _c=$2
  shift 2
  mkdir -p "$(dirname "$LIVE$_p")" "$(dirname "$STATE/envkeys/h1$_p")"
  printf '%s' "$_c" >"$LIVE$_p"
  chmod 600 "$LIVE$_p"
  printf '%s\n' "$@" >"$STATE/envkeys/h1$_p.keys"
  printf 'h1 envkeys %s -\n' "$_p" >>"$STATE/checks.tsv"
}

# verify: run the verifier on the fixture. Sets OUT (stdout+stderr) and RC.
verify() {
  OUT=$("$DV" -s "$STATE" 2>&1)
  RC=$?
}

# negative KIND LABEL BREAK EXPECT
#
# The contract every check must honour, in three steps:
#   1. the fixture as declared verifies GREEN (exit 0), so the failure in
#      step 3 can only come from the break;
#   2. BREAK (a shell snippet, run with $LIVE pointing at the host root)
#      damages the live side;
#   3. the verifier now exits 1 and its output contains EXPECT.
# A passing case is written to the ledger; tests/coverage.sh then refuses a
# suite in which any check kind has no passing negative case.

negative_core() {
  _k=$1 _break=$3 _expect=$4
  verify
  if [ "$RC" -ne 0 ]; then
    echo "fixture was not green before the break (exit $RC)" | diag
    printf '%s\n' "$OUT" | diag
    return 1
  fi
  (cd "$LIVE" && LIVE=$LIVE sh -c "$_break") || {
    echo "break command failed" | diag
    return 1
  }
  verify
  if [ "$RC" -ne 1 ]; then
    echo "expected exit 1 after the break, got $RC" | diag
    printf '%s\n' "$OUT" | diag
    return 1
  fi
  if ! printf '%s\n' "$OUT" | grep -qF -- "$_expect"; then
    echo "output does not mention: $_expect" | diag
    printf '%s\n' "$OUT" | diag
    return 1
  fi
  printf '%s\n' "$OUT" | grep -q "FAIL  h1 *$_k " || {
    echo "no FAIL line for kind $_k" | diag
    return 1
  }
  return 0
}

negative() {
  if negative_core "$@"; then
    printf 'neg %s %s\n' "$1" "$2" >>"$LEDGER"
    ok "negative [$1] $2"
  else
    not_ok "negative [$1] $2"
  fi
}
