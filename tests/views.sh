#!/bin/sh
# Tests for list, tree and check.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
has() { if printf '%s' "$2" | grep -qF "$3"; then ok "$1"; else no "$1 (missing '$3' in: $2)"; fi; }
hasnt() { if printf '%s' "$2" | grep -qF "$3"; then no "$1 (unexpected '$3')"; else ok "$1"; fi; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
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
sed -i '3s/.*/not a title/' .pidly/2/info
out=$($PIDLY check 2>&1) && rc=0 || rc=$?
check "exit 1 when something is wrong" "$rc" "1"
has "a missing title" "$out" "2: line 3 is not a title"
$PIDLY init >/dev/null 2>&1 || true
sed -i '3s/.*/title: root two/' .pidly/2/info

sed -i '2s/.*/needs: 99/' .pidly/4/info
has "a dangling dependency" "$($PIDLY check 2>&1 || true)" "4: needs 99, which does not exist"
sed -i '2s/.*/needs: 2/' .pidly/4/info

sed -i '2s/.*/needs: 2/' .pidly/1/info
sed -i '2s/.*/needs: 1/' .pidly/2/info
out=$($PIDLY check 2>&1 || true)
has "a cycle, naming one member" "$out" "1: in a needs cycle"
has "and the other" "$out" "2: in a needs cycle"
hasnt "without implicating an unrelated ticket" "$out" "3: in a needs cycle"
sed -i '2s/.*/needs:/' .pidly/1/info
sed -i '2s/.*/needs:/' .pidly/2/info

printf 'strayfield: x\n' > .pidly/2/info.tmp
sed -i '3a strayfield: x' .pidly/2/info; rm -f .pidly/2/info.tmp
has "an undeclared field" "$($PIDLY check 2>&1 || true)" "field 'strayfield' is not in schema.md"
sed -i '/^strayfield:/d' .pidly/2/info

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
sed -i 's/^A ticket is a directory.*/TAMPERED/' AGENTS.md
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
