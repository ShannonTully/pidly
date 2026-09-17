#!/bin/sh
# The tracker must behave the same in a checkout whose own path contains a
# directory named c — ~/c/pidly, /srv/c/proj. Closed-ness is a fact about the
# path inside .pidly; matching it against the absolute path made every ticket
# in such a checkout look finished, which is the direction that loses work.
set -eu
PIDLY=${PIDLY_BIN:-$(cd "$(dirname "$0")/.." && pwd)/bin/pidly}
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
has() { if printf '%s' "$2" | grep -qF "$3"; then ok "$1"; else no "$1 (missing '$3' in: $2)"; fi; }
hasnt() { if printf '%s' "$2" | grep -qF "$3"; then no "$1 (unexpected '$3')"; else ok "$1"; fi; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pidly.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/c/proj"; cd "$tmp/c/proj"
PIDLY_PID=$$; export PIDLY_PID
$PIDLY init >/dev/null
$PIDLY new "first" </dev/null >/dev/null            # 1
$PIDLY new -n "1" "waits for first" </dev/null >/dev/null   # 2

echo "with an open dependency"
out=$($PIDLY list -a)
has "list -a calls the blocked ticket blocked" "$out" "2     blocked"
has "and names its blocker" "$out" "(needs 1)"
hasnt "list does not offer it as ready" "$($PIDLY list)" "waits for first"
out=$($PIDLY claim 2 2>&1) && rc=0 || rc=$?
check "claim refuses it" "$rc" "1"
has "saying what blocks it" "$out" "2 is blocked by open tickets: 1"

echo "once the dependency closes"
$PIDLY close 1 >/dev/null
has "list offers the ticket" "$($PIDLY list)" "waits for first"
$PIDLY claim 2 >/dev/null
check "and claim takes it" "$($PIDLY status 2 | cut -f2)" "live"
$PIDLY release 2 >/dev/null

echo "the closed ticket"
has "is marked closed in tree" "$($PIDLY tree)" "[x] 1"
out=$($PIDLY new -p 1 "child of a closed parent" </dev/null 2>&1) && rc=0 || rc=$?
check "refuses new children" "$rc" "1"
has "and says why" "$out" "1 is closed"
$PIDLY reopen 1 >/dev/null
check "reopens to the top level" "$(find .pidly -type d -name 1)" ".pidly/1"
has "and tree shows it open again" "$($PIDLY tree)" "[ ] 1"

echo "check"
out=$($PIDLY check) && rc=0 || rc=$?
check "passes" "$rc" "0"
has "over every ticket" "$out" "ok: 2 tickets"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
