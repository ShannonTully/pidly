#!/bin/sh
# Tests for list, field, tree and check.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
. "$(dirname "$0")/lib.sh"
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
has() { if printf '%s' "$2" | grep -qF "$3"; then ok "$1"; else no "$1 (missing '$3' in: $2)"; fi; }
hasnt() { if printf '%s' "$2" | grep -qF "$3"; then no "$1 (unexpected '$3')"; else ok "$1"; fi; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pidly.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
PIDLY_PID=$$; export PIDLY_PID
$PIDLY init >/dev/null
$PIDLY new "root one" </dev/null >/dev/null            # 1
$PIDLY new "root two" </dev/null >/dev/null            # 2
$PIDLY new -p 1 "child of one" </dev/null >/dev/null   # 3
$PIDLY new -n "2" "blocked on two" </dev/null >/dev/null  # 4

echo "list"
out=$($PIDLY list)
has "shows ready work" "$out" "root one"
hasnt "hides blocked work" "$out" "blocked on two"
$PIDLY claim 2 >/dev/null
out=$($PIDLY list)
hasnt "hides claimed work" "$out" "root two"
out=$($PIDLY list -a)
has "-a shows the claimed one" "$out" "claimed"
has "-a shows the blocked one with its blocker" "$out" "(needs 2)"
check "-a sorts numerically" "$(printf '%s' "$out" | awk '{print $1}' | tr '\n' ' ')" "1 2 3 4 "
$PIDLY release 2 >/dev/null

echo "field"
# Two tickets carry effort, in different places in their blocks, one carries
# area instead and one carries neither: a tracker whose tickets disagree
# about which fields they have, which is what a schema change leaves behind.
printf '\nfield: effort\nmatch: S|M|L\n\nfield: area\nmatch: cli|docs\n' \
	>> .pidly/schema
insert_after 3 .pidly/1/info 'effort: L'
insert_after 3 .pidly/2/info 'area: cli' 'effort: M'
insert_after 3 .pidly/1/3/info 'area: docs'
out=$($PIDLY field effort)
check "a row per open ticket" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "4"
check "sorted numerically" \
	"$(printf '%s\n' "$out" | awk '{print $1}' | tr '\n' ' ')" "1 2 3 4 "
has "reads the field" "$out" "1     L"
has "wherever it sits in the block" "$out" "2     M"
has "- where the ticket does not carry it" "$out" "3     -"
out=$($PIDLY field area)
has "a ticket that has this one instead" "$out" "3     docs"
has "and - for the one that does not" "$out" "1     -"
check "a field no ticket has is every ticket, all -" \
	"$(printf '%s\n' "$($PIDLY field nosuch)" | awk '{print $2}' | sort -u | tr '\n' ' ')" "- "
mkdir -p .pidly/c && mv .pidly/2 .pidly/c/
hasnt "closed work is left out" "$($PIDLY field effort)" "2     M"
has "-a takes it in" "$($PIDLY field -a effort)" "2     M"
mv .pidly/c/2 .pidly/; rmdir .pidly/c
$PIDLY field >/dev/null 2>&1 && rc=0 || rc=$?
check "a name is required" "$rc" "1"

echo "claims list can and cannot verify"
# list used to call anything with a non-empty line 1 claimed, while claim
# resolved it properly. The two disagreed about an expired lease, which is
# takeable: ready work no listing offered.
sedi '1s/.*/claim:cloud-1@- 2020-01-01T00:00:00Z/' .pidly/2/info
out=$($PIDLY list)
has "an expired lease is offered as ready" "$out" "root two"
out=$($PIDLY list -a)
has "and -a says whose lease ran out" "$out" "(cloud-1 left a lease that ran out)"
check "which is what claim says too" "$($PIDLY claim 2 >/dev/null && echo taken)" "taken"

out=$($PIDLY list -a)
has "a live claim still reads claimed" "$out" "2     claimed"
# A dead claim: same runtime, a pid that is not there. list leaves it as
# claimed, because judging a pid needs the process table and that is a
# process per ticket — and claim agrees, refusing it until reap.
sedi '1s/^claim:[0-9]*\./claim:999999./' .pidly/2/info
has "so does a dead one" "$($PIDLY list -a)" "2     claimed"
out=$($PIDLY claim 2 2>&1) && rc=0 || rc=$?
check "which claim refuses as well" "$rc" "1"
has "pointing at reap" "$out" "reap"
$PIDLY reap 2 >/dev/null
has "and after reap both call it ready" "$($PIDLY list)" "root two"

echo "deferred"
# 34, 35, 36 and 37 in this tracker: open, unclaimed, unblocked, and nobody
# should start any of them. Before defer: they were a quarter of what list
# offered, and the only way to tell was to open each one.
$PIDLY set 1 defer "someone actually wanting it" >/dev/null
out=$($PIDLY list)
hasnt "list stops offering a deferred ticket" "$out" "root one"
out=$($PIDLY list -a)
has "-a shows the state" "$out" "deferred"
has "with the trigger that would end it" "$out" "(until someone actually wanting it)"
out=$($PIDLY claim 1)
has "claim takes it anyway: deferring is an opinion, not a blocker" "$out" "1 claimed"
has "and prints the trigger" "$out" "deferred until: someone actually wanting it"
$PIDLY release 1 >/dev/null
$PIDLY set 1 defer >/dev/null
has "clearing the field makes it ready again" "$($PIDLY list)" "root one"
check "nothing offers to write defer into every ticket" \
	"$($PIDLY check 2>&1 | grep -c "no 'defer' line" || true)" "0"
out=$($PIDLY fields)
hasnt "and the migration leaves it alone" "$out" "defer"

echo "tree"
out=$($PIDLY tree)
has "shows a root" "$out" "[ ] 1"
has "indents a child under it" "$out" "  [ ] 3"
mkdir -p .pidly/1/c && mv .pidly/1/3 .pidly/1/c/
out=$($PIDLY tree)
has "marks a closed ticket" "$out" "[x] 3"
check "parents still precede children" \
	"$(printf '%s' "$out" | grep -n '] [13] ' | cut -d: -f1 | tr '\n' ' ')" "1 2 "
mv .pidly/1/c/3 .pidly/1/

echo "check passes a clean tracker"
out=$($PIDLY check) && rc=0 || rc=$?
check "exit 0" "$rc" "0"
has "and says so" "$out" "ok:"

echo "check catches"
sedi '3s/.*/not a title/' .pidly/2/info
out=$($PIDLY check 2>&1) && rc=0 || rc=$?
check "exit 1 when something is wrong" "$rc" "1"
has "a missing title" "$out" "2: line 3 is not title:"
$PIDLY init >/dev/null 2>&1 || true
sedi '3s/.*/title: root two/' .pidly/2/info

sedi '2s/.*/needs: 99/' .pidly/4/info
has "a dangling dependency" "$($PIDLY check 2>&1 || true)" "4: needs 99, which does not exist"
sedi '2s/.*/needs: 2/' .pidly/4/info

sedi '2s/.*/needs: 2/' .pidly/1/info
sedi '2s/.*/needs: 1/' .pidly/2/info
out=$($PIDLY check 2>&1 || true)
has "a cycle, naming one member" "$out" "1: in a needs cycle"
has "and the other" "$out" "2: in a needs cycle"
hasnt "without implicating an unrelated ticket" "$out" "3: in a needs cycle"
sedi '2s/.*/needs:/' .pidly/1/info
sedi '2s/.*/needs:/' .pidly/2/info

insert_after 3 .pidly/2/info 'strayfield: x'
has "an undeclared field" "$($PIDLY check 2>&1 || true)" "field 'strayfield' is not in the schema"
sedi '/^strayfield:/d' .pidly/2/info

mkdir .pidly/2/notes
out=$($PIDLY check 2>&1 || true)
has "a directory that is not a number or c" "$out" "2: 'notes/' is neither a number nor c"
hasnt "and does not also report it as a broken ticket" "$out" "no info file"
rmdir .pidly/2/notes

rm .pidly/.n/2
has "a number with no registry entry" "$($PIDLY check 2>&1 || true)" "2: no registry entry"
$PIDLY init >/dev/null

echo 999999 > .pidly/1/.lock
has "a lock whose holder is gone" "$($PIDLY check 2>&1 || true)" "1: a lock held by 999999"
rm -f .pidly/1/.lock

printf 'clobbered\n' > .pidly/README.md
has "a stale reference" "$($PIDLY check 2>&1 || true)" "README.md is out of date"
$PIDLY agents >/dev/null
sedi 's/^A ticket is a directory.*/TAMPERED/' AGENTS.md
has "a stale AGENTS.md section" "$($PIDLY check 2>&1 || true)" "pidly section is out of date"
$PIDLY agents >/dev/null

echo "check changes nothing"
$PIDLY agents >/dev/null
before=$(find .pidly -type f -exec cksum {} + | sort)
$PIDLY check >/dev/null 2>&1 || true
check "the tracker is byte-identical afterwards" \
	"$(find .pidly -type f -exec cksum {} + | sort)" "$before"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
