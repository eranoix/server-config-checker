#!/bin/sh
set -eu
install -m 600 /keys/client /tmp/client
DRIFT_SSH_KEY=/tmp/client
DRIFT_KNOWN_HOSTS=/keys/known_hosts
export DRIFT_SSH_KEY DRIFT_KNOWN_HOSTS
exec "$@"
