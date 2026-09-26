# shellcheck shell=sh
# lib/common.sh: helpers shared by bin/config-check and the check modules.
#
# Everything here is POSIX sh. Names that come from the declared state (host
# names, paths, unit names) are validated against a closed character set
# before they get anywhere near a shell or an ssh command line. That is what
# lets the transport pass them as plain arguments without quoting tricks.

# Printed on stderr, never mixed into the report on stdout.
die() {
  printf 'config-check: %s\n' "$*" >&2
  exit 2
}

# valid_host NAME: lower case letters, digits, dot and dash.
valid_host() {
  case $1 in
    '' | [!a-z0-9]* | *[!a-z0-9.-]*) return 1 ;;
  esac
  return 0
}

# valid_path PATH: absolute, conservative characters, no "..".
valid_path() {
  case $1 in
    /*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[!A-Za-z0-9._/-]* | *..*) return 1 ;;
  esac
  return 0
}

# valid_unit NAME: a systemd unit file name with a known suffix.
valid_unit() {
  case $1 in
    */* | *[!A-Za-z0-9@._-]*) return 1 ;;
  esac
  case $1 in
    ?*.service | ?*.timer | ?*.socket | ?*.path | ?*.mount) return 0 ;;
  esac
  return 1
}

# looks_like_env_file PATH: files that may hold secrets are only ever compared
# by key name. The `file` check refuses them so a content diff can never print
# a value.
looks_like_env_file() {
  _b=${1##*/}
  case $_b in
    *.env | .env.* | *.env.* | *secret* | *credential* | *.key | *.pem) return 0 ;;
  esac
  return 1
}

# strip_zeros MODE: "0644" and "644" compare equal.
strip_zeros() {
  _m=$1
  while :; do
    case $_m in
      0?*) _m=${_m#0} ;;
      *) break ;;
    esac
  done
  printf '%s' "$_m"
}

# indent: prefix every line of stdin so details sit under their status line.
indent() {
  sed 's/^/      /'
}

# inventory_lookup HOST: prints "transport address" for HOST, or fails.
inventory_lookup() {
  awk -v h="$1" '
    /^[[:space:]]*(#|$)/ { next }
    $1 == h { print $2, $3; found = 1; exit }
    END { exit found ? 0 : 1 }
  ' "$DRIFT_INVENTORY"
}

# remote HOST SCRIPT [ARG...]
#
# Runs one of the read-only scripts in lib/remote/ on HOST. The script travels
# on stdin (`sh -s`), so nothing is installed on the target and nothing needs
# to exist there except a POSIX shell. Arguments are validated by the caller.
#
# Transports:
#   ssh   ADDRESS is user@host or user@host:port
#   local ADDRESS is a directory used as the file system root. This is what
#         the offline test suite uses; it runs the very same remote script.
remote() {
  _rh=$1 _rs=$2
  shift 2
  _line=$(inventory_lookup "$_rh") || {
    printf 'host %s is not in the inventory\n' "$_rh" >&2
    return 2
  }
  _rt=${_line%% *}
  _ra=${_line#* }
  case $_rt in
    ssh)
      _port=22
      _dest=$_ra
      case $_ra in
        *:*) _port=${_ra##*:} _dest=${_ra%:*} ;;
      esac
      # shellcheck disable=SC2086 # DRIFT_SSH_OPTS is a word list on purpose
      ssh -p "$_port" \
        -o BatchMode=yes \
        -o ConnectTimeout="${DRIFT_SSH_TIMEOUT:-5}" \
        ${DRIFT_SSH_KEY:+-o IdentitiesOnly=yes -i "$DRIFT_SSH_KEY"} \
        ${DRIFT_KNOWN_HOSTS:+-o StrictHostKeyChecking=yes -o UserKnownHostsFile="$DRIFT_KNOWN_HOSTS"} \
        ${DRIFT_SSH_OPTS:-} \
        "$_dest" sh -s -- "$@" <"$_rs"
      ;;
    local)
      DRIFT_ROOT=$_ra sh -s -- "$@" <"$_rs"
      ;;
    *)
      printf 'host %s has unknown transport %s\n' "$_rh" "$_rt" >&2
      return 2
      ;;
  esac
}

# remote_status CODE: turns the exit codes of lib/remote/*.sh into words.
remote_status() {
  case $1 in
    3) printf 'missing on host' ;;
    4) printf 'not readable by the verifier user' ;;
    5) printf 'not a regular file' ;;
    255) printf 'ssh connection failed' ;;
    *) printf 'remote command exited %s' "$1" ;;
  esac
}
