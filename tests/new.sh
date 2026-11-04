#!/bin/sh
# Tests for `pidly new`: numbering, the header it writes, and placement.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/config.sh"
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
fields() { awk 'NR>3 { if ($0 == "") exit; print }' "$1"; }
# created carries a timestamp, so assertions about the field block compare
# against its name rather than its value.
fieldnames() { fields "$1" | sed 's/:.*/:/'; }
iso='^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$'
body() { awk 'b { print } !b && $0 == "" { b = 1 }' "$1"; }
nums() { find .pidly -mindepth 1 -type d '!' -name c '!' -name '.*' -print | awk -F/ '{print $NF}' | sort -n | tr '\n' ' '; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pidly.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"; mkdir .pidly
cat > .pidly/schema <<'EOF'
field: effort
match: S|M|L

field: area
EOF

echo "numbering"
# Regression: lock() used _n as its spin counter and cmd_new used _n as the
# ticket number. Shell functions share one namespace, so taking the lock
# clobbered the allocation and the first ticket came out as 2.
n=$($PIDLY new "first" </dev/null | cut -f1)
check "the first ticket in a fresh tracker is 1" "$n" "1"
$PIDLY new "second" </dev/null >/dev/null
$PIDLY new "third" </dev/null >/dev/null
check "serial creation is contiguous" "$(nums)" "1 2 3 "

mkdir -p .pidly/c && mv .pidly/2 .pidly/c/
n=$($PIDLY new "after a close" </dev/null | cut -f1)
check "closed tickets still count toward the next number" "$n" "4"

echo "the header"
# A title-only ticket from empty stdin is the normal idiom, and stays one:
# edit refuses empty stdin, new does not (ticket 74).
$PIDLY new "titled" </dev/null >/dev/null && rc=0 || rc=$?
check "empty stdin makes a ticket with no body" "$rc" "0"
f=.pidly/5/info
check "line 1 is an empty claim" "$(sed -n 1p $f)" "claim:"
check "line 2 is an empty needs" "$(sed -n 2p $f)" "needs:"
check "line 3 is the title" "$(sed -n 3p $f)" "title: titled"
check "the ticket is dated" "$(sed -n '4s/^created: //p' $f | grep -Ec "$iso")" "1"
check "and stamped as just updated" "$(sed -n '5s/^updated: //p' $f | grep -Ec "$iso")" "1"
check "every declared field gets a slot" "$(sed -n 6p $f)" "effort:"
check "optional ones too, empty" "$(sed -n 7p $f)" "area:"
check "an empty body writes no blank line" "$(wc -l < $f | tr -d " ")" "7"

printf 'line one\nline two\n' | $PIDLY new "with body" >/dev/null
f=.pidly/6/info
check "a blank line separates fields from the body" "$(sed -n 8p $f)" ""
check "the body follows it" "$(body $f | tr '\n' '/')" "line one/line two/"
check "fields come before the body" "$(fieldnames $f | tr '\n' ' ')" "created: updated: effort: area: "
check "the body ends at the end of the file" "$(tail -1 $f)" "line two"

echo "no derived data"
# The layout exists so that editing a body needs no bookkeeping. Nothing
# records where the body starts or ends, so there is nothing to fall out of
# sync with it.
before=$(cat $f)
printf 'appended by hand\n' >> $f
check "appending to a body needs no other change" \
	"$(body $f | tr '\n' '/')" "line one/line two/appended by hand/"
check "fields are unaffected" "$(fieldnames $f | tr '\n' ' ')" "created: updated: effort: area: "
printf '%s\n' "$before" > $f

printf 'one\n\ntwo\n' | $PIDLY new "blank inside the body" >/dev/null
check "a blank line inside a body does not end it" \
	"$(body .pidly/7/info | tr '\n' '/')" "one//two/"
printf 'x\nhandoff: not a field, this is body text\n' | \
	$PIDLY new "field-shaped body line" >/dev/null
check "a body line that looks like a field stays in the body" \
	"$(body .pidly/8/info | tail -1)" "handoff: not a field, this is body text"
check "and is not read as a field" "$(fieldnames .pidly/8/info | tr '\n' ' ')" "created: updated: effort: area: "

echo "placement and needs"
$PIDLY new -p 1 "a child" </dev/null >/dev/null
check "-p puts the ticket under its parent" "$([ -f .pidly/1/9/info ] && echo yes)" "yes"
$PIDLY new -n "1 3" "blocked" </dev/null >/dev/null
check "-n records the dependencies" "$(sed -n 2p .pidly/10/info)" "needs: 1 3"

out=$($PIDLY new -p 2 "child of closed" </dev/null 2>&1) && rc=0 || rc=$?
check "a closed parent is refused" "$rc" "1"
case $out in *"reopen it"*) ok "and the refusal says what to do" ;; *) no "message: $out" ;; esac
out=$($PIDLY new -n "999" "bad dep" </dev/null 2>&1) && rc=0 || rc=$?
check "a nonexistent dependency is refused" "$rc" "1"
out=$($PIDLY new -n "abc" "bad dep" </dev/null 2>&1) && rc=0 || rc=$?
check "a non-numeric dependency is refused" "$rc" "1"
out=$($PIDLY new </dev/null 2>&1) && rc=0 || rc=$?
check "a missing title is refused" "$rc" "1"
out=$($PIDLY new "two
lines" </dev/null 2>&1) && rc=0 || rc=$?
check "a multi-line title is refused" "$rc" "1"

echo "fields"
# A tracker of its own: required means a value here, and every other test in
# this file would have to supply one.
mkdir req; cd req; mkdir .pidly
cat > .pidly/schema <<'EOF'
field: effort
required: yes
match: S|M|L

field: area
EOF

out=$($PIDLY new "unvalued" </dev/null 2>&1) && rc=0 || rc=$?
check "a required field with no value is refused" "$rc" "1"
case $out in *effort*) ok "and the refusal names it" ;; *) no "message: $out" ;; esac
check "and no ticket is left behind" "$(find .pidly -name info | wc -l | tr -d " ")" "0"
out=$($PIDLY new -f effort= "empty value" </dev/null 2>&1) && rc=0 || rc=$?
check "an empty value is no value" "$rc" "1"

$PIDLY new -f area="two words" -f effort=M "valued" </dev/null >/dev/null
f=.pidly/1/info
check "-f supplies the required field" "$(sed -n 's/^effort: //p' $f)" "M"
check "a value may contain spaces" "$(sed -n 's/^area: //p' $f)" "two words"
check "fields follow the schema, not the order of the flags" \
	"$(fieldnames $f | tr '\n' ' ')" "created: updated: effort: area: "
out=$($PIDLY check 2>&1 || true)
case $out in *"required field"*) no "check still complains: $out" ;;
             *) ok "and check is satisfied by the value" ;; esac

sedi 's/^effort: M$/effort:/' $f
case $($PIDLY check 2>&1 || true) in
*"1: required field 'effort' is empty"*) ok "a required field emptied by hand is reported" ;;
*) no "check did not report the empty field" ;; esac
sedi '/^effort:$/d' $f
case $($PIDLY check 2>&1 || true) in
*"1: required field 'effort' is missing"*) ok "and so is one that is gone" ;;
*) no "check did not report the missing field" ;; esac

$PIDLY new -f effort=S -f effort=L "corrected" </dev/null >/dev/null
check "a repeated -f is a correction: the last wins" \
	"$(sed -n 's/^effort: //p' .pidly/2/info)" "L"

out=$($PIDLY new -f nosuch=1 -f effort=M "unknown field" </dev/null 2>&1) && rc=0 || rc=$?
check "a field the schema does not declare is refused" "$rc" "1"
case $out in *"the schema"*) ok "and says where the names come from" ;; *) no "message: $out" ;; esac
out=$($PIDLY new -f effort "no equals" </dev/null 2>&1) && rc=0 || rc=$?
check "a -f without name=value is refused" "$rc" "1"
out=$($PIDLY new -f created=2020-01-01T00:00:00Z -f effort=M "stamp" </dev/null 2>&1) && rc=0 || rc=$?
check "pidly's own stamps are not -f's to set" "$rc" "1"
out=$($PIDLY new -f effort="two
lines" "multiline value" </dev/null 2>&1) && rc=0 || rc=$?
check "a multi-line value is refused" "$rc" "1"
check "none of the refusals created anything" "$(find .pidly -name info | wc -l | tr -d " ")" "2"
cd "$tmp"

echo "a number issued after the scan"
# new scans for the highest number before it takes the lock, and mkdir only
# sees siblings. So a number another new issued under a different parent in
# between was taken again: two tickets numbered 2 (ticket 75). Hold the lock
# with a live pid, let new scan and queue on it, then do what a `new -p 1`
# does while holding the lock, and let go.
mkdir scan; cd scan; mkdir .pidly
$PIDLY new "parent" </dev/null >/dev/null
echo $$ > .pidly/.lock
( $PIDLY new "top level" </dev/null > out 2>&1; echo $? > rc ) &
i=0
while [ -z "$(find .pidly -maxdepth 1 -name '.lock.*' -print)" ] && [ $i -lt 600 ]; do
	sleep 0.05 2>/dev/null || sleep 1; i=$((i+1))
done
mkdir .pidly/1/2
printf 'nonce\tchild\n' > .pidly/.n/2
rm -f .pidly/.lock
wait
check "a new that waited on the lock succeeds" "$(cat rc)" "0"
check "and skips the number issued while it waited" "$(cut -f1 out)" "3"
check "no number is issued twice" "$(nums)" "1 2 3 "
cd "$tmp"

echo "concurrency under two parents ($PIDLY_TEST_RACE processes)"
mkdir parents; cd parents; mkdir .pidly
$PIDLY new "parent" </dev/null >/dev/null
i=0; while [ $i -lt "$PIDLY_TEST_RACE" ]; do
	i=$((i+1))
	if [ $((i % 2)) -eq 0 ]; then
		( $PIDLY new -p 1 "child $i" </dev/null >/dev/null 2>&1 ) &
	else
		( $PIDLY new "top $i" </dev/null >/dev/null 2>&1 ) &
	fi
done
wait
check "every creation succeeds" "$(find .pidly -name info | wc -l | tr -d ' ')" "$((PIDLY_TEST_RACE + 1))"
dupes=$(nums | tr ' ' '\n' | sed '/^$/d' | uniq -d | tr -d '\n')
check "and no number is issued twice across parents" "$dupes" ""
cd "$tmp"

echo "concurrency ($PIDLY_TEST_RACE processes)"
before=$(find .pidly -name info | wc -l)
i=0; while [ $i -lt "$PIDLY_TEST_RACE" ]; do
	i=$((i+1))
	( $PIDLY new "parallel $i" </dev/null >/dev/null 2>&1 ) &
done
wait
after=$(find .pidly -name info | wc -l)
check "every parallel creation succeeds" "$((after - before))" "$PIDLY_TEST_RACE"
dupes=$(find .pidly -mindepth 1 -type d '!' -name c '!' -name '.*' -print | awk -F/ '{print $NF}' | sort | uniq -d | tr -d '\n')
check "and no number is issued twice" "$dupes" ""
check "no lock is left behind" "$(find .pidly -name '.lock*' | wc -l | tr -d " ")" "0"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
