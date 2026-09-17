#!/bin/sh
# Tests for close and reopen: the moves that carry state, and the rules that
# keep a finished tree from holding live work.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
has() { if printf '%s' "$2" | grep -qF "$3"; then ok "$1"; else no "$1 (missing '$3' in: $2)"; fi; }
where() { find .pidly -type d -name "$1" | sed "s|^\.pidly/||"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pidly.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
PIDLY_PID=$$; export PIDLY_PID
$PIDLY init >/dev/null
$PIDLY new "root one" </dev/null >/dev/null              # 1
$PIDLY new -p 1 "child of one" </dev/null >/dev/null     # 2
$PIDLY new -p 2 "grandchild" </dev/null >/dev/null       # 3
$PIDLY new "root two" </dev/null >/dev/null              # 4

echo "closing a leaf"
before=$(cat .pidly/1/2/3/info)
out=$($PIDLY close 3)
has "says so" "$out" "3 closed"
check "the ticket moved into its parent's c/" "$(where 3)" "1/2/c/3"
check "and nothing was written to it" "$(cat .pidly/1/2/c/3/info)" "$before"

echo "closing a parent"
out=$($PIDLY close 1 2>&1) && rc=0 || rc=$?
check "is refused while a child is open" "$rc" "1"
has "naming the child" "$out" "1 has open children: 2"
check "and the ticket did not move" "$(where 1)" "1"
$PIDLY close 2 >/dev/null
check "a parent whose children are all closed may close" \
	"$($PIDLY close 1 >/dev/null && where 1)" "c/1"
check "its finished children travel with it" "$(where 3)" "c/1/c/2/c/3"

echo "closing what is already closed"
out=$($PIDLY close 1 2>&1) && rc=0 || rc=$?
check "is refused" "$rc" "1"
has "and says why" "$out" "already closed"

echo "reopening"
out=$($PIDLY reopen 3)
check "the ticket is out of its c/" "$(where 3)" "1/2/3"
check "and so are the ancestors that held it" "$(where 1)/$(where 2)" "1/1/2"
has "each level is reported" "$out" "1 reopened"
has "including the ticket itself" "$out" "3 reopened"
check "an emptied c/ is not left behind" "$([ -d .pidly/c ] && echo yes || echo no)" "no"

echo "reopening does not cascade downward"
$PIDLY close 3 >/dev/null
$PIDLY close 2 >/dev/null
$PIDLY reopen 2 >/dev/null
check "the reopened ticket is open" "$(where 2)" "1/2"
check "its finished child stays finished" "$(where 3)" "1/2/c/3"

echo "reopening what is already open"
out=$($PIDLY reopen 2 2>&1) && rc=0 || rc=$?
check "is refused" "$rc" "1"
has "and says why" "$out" "already open"

echo "a closed root"
$PIDLY close 4 >/dev/null
check "goes into .pidly/c" "$(where 4)" "c/4"
$PIDLY reopen 4 >/dev/null
check "and comes back to the top level" "$(where 4)" "4"

echo "the commands are hand-doable"
$PIDLY close 4 >/dev/null
byhand=$(find .pidly -type d | sort)
$PIDLY reopen 4 >/dev/null
mkdir -p .pidly/c && mv .pidly/4 .pidly/c/
check "close leaves what mkdir and mv leave" "$(find .pidly -type d | sort)" "$byhand"
$PIDLY reopen 4 >/dev/null

echo "check"
out=$($PIDLY check) && rc=0 || rc=$?
check "passes over closed work" "$rc" "0"
mkdir -p .pidly/c && mv .pidly/1 .pidly/c/        # by hand, with 2 still open
out=$($PIDLY check 2>&1) && rc=0 || rc=$?
check "catches live work in a finished tree" "$rc" "1"
has "naming the parent and the child" "$out" "1: closed, but child 2 is open"
$PIDLY reopen 2 >/dev/null
check "and reopen is the fix" "$($PIDLY check >/dev/null && echo clean)" "clean"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
