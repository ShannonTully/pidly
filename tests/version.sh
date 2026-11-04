#!/bin/sh
# Tests for the version, which exists so that a person can say what they are
# running and a package has something to name.
#
# It lives in the script and nowhere else. Nothing on disk records it: a
# tracker carries no version and must not, because that is state that can
# disagree with the files.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
# -- before the needle: this suite is the one that greps for text beginning
# with a dash, and grep would otherwise read --version as its own flag.
has() { if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else no "$1 (missing '$3' in: $2)"; fi; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pidly.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
PIDLY_PID=$$; export PIDLY_PID

echo "the flag"
out=$($PIDLY --version) && rc=0 || rc=$?
check "--version exits 0" "$rc" "0"
has "and names the tool" "$out" "pidly "
check "-V is the same thing" "$($PIDLY -V)" "$out"

# The point of the flag is to report what is installed. A literal in the
# printf would pass every test above and lie after the next bump.
declared=$(sed -n 's/^VERSION=//p' "$PIDLY")
check "what it prints is the VERSION the script carries" "$out" "pidly $declared"
check "and that is one line" "$(printf '%s\n' "$out" | grep -c .)" "1"
check "in the shape a package can name" \
	"$(printf '%s' "$declared" | grep -Ec '^[0-9]+\.[0-9]+\.[0-9]+$')" "1"

echo "it answers before anything else does"
# Asking what you are running must work when nothing else does: outside a
# tracker, which every other command refuses, and on a first install before
# init has ever run.
check "there is no tracker here" "$(if [ -e .pidly ]; then echo 1; else echo 0; fi)" "0"
out2=$($PIDLY --version) && rc=0 || rc=$?
check "--version still works outside a tracker" "$rc" "0"
check "with the same answer" "$out2" "$out"

echo "and it is a flag, not a command"
out=$($PIDLY --version extra 2>&1) && rc=0 || rc=$?
check "an argument is refused" "$rc" "1"
has "saying how to spell it" "$out" "usage: pidly --version"
has "the usage text lists it" "$($PIDLY 2>&1 || true)" "--version"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
