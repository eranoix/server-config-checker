# shellcheck shell=sh

check_file() {
  _h=$1 _p=$2 _mode=$3
  valid_path "$_p" || { echo "invalid path"; return 2; }
  if looks_like_env_file "$_p"; then
    echo "refused: $_p may hold secrets, declare it as envkeys instead"
    return 2
  fi
  _decl="$DRIFT_STATE/files/$_h$_p"
  [ -f "$_decl" ] || { echo "no declared content at files/$_h$_p"; return 2; }

  _raw="$DRIFT_TMP/file.raw"
  remote "$_h" "$DRIFT_LIB/remote/file.sh" "$_p" >"$_raw" 2>"$DRIFT_TMP/stderr"
  _rc=$?
  if [ "$_rc" -ne 0 ]; then
    remote_status "$_rc"
    echo
    case $_rc in 3 | 5) return 1 ;; esac
    sed -n '1,3p' "$DRIFT_TMP/stderr"
    return 2
  fi

  _live="$DRIFT_TMP/file.live"
  _got=$(sed -n '1s/^mode //p' "$_raw")
  sed '1d' "$_raw" >"$_live"

  _bad=0
  if [ "$_mode" != "-" ] && [ "$(strip_zeros "$_got")" != "$(strip_zeros "$_mode")" ]; then
    echo "mode: declared $_mode, live 0$(strip_zeros "$_got")"
    _bad=1
  fi
  if ! cmp -s "$_decl" "$_live"; then
    echo "content differs:"
    diff -u "$_decl" "$_live" |
      sed -e "1s|.*|--- declared  files/$_h$_p|" -e "2s|.*|+++ live      $_h:$_p|"
    _bad=1
  fi
  return "$_bad"
}
