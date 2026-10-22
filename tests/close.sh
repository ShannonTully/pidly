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

echo "closing a claimed ticket"
$PIDLY claim 4 >/dev/null
updated=$(sed -n 's/^updated: //p' "$($PIDLY show -p 4)/info")
$PIDLY close 4 >/dev/null
check "empties claim:" "$(sed -n 1p .pidly/c/4/info)" "claim:"
check "and leaves updated alone, as a move always has" \
	"$(sed -n 's/^updated: //p' .pidly/c/4/info)" "$updated"
check "and leaves nothing of its lock behind" "$(ls -A .pidly/c/4)" "info"
check "and check is content" "$($PIDLY check >/dev/null && echo clean)" "clean"
$PIDLY reopen 4 >/dev/null

echo "a claim left on a closed ticket"
$PIDLY claim 4 >/dev/null
held=$(sed -n '1s/^claim://p' .pidly/4/info)
mkdir -p .pidly/c && mv .pidly/4 .pidly/c/          # closed by hand
out=$($PIDLY check 2>&1) && rc=0 || rc=$?
check "is a warning, not a problem" "$rc" "0"
has "check names the ticket and the holder" "$out" \
	"note: 4: closed, but still claimed by $held"
# A dead holder on a closed ticket is still only the warning: nobody can
# be working on finished work, so "which is gone" adds nothing.
printf 'claim:999999.1@nobody.u0\n' > "$tmp/l1"
sed 1d .pidly/c/4/info >> "$tmp/l1" && mv "$tmp/l1" .pidly/c/4/info
out=$($PIDLY check 2>&1) && rc=0 || rc=$?
check "even when the holder is gone" "$rc" "0"
has "it is the same warning" "$out" "note: 4: closed, but still claimed by 999999.1@nobody.u0"
sed '1s/^claim:.*/claim:/' .pidly/c/4/info > "$tmp/l1" && mv "$tmp/l1" .pidly/c/4/info
$PIDLY reopen 4 >/dev/null

echo "reparent"
at() { dirname "$($PIDLY show -p "$1")"; }
$PIDLY new "root three" </dev/null >/dev/null            # 5
$PIDLY reparent 5 4 >/dev/null
check "a clean move lands under the new parent" "$(at 5)" "$(  $PIDLY show -p 4)"
check "and check is content" "$($PIDLY check >/dev/null && echo clean)" "clean"
$PIDLY reparent -r 5 >/dev/null
check "-r moves it back to the top" "$(at 5)" "$(cd .pidly && pwd)"
out=$($PIDLY reparent -r 5 2>&1) && rc=0 || rc=$?
check "moving it where it already is is refused" "$rc" "1"
out=$($PIDLY reparent 5 5 2>&1) && rc=0 || rc=$?
check "a ticket cannot be its own parent" "$rc" "1"

# needs survives a move: it holds numbers, and only the hierarchy is
# positional. This is why a reparent needs no bookkeeping.
$PIDLY set 5 needs "4" >/dev/null
$PIDLY reparent 5 1 >/dev/null
check "needs is untouched by a move" "$($PIDLY needs 5)" "4"
$PIDLY set 5 needs "" >/dev/null

# The guard this command exists for: a move must never change open/closed.
$PIDLY close 5 >/dev/null
$PIDLY reparent 5 4 >/dev/null
check "a closed ticket stays closed, in the new parent's c/" \
	"$(at 5)" "$($PIDLY show -p 4)/c"
check "and check is still content" "$($PIDLY check >/dev/null && echo clean)" "clean"
# Back to the top, so 4 has no open child and can be closed below.
$PIDLY reopen 5 >/dev/null
$PIDLY reparent -r 5 >/dev/null

$PIDLY close 4 >/dev/null
out=$($PIDLY reparent 5 4 2>&1) && rc=0 || rc=$?
check "a closed destination is refused" "$rc" "1"
has "and says what it would have done" "$out" "would close it too"
$PIDLY reopen 4 >/dev/null

$PIDLY reparent 1 5 >/dev/null
out=$($PIDLY reparent 5 1 2>&1) && rc=0 || rc=$?
check "a parent inside the ticket's own subtree is refused" "$rc" "1"
has "and says why" "$out" "into itself"
$PIDLY reparent -r 1 >/dev/null

# An open ticket stranded inside a closed ancestor is check's finding and
# reopen's repair; moving it would hide it.
$PIDLY close 4 >/dev/null
mkdir -p "$($PIDLY show -p 4)"
mv "$($PIDLY show -p 5)" "$($PIDLY show -p 4)/5"
out=$($PIDLY reparent 5 1 2>&1) && rc=0 || rc=$?
check "a ticket stranded in a closed ancestor is refused" "$rc" "1"
has "and points at reopen" "$out" "reopen 5"
$PIDLY reopen 5 >/dev/null
check "after reopen the tracker is clean again" \
	"$($PIDLY check >/dev/null && echo clean)" "clean"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
