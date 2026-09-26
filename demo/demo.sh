#!/bin/sh
# demo/demo.sh: the whole story in one command (`make demo`).
#
#   1. generate throwaway ssh keys (client and host keys) for this run only
#   2. start two fake servers, web-1 and worker-1, with docker compose
#   3. run the verifier: everything matches, exit 0
#   4. make the kind of changes people make by hand during an incident
#   5. run the verifier again: drift is found, shown as a diff, exit 1
#   6. tear everything down: containers, network, built images, keys
#
# The demo itself fails (non-zero) unless step 3 is green, step 5 is red, and
# no env value appears anywhere in the output.
#
# Environment:
#   DEMO_KEEP=1      leave the stack running and keep the keys (for poking at)
#   DEMO_PROJECT     compose project name (default: a random, unique one)

set -u

here=$(cd "$(dirname "$0")" && pwd) || exit 2
suffix=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')
project=${DEMO_PROJECT:-configcheck-demo-$suffix}
work=$(mktemp -d "${TMPDIR:-/tmp}/drift-demo.XXXXXX") || exit 2
DEMO_KEYS="$work/keys"
export DEMO_KEYS

bold=$(printf '\033[1m') off=$(printf '\033[0m')
[ -t 1 ] || { bold=''; off=''; }
step() { printf '\n%s==> %s%s\n' "$bold" "$*" "$off"; }
die() { printf 'demo: %s\n' "$*" >&2; exit 1; }

# Keep compose's progress lines out of the verifier output where supported.
progress=''
docker compose --progress quiet version >/dev/null 2>&1 && progress='--progress quiet'
# shellcheck disable=SC2086 # $progress is empty or two words
dc() { docker compose $progress -p "$project" -f "$here/compose.yaml" "$@"; }

cleanup() {
  if [ "${DEMO_KEEP:-0}" = 1 ]; then
    printf '\nDEMO_KEEP=1: stack %s left running, keys in %s\n' "$project" "$work"
    printf 'remove with: DEMO_KEYS=%s docker compose -p %s -f %s --profile run down -v --rmi local\n' \
      "$DEMO_KEYS" "$project" "$here/compose.yaml"
    return
  fi
  step "tearing down (containers, network, images built for $project)"
  dc --profile run down -v --rmi local --remove-orphans >/dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

command -v docker >/dev/null || die "docker is required"
command -v ssh-keygen >/dev/null || die "ssh-keygen is required"

# ---------------------------------------------------------------- 1. keys
step "generating throwaway ssh keys for this run"
mkdir -p "$DEMO_KEYS/control"
ssh-keygen -q -t ed25519 -N '' -C "drift-demo-client" -f "$work/client" || die "ssh-keygen failed"
cp "$work/client" "$DEMO_KEYS/control/client"
: >"$DEMO_KEYS/control/known_hosts"
for h in web-1 worker-1; do
  mkdir -p "$DEMO_KEYS/$h"
  ssh-keygen -q -t ed25519 -N '' -C "drift-demo-$h" -f "$DEMO_KEYS/$h/host_ed25519" || die "ssh-keygen failed"
  cp "$work/client.pub" "$DEMO_KEYS/$h/client.pub"
  # Pin each host key: the verifier runs with StrictHostKeyChecking=yes.
  printf '%s %s\n' "$h" "$(cut -d' ' -f1,2 "$DEMO_KEYS/$h/host_ed25519.pub")" >>"$DEMO_KEYS/control/known_hosts"
done
chmod -R a+rX "$DEMO_KEYS"
echo "keys in $work (deleted at the end)"

# ---------------------------------------------------------------- 2. hosts
step "starting web-1 and worker-1 (compose project $project)"
dc --profile run build -q || die "build failed"
dc up -d web-1 worker-1 || die "compose up failed"

# shellcheck disable=SC2016 # expanded inside the control container
dc --profile run run --rm --no-deps -T control sh -c '
  for h in web-1 worker-1; do
    n=0
    until ssh -o BatchMode=yes -o ConnectTimeout=2 -o IdentitiesOnly=yes -i "$DRIFT_SSH_KEY" \
          -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$DRIFT_KNOWN_HOSTS" \
          "drift@$h" true 2>/dev/null; do
      n=$((n + 1)); [ $n -lt 60 ] || { echo "sshd on $h did not come up" >&2; exit 1; }
      sleep 0.5
    done
    echo "$h: sshd ready, host key pinned"
  done' || die "hosts did not come up"

verify() {
  dc --profile run run --rm --no-deps -T -e DRIFT_COLOR="${DRIFT_COLOR:-auto}" control \
    bin/config-check -s demo/state
}

# ---------------------------------------------------------------- 3. green
step "verifying declared state against the live hosts"
green=$(verify 2>&1)
rc=$?
printf '%s\n' "$green"
[ "$rc" -eq 0 ] || die "expected a clean run (exit 0), got exit $rc"

# ---------------------------------------------------------------- 4. drift
step "03:12, an incident: someone fixes things by hand, straight on the servers"
cat <<'EOF'
  web-1:    raises client_max_body_size to 512m in the nginx site
  worker-1: loosens worker.conf to 0666 while debugging
  worker-1: drops QUEUE_URL from worker.env and adds DEBUG_BYPASS_AUTH
  worker-1: disables cleanup.timer "for now"
EOF
dc exec -T web-1 sed -i 's/client_max_body_size 10m/client_max_body_size 512m/' /etc/nginx/http.d/site.conf
dc exec -T worker-1 chmod 0666 /etc/app/worker.conf
dc exec -T worker-1 sh -c "sed -i '/^QUEUE_URL=/d' /etc/app/worker.env && echo 'DEBUG_BYPASS_AUTH=demo-value-yes' >>/etc/app/worker.env"
dc exec -T worker-1 rm /etc/systemd/system/timers.target.wants/cleanup.timer

# ---------------------------------------------------------------- 5. red
step "verifying again, the next morning"
red=$(verify 2>&1)
rc=$?
printf '%s\n' "$red"
[ "$rc" -eq 1 ] || die "expected drift (exit 1), got exit $rc"

# DRIFT_COLOR=always colours the report; the checks below read it without colour.
esc=$(printf '\033')
red_plain=$(printf '%s\n' "$red" | sed "s/${esc}\\[[0-9;]*m//g")
drifted=$(printf '%s\n' "$red_plain" | grep -c '^FAIL')
[ "$drifted" -eq 4 ] || die "expected 4 drifted checks, got $drifted"
for needle in '+    client_max_body_size 512m;' 'mode: declared 0644, live 0666' \
  'declared but missing on host: QUEUE_URL' 'on host but not declared:     DEBUG_BYPASS_AUTH' \
  'state: declared enabled, live disabled'; do
  printf '%s\n' "$red_plain" | grep -qF -- "$needle" || die "drift report is missing: $needle"
done
# Every env value in the fixtures contains "demo-value". None may be printed.
if printf '%s\n%s\n' "$green" "$red" | grep -q 'demo-value'; then
  die "an env value leaked into the output"
fi

step "demo passed: green, then 4 drifted checks with diffs, and no env value printed"
