# shellcheck shell=sh

check_envkeys() {
  _h=$1 _p=$2
  valid_path "$_p" || { echo "invalid path"; return 2; }
  _decl="$DRIFT_STATE/envkeys/$_h$_p.keys"
  [ -f "$_decl" ] || { echo "no declared keys at envkeys/$_h$_p.keys"; return 2; }

  _want="$DRIFT_TMP/keys.want"
  _live="$DRIFT_TMP/keys.live"
  grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$_decl" | LC_ALL=C sort -u >"$_want"

  remote "$_h" "$DRIFT_LIB/remote/envkeys.sh" "$_p" >"$_live" 2>/dev/null
  _rc=$?
  if [ "$_rc" -ne 0 ]; then
    remote_status "$_rc"
    echo " (remote stderr is never shown for envkeys)"
    [ "$_rc" -eq 3 ] && return 1
    return 2
  fi

  _missing=$(LC_ALL=C comm -23 "$_want" "$_live" | tr '\n' ' ')
  _extra=$(LC_ALL=C comm -13 "$_want" "$_live" | tr '\n' ' ')
  _bad=0
  if [ -n "$_missing" ]; then
    echo "declared but missing on host: ${_missing% }"
    _bad=1
  fi
  if [ -n "$_extra" ]; then
    echo "on host but not declared:     ${_extra% }"
    _bad=1
  fi
  return "$_bad"
}
