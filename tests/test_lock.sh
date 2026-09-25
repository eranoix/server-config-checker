#!/bin/sh
# shellcheck disable=SC2016 # break snippets expand later, in the shell that runs them
# bin/drift-lock: named critical sections, timeouts and stale-lock recovery.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

LOCK="$ROOT/bin/drift-lock"
DRIFT_LOCK_DIR="$TD/locks"
DRIFT_LOCK_POLL=0.05
export DRIFT_LOCK_DIR DRIFT_LOCK_POLL
me=$(hostname 2>/dev/null || uname -n)

dead_pid() {
  sh -c 'exit 0' &
  _d=$!
  wait "$_d"
  echo "$_d"
}

# fake_owner PID CHILD [HOST]: a lock left behind by someone else.
fake_owner() {
  mkdir -p "$DRIFT_LOCK_DIR/verify.lock"
  printf 'name=verify\nhost=%s\npid=%s\nchild=%s\nsince=1\ntoken=fake\ncommand=fake\n' \
    "${3:-$me}" "$1" "$2" >"$DRIFT_LOCK_DIR/verify.lock/owner"
}

ran() { [ "$rc" -eq 0 ] && [ -e "$TD/ran" ]; }
blocked() { [ "$rc" -eq 2 ] && [ ! -e "$TD/ran" ]; }

# --- names are a closed list
out=$("$LOCK" -t 1 verfy -- touch "$TD/ran" 2>&1); rc=$?
check "a mistyped lock name is refused (exit 2)" [ "$rc" -eq 2 ]
check "... and the command does not run" [ ! -e "$TD/ran" ]
check "... and the error lists the known names" contains "$out" "known: queue merge verify"

# --- exit status and release
"$LOCK" verify -- sh -c 'exit 7'; rc=$?
check "the command's exit code is passed through" [ "$rc" -eq 7 ]
check "the lock is released after a failing command" [ ! -d "$DRIFT_LOCK_DIR/verify.lock" ]
out=$(echo "through stdin" | "$LOCK" verify -- cat)
check "stdin reaches the command" [ "$out" = "through stdin" ]

# --- mutual exclusion: 6 concurrent holders, never two inside at once
: >"$TD/trace"
echo 0 >"$TD/counter"
i=0
while [ $i -lt 6 ]; do
  "$LOCK" -t 30 verify -- sh -c '
    echo in >>"$1"; n=$(cat "$2"); sleep 0.1; echo $((n + 1)) >"$2"; echo out >>"$1"
  ' _ "$TD/trace" "$TD/counter" &
  i=$((i + 1))
done
wait
check "6 concurrent increments under the lock give 6" [ "$(cat "$TD/counter")" -eq 6 ]
check "the trace strictly alternates in/out (no overlap)" \
  same "$(trace_of "$TD/trace")" "in out in out in out in out in out in out "

# --- timeout: the command must NOT run
"$LOCK" verify -- sleep 3 &
holder=$!
sleep 0.5
start=$(date +%s)
"$LOCK" -t 1 verify -- touch "$TD/ran" 2>"$TD/err"; rc=$?
check "a held lock times out with exit 2" [ "$rc" -eq 2 ]
check "... without running the command" [ ! -e "$TD/ran" ]
check "... after roughly the timeout" [ $(($(date +%s) - start)) -le 3 ]
check "... and says who holds it" grep -q "held by: $me pid $holder" "$TD/err"
kill "$holder" 2>/dev/null
wait "$holder" 2>/dev/null
check "SIGTERM to a holder releases the lock" [ ! -d "$DRIFT_LOCK_DIR/verify.lock" ]

# --- stale: holder and its command are both gone
fake_owner "$(dead_pid)" "$(dead_pid)"
"$LOCK" -t 5 verify -- touch "$TD/ran" 2>"$TD/err"; rc=$?
check "a lock whose holder died is recovered" ran
check "... and the recovery is announced" grep -q "recovered stale lock verify" "$TD/err"
rm -f "$TD/ran"

# --- not stale: the holder is alive
sleep 30 &
live=$!
fake_owner "$live" ""
"$LOCK" -t 1 verify -- touch "$TD/ran" 2>/dev/null; rc=$?
check "a lock held by a live process is not stolen" blocked

# --- not stale: holder killed with -9 but its command still running
fake_owner "$(dead_pid)" "$live"
"$LOCK" -t 1 verify -- touch "$TD/ran" 2>/dev/null; rc=$?
check "holder gone but command alive: still not stolen" blocked
kill "$live"; wait "$live" 2>/dev/null
rm -rf "$DRIFT_LOCK_DIR/verify.lock"

# --- the real thing: kill -9 a running drift-lock, then kill its command
"$LOCK" verify -- sh -c 'echo $$ >"$1"; exec sleep 30' _ "$TD/childpid" &
holder=$!
n=0
while [ ! -s "$TD/childpid" ] && [ $n -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
kill -9 "$holder"; wait "$holder" 2>/dev/null
"$LOCK" -t 1 verify -- true 2>/dev/null; rc=$?
check "after kill -9 of drift-lock, its live command keeps the lock" [ "$rc" -eq 2 ]
kill "$(cat "$TD/childpid")"
"$LOCK" -t 5 verify -- touch "$TD/ran" 2>"$TD/err"; rc=$?
check "once the command is gone too, the next caller recovers the lock" ran
rm -f "$TD/ran"

# --- another host: cannot check its process, so never auto-recovered
fake_owner "$(dead_pid)" "" "other-host.example.com"
"$LOCK" -t 1 verify -- touch "$TD/ran" 2>"$TD/err"; rc=$?
check "a lock held from another host is not stolen" blocked
check "... and the wait says so" grep -q "held from host other-host.example.com" "$TD/err"
rm -rf "$DRIFT_LOCK_DIR/verify.lock"

# --- a lock directory with no owner file (holder died between mkdir and write)
mkdir -p "$DRIFT_LOCK_DIR/verify.lock"
DRIFT_LOCK_GRACE=1 "$LOCK" -t 5 verify -- touch "$TD/ran" 2>"$TD/err"; rc=$?
check "an ownerless lock is recovered after the grace period" ran
rm -f "$TD/ran"

# --- a recovery guard left behind by a waiter that died mid-recovery
fake_owner "$(dead_pid)" "$(dead_pid)"
mkdir "$DRIFT_LOCK_DIR/verify.steal"
DRIFT_LOCK_GRACE=1 "$LOCK" -t 5 verify -- touch "$TD/ran" 2>"$TD/err"; rc=$?
check "an abandoned recovery guard is cleared and the lock recovered" ran
check "... and both steps are announced" \
  sh -c 'grep -q "removing guard" "$1" && grep -q "recovered stale lock" "$1"' _ "$TD/err"
rm -f "$TD/ran"

# --- two waiters racing to recover the same stale lock: exactly one runs at a time
fake_owner "$(dead_pid)" "$(dead_pid)"
: >"$TD/trace"
for _ in 1 2 3 4; do
  "$LOCK" -t 10 verify -- sh -c 'echo in >>"$1"; sleep 0.2; echo out >>"$1"' _ "$TD/trace" 2>>"$TD/race.err" &
done
wait
check "4 waiters recovering one stale lock never overlap" \
  same "$(trace_of "$TD/trace")" "in out in out in out in out "
same "$(trace_of "$TD/trace")" "in out in out in out in out " || cat "$TD/trace" "$TD/race.err" | diag

finish
