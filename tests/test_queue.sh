#!/bin/sh
# bin/drift-queue: FIFO order, concurrent submits, rejection, crash recovery.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

QUEUE="$ROOT/bin/drift-queue"
R="$TD/repo"
# A private git environment: no user config, a fixed test identity.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
HOME=$TD
GIT_CONFIG_NOSYSTEM=1
GIT_AUTHOR_NAME="Test Runner" GIT_AUTHOR_EMAIL=test@example.com
GIT_COMMITTER_NAME="Test Runner" GIT_COMMITTER_EMAIL=test@example.com
DRIFT_LOCK_POLL=0.05
# The gate: a change that adds a file named BROKEN is red.
DRIFT_QUEUE_GATE='test ! -e BROKEN'
export HOME GIT_CONFIG_NOSYSTEM GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL DRIFT_LOCK_POLL DRIFT_QUEUE_GATE

g() { git -C "$R" "$@"; }

new_repo() {
  rm -rf "$R"
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R" && g checkout -q -b main; }
  printf 'line one\n' >"$R/shared.txt"
  g add shared.txt && g commit -q -m "initial"
}

# branch NAME FILE CONTENT: a branch off main that writes one file.
branch() {
  g checkout -q -b "$1" main
  printf '%s\n' "$3" >"$R/$2"
  g add "$2" && g commit -q -m "change $1"
  g checkout -q main
}

log_subjects() { g log --first-parent --format=%s main | tr '\n' '|'; }

# --- FIFO: tickets are merged in the order they were taken
new_repo
branch c c.txt c; branch a a.txt a; branch b b.txt b
"$QUEUE" -r "$R" submit c >/dev/null
"$QUEUE" -r "$R" submit a >/dev/null
"$QUEUE" -r "$R" submit b >/dev/null
check "list shows tickets in submission order" \
  same "$("$QUEUE" -r "$R" list | tr '\n' ' ')" "#1 c #2 a #3 b "
out=$("$QUEUE" -r "$R" run 2>&1); rc=$?
check "run merges everything (exit 0)" [ "$rc" -eq 0 ]
check "history records c, a, b in that order, one --no-ff merge each" \
  [ "$(log_subjects)" = "queue #3: merge b|queue #2: merge a|queue #1: merge c|initial|" ]
check "every queue commit is a real merge (two parents)" \
  [ "$(g log --first-parent --format=%p -n 3 main | awk 'NF == 2' | wc -l | tr -d ' ')" -eq 3 ]
check "queue is empty afterwards" [ -z "$("$QUEUE" -r "$R" list)" ]

# --- concurrency: 8 submitters at once get 8 distinct numbers
new_repo
for i in 1 2 3 4 5 6 7 8; do branch "p$i" "p$i.txt" "$i"; done
for i in 1 2 3 4 5 6 7 8; do "$QUEUE" -r "$R" submit "p$i" >"$TD/sub.$i" 2>&1 & done
wait
nums=$(cat "$TD"/sub.* | sed -n 's/^queued #\([0-9]*\) .*/\1/p' | sort -n | tr '\n' ' ')
check "8 concurrent submits get tickets 1..8, no duplicates, no gaps" [ "$nums" = "1 2 3 4 5 6 7 8 " ]
"$QUEUE" -r "$R" run >/dev/null 2>&1
order_q=$(g log --first-parent --reverse --format=%s main | sed -n 's/^queue #[0-9]*: merge //p' | tr '\n' ' ')
order_t=$(for i in 1 2 3 4 5 6 7 8; do sed -n "s/^queued #\([0-9]*\) \(.*\)/\1 \2/p" "$TD/sub.$i"; done | sort -n | awk '{printf "%s ", $2}')
check "merge order equals ticket order" [ "$order_q" = "$order_t" ]

# --- a red gate rejects the ticket, restores main, and does not block the line
new_repo
branch good1 g1.txt ok; branch broken BROKEN x; branch good2 g2.txt ok
for b in good1 broken good2; do "$QUEUE" -r "$R" submit "$b" >/dev/null; done
out=$("$QUEUE" -r "$R" run 2>&1); rc=$?
check "a rejected ticket makes run exit 1" [ "$rc" -eq 1 ]
check "the broken ticket is reported as rejected by the gate" \
  contains "$out" "REJECTED #2 broken: gate failed"
check "the ticket after it is still merged" \
  [ "$(log_subjects)" = "queue #3: merge good2|queue #1: merge good1|initial|" ]
check "nothing of the broken change is left on main" [ ! -e "$R/BROKEN" ]
check "working tree is clean after a rejection" [ -z "$(g status --porcelain --untracked-files=no)" ]

# --- a conflict is a rejection too, and main is untouched
new_repo
g checkout -q -b left main; printf 'left\n' >"$R/shared.txt"; g commit -q -am left; g checkout -q main
g checkout -q -b right main; printf 'right\n' >"$R/shared.txt"; g commit -q -am right; g checkout -q main
"$QUEUE" -r "$R" submit left >/dev/null; "$QUEUE" -r "$R" submit right >/dev/null
out=$("$QUEUE" -r "$R" run 2>&1)
check "the second of two conflicting tickets is rejected" \
  contains "$out" "REJECTED #2 right: merge conflict"
check "main holds the first ticket's content" [ "$(cat "$R/shared.txt")" = "left" ]

# --- guards
new_repo; branch x x.txt x
"$QUEUE" -r "$R" submit x >/dev/null
"$QUEUE" -r "$R" submit x >/dev/null 2>&1; rc=$?
check "a branch cannot be queued twice" [ "$rc" -eq 2 ]
"$QUEUE" -r "$R" submit no-such-branch >/dev/null 2>&1; rc=$?
check "a missing branch cannot be queued" [ "$rc" -eq 2 ]
echo dirty >>"$R/shared.txt"
"$QUEUE" -r "$R" run >/dev/null 2>&1; rc=$?
check "run refuses a tree with uncommitted tracked changes" [ "$rc" -eq 2 ]
g checkout -q -- shared.txt

# --- stale queue lock: a submitter that died holding it does not wedge the queue
new_repo; branch s s.txt s
L="$(g rev-parse --absolute-git-dir)/drift-queue/locks/queue.lock"
mkdir -p "$L"
sh -c 'exit 0' & dp=$!; wait "$dp"
printf 'host=%s\npid=%s\nchild=\nsince=1\ntoken=x\n' "$(hostname 2>/dev/null || uname -n)" "$dp" >"$L/owner"
out=$("$QUEUE" -r "$R" submit s 2>&1); rc=$?
check "submit recovers a stale queue lock" [ "$rc" -eq 0 ]
check "... and says so" contains "$out" "recovered stale lock queue"

# --- crash in the middle of a merge: kill -9 everything while the gate runs
new_repo; branch slow slow.txt slow
"$QUEUE" -r "$R" submit slow >/dev/null
before=$(g rev-parse HEAD)
DRIFT_QUEUE_GATE="echo \$\$ >'$TD/gatepid'; exec sleep 30" "$QUEUE" -r "$R" run >/dev/null 2>&1 &
lockpid=$!
n=0
while [ ! -s "$TD/gatepid" ] && [ $n -lt 100 ]; do sleep 0.05; n=$((n + 1)); done
owner="$(g rev-parse --absolute-git-dir)/drift-queue/locks/merge.lock/owner"
runpid=$(sed -n 's/^child=//p' "$owner")
kill -9 "$lockpid" "$runpid" "$(cat "$TD/gatepid")" 2>/dev/null
wait "$lockpid" 2>/dev/null
sleep 0.2
check "the crash left main on an unverified merge commit" [ "$(g rev-parse HEAD)" != "$before" ]
out=$("$QUEUE" -r "$R" run 2>&1); rc=$?
check "the next run recovers the stale merge lock" \
  contains "$out" "recovered stale lock merge"
check "... detects the interrupted merge and resets main" \
  contains "$out" "found an interrupted merge of #1"
check "... then exits 0" [ "$rc" -eq 0 ]
check "... and merges the ticket for real, exactly once" \
  same "$(log_subjects)" "queue #1: merge slow|initial|"

finish
