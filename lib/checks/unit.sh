# shellcheck shell=sh
# check `unit`: a systemd unit file and whether it is enabled.
#
#   HOST  unit  name.service  enabled|disabled
#
# Declared content lives at $DRIFT_STATE/units/HOST/name.service. See
# lib/remote/unit.sh for how "enabled" is read without calling systemctl.

check_unit() {
  _h=$1 _u=$2 _want=$3
  valid_unit "$_u" || { echo "invalid unit name"; return 2; }
  case $_want in
    enabled | disabled) ;;
    *) echo "expect must be enabled or disabled, got $_want"; return 2 ;;
  esac
  _decl="$DRIFT_STATE/units/$_h/$_u"
  [ -f "$_decl" ] || { echo "no declared unit at units/$_h/$_u"; return 2; }

  _raw="$DRIFT_TMP/unit.raw"
  remote "$_h" "$DRIFT_LIB/remote/unit.sh" "$_u" >"$_raw" 2>"$DRIFT_TMP/stderr"
  _rc=$?
  if [ "$_rc" -ne 0 ]; then
    remote_status "$_rc"
    echo
    [ "$_rc" -eq 3 ] && return 1
    sed -n '1,3p' "$DRIFT_TMP/stderr"
    return 2
  fi

  _live="$DRIFT_TMP/unit.live"
  _got=$(sed -n '1s/^state //p' "$_raw")
  sed '1d' "$_raw" >"$_live"

  _bad=0
  if [ "$_got" != "$_want" ]; then
    echo "state: declared $_want, live $_got"
    _bad=1
  fi
  if ! cmp -s "$_decl" "$_live"; then
    echo "unit file differs:"
    diff -u "$_decl" "$_live" |
      sed -e "1s|.*|--- declared  units/$_h/$_u|" -e "2s|.*|+++ live      $_h:/etc/systemd/system/$_u|"
    _bad=1
  fi
  return "$_bad"
}
