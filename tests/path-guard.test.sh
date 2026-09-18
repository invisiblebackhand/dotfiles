#!/usr/bin/env bash
# tests/path-guard.test.sh - regression test for the PATH self-heal guard that
# configuration.nix installs into /etc/zshenv through programs.zsh.shellInit.
#
# The 2026-09-18 incident: Terminal.app was relaunched by an AppleScript from an
# agent shell and inherited nix-darwin's __NIX_DARWIN_SET_ENVIRONMENT_DONE=1
# without the PATH that goes with it. /etc/zshenv trusted the flag, skipped
# set-environment, and every new window was born with PATH=/usr/bin:/bin plus
# the ~/.zshrc prepends: no nix directories, no Homebrew.
#
# This test extracts the guard text from configuration.nix, substitutes the
# set-environment file that this host's /etc/zshenv references for the Nix
# interpolation, and runs it at the equivalent position (first thing after
# /etc/zshenv, before ~/.zshenv and ~/.zshrc) through a throwaway ZDOTDIR.
# Nothing system-wide is touched: the guard log goes to a temporary
# XDG_STATE_HOME. Requires a nix-darwin host with /bin/zsh; skips elsewhere.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SETENV=$(grep -o '/nix/store/[^ ]*-set-environment' /etc/zshenv 2>/dev/null | head -1 || true)
if [ -z "$SETENV" ] || [ ! -f /bin/zsh ]; then
  pass "path-guard: skipped (not a nix-darwin host)"
  exit 0
fi

TMP=$(dotfiles_test_tmproot path-guard)
ZD="$TMP/zdot"
STATE="$TMP/state"
LOG="$STATE/nix-darwin-path-guard.log"
GUARD="$TMP/guard.zsh"
mkdir -p "$ZD" "$STATE"

# --- extract the guard exactly as configuration.nix ships it -------------------

sed -n "/programs.zsh.shellInit = ''\$/,/^  '';\$/p" "$ROOT/configuration.nix" \
  | sed '1d;$d' \
  | sed -e "s|\\\${config.system.build.setEnvironment}|$SETENV|g" -e "s|''\\\${|\${|g" \
  > "$GUARD"
grep -q '__nix_darwin_path_guard' "$GUARD" || fail "guard text not found in configuration.nix"
grep -q "$SETENV" "$GUARD" || fail "set-environment path was not substituted into the guard"
grep -q "''" "$GUARD" && fail "unexpanded Nix escape left in the guard text"
/bin/zsh -n "$GUARD" || fail "guard text does not parse as zsh"
pass "path-guard: guard text extracted and parses"

{
  printf 'source %q\n' "$GUARD"
  [ -f "$HOME/.zshenv" ] && printf 'source %q\n' "$HOME/.zshenv"
} > "$ZD/.zshenv"
{
  [ -f "$HOME/.zshrc" ] && printf 'source %q\n' "$HOME/.zshrc"
  :
} > "$ZD/.zshrc"

run_zsh() {
  # usage: run_zsh [VAR=value ...] /bin/zsh <flags>; stderr lands in $TMP/err
  env -i HOME="$HOME" USER="$USER" TERM=xterm ZDOTDIR="$ZD" XDG_STATE_HOME="$STATE" \
    "$@" 2>"$TMP/err"
}
warnings() { grep -c 'environment re-applied' "$TMP/err" || true; }
log_lines() { if [ -f "$LOG" ]; then wc -l < "$LOG" | tr -d ' '; else printf 0; fi; }

# --- 1. the incident: flag set, PATH=/usr/bin:/bin, interactive login shell ----

rm -f "$LOG"
out=$(run_zsh __NIX_DARWIN_SET_ENVIRONMENT_DONE=1 PATH=/usr/bin:/bin \
  /bin/zsh -l -i -c 'print -r -- "$PATH"; command -v darwin-rebuild')
assert_contains ":$out:" ":/run/current-system/sw/bin:" "poisoned interactive shell: nix system path not restored"
assert_contains "$out" "/run/current-system/sw/bin/darwin-rebuild" "poisoned interactive shell: darwin-rebuild not resolvable"
[ "$(warnings)" = 1 ] || fail "poisoned interactive shell: expected exactly one stderr warning, got $(warnings)"
[ "$(log_lines)" = 1 ] || fail "poisoned interactive shell: expected exactly one log line, got $(log_lines)"
grep -q 'interactive=y' "$LOG" || fail "log line does not record interactive=y"
grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} pid=[0-9]+ ppid=[0-9]+ term=[^ ]+ interactive=y path=/usr/bin:/bin$' "$LOG" \
  || fail "log line is malformed or lacks the pre-repair PATH: $(cat "$LOG")"
if grep -q 'HOME/.local/bin' "$HOME/.zshrc" 2>/dev/null; then
  case "$out" in
    "$HOME/.local/bin:"*) : ;;
    *) fail "guard did not run before the ~/.zshrc PATH prepends" ;;
  esac
fi
pass "path-guard: poisoned interactive shell is repaired, warned once, logged once"

# --- 2. flag set, no PATH at all, non-interactive -------------------------------

out=$(run_zsh __NIX_DARWIN_SET_ENVIRONMENT_DONE=1 /bin/zsh -c 'print -r -- "$PATH"')
assert_contains ":$out:" ":/run/current-system/sw/bin:" "PATH-less non-interactive shell: nix system path not restored"
[ "$(warnings)" = 0 ] || fail "non-interactive shell printed a warning"
[ "$(log_lines)" = 2 ] || fail "non-interactive repair was not logged"
# With PATH absent from the environment, zsh substitutes its own compiled default
# before /etc/zshenv runs, so that default is what the guard finds and records.
last=$(sed -n '$p' "$LOG")
case "$last" in
  *"interactive=n path="*) : ;;
  *) fail "log line does not record interactive=n with a pre-repair PATH: $last" ;;
esac
assert_not_contains "$last" "/run/current-system/sw/bin" "recorded pre-repair PATH already contained the nix system path"
pass "path-guard: non-interactive shell is repaired silently and logged"

# --- 2b. the log records the first 512 characters of the pre-repair PATH and ---
# ---     discards the remainder; a marker in the first entry must survive    ---

marker="/tmp/probe-marker"
long="$marker"
i=0
while [ "$i" -lt 60 ]; do
  long="$long:/tmp/filler-directory-number-$i"
  i=$((i + 1))
done
[ "${#long}" -gt 600 ] || fail "fixture PATH is not long enough to exercise truncation"
run_zsh __NIX_DARWIN_SET_ENVIRONMENT_DONE=1 PATH="$long" /bin/zsh -c ':' >/dev/null
recorded=$(sed -n '$p' "$LOG" | sed 's/.* path=//')
[ "${#recorded}" -eq 512 ] || fail "recorded PATH is ${#recorded} characters, expected the first 512"
case "$recorded" in
  "$marker:"*) : ;;
  *) fail "recorded PATH does not begin with the marker; the wrong part of the string was kept" ;;
esac
[ "$recorded" = "$(printf '%s' "$long" | cut -c1-512)" ] || fail "recorded PATH is not the first 512 characters of the original"
pass "path-guard: log keeps the first 512 characters of the pre-repair PATH and discards the remainder"

# --- 3. stale home-manager session variables are refreshed too -----------------

HM_VARS="/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
if grep -q '^export EDITOR=' "$HM_VARS" 2>/dev/null; then
  out=$(run_zsh __NIX_DARWIN_SET_ENVIRONMENT_DONE=1 __HM_SESS_VARS_SOURCED=1 EDITOR=stale-editor PATH=/usr/bin:/bin \
    /bin/zsh -c 'print -r -- "$EDITOR"')
  [ "$out" != "stale-editor" ] || fail "stale EDITOR survived the repair (home-manager guard not cleared)"
  pass "path-guard: stale home-manager session variables are refreshed"
fi

# --- 4. controls: the guard must not fire on healthy shells ---------------------

rm -f "$LOG"
healthy=$(run_zsh /bin/zsh -l -i -c 'print -r -- "$PATH"')
assert_contains ":$healthy:" ":/run/current-system/sw/bin:" "clean control shell has no nix system path"
[ ! -e "$LOG" ] || fail "guard fired on a clean environment"
[ "$(warnings)" = 0 ] || fail "guard warned on a clean environment"

out=$(run_zsh __NIX_DARWIN_SET_ENVIRONMENT_DONE=1 __HM_SESS_VARS_SOURCED=1 PATH="$healthy" \
  /bin/zsh -c 'print -r -- "$PATH"')
[ "$out" = "$healthy" ] || fail "guard changed a healthy inherited PATH"
[ ! -e "$LOG" ] || fail "guard fired on a healthy inherited environment"
pass "path-guard: clean and healthy inherited environments are left alone"

# --- 5. the log is bounded: over 64 KiB keeps only the last 200 lines -----------

i=0
: > "$LOG"
while [ "$i" -lt 3000 ]; do
  printf 'old entry %04d padding padding padding padding padding\n' "$i" >> "$LOG"
  i=$((i + 1))
done
[ "$(wc -c < "$LOG")" -gt 65536 ] || fail "fixture log is not over the 64 KiB threshold"
run_zsh __NIX_DARWIN_SET_ENVIRONMENT_DONE=1 PATH=/usr/bin:/bin /bin/zsh -c ':' >/dev/null
n=$(log_lines)
[ "$n" -le 201 ] || fail "log was not truncated: $n lines remain"
[ "$n" -ge 100 ] || fail "log lost its most recent lines: only $n remain"
head -n 1 "$LOG" | grep -q '^old entry 2' || fail "log kept the head instead of the tail"
tail -n 1 "$LOG" | grep -q 'interactive=n' || fail "new entry was not appended after truncation"
pass "path-guard: log over 64 KiB is cut to its last 200 lines before appending"
