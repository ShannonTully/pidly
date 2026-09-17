#!/bin/sh
# Tests for `pidly new`: numbering, the header it writes, and placement.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
. "$(dirname "$0")/config.sh"
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
fields() { awk 'NR>3 { if ($0 == "") exit; print }' "$1"; }
body() { awk 'b { print } !b && $0 == "" { b = 1 }' "$1"; }
nums() { find .pidly -mindepth 1 -type d '!' -name c '!' -name '.*' -printf '%f\n' | sort -n | tr '\n' ' '; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"; mkdir .pidly
cat > .pidly/schema.md <<'EOF'
| field  | required | values  |
|--------|----------|---------|
| effort | yes      | S, M, L |
| area   | no       | free    |
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
$PIDLY new "titled" </dev/null >/dev/null
f=.pidly/5/info
check "line 1 is an empty claim" "$(sed -n 1p $f)" "claim:"
check "line 2 is an empty needs" "$(sed -n 2p $f)" "needs:"
check "line 3 is the title" "$(sed -n 3p $f)" "title: titled"
check "required schema fields are stubbed" "$(sed -n 4p $f)" "effort:"
check "optional ones are not" "$(grep -c '^area:' $f || true)" "0"
check "an empty body writes no blank line" "$(wc -l < $f)" "4"

printf 'line one\nline two\n' | $PIDLY new "with body" >/dev/null
f=.pidly/6/info
check "a blank line separates fields from the body" "$(sed -n 5p $f)" ""
check "the body follows it" "$(body $f | tr '\n' '/')" "line one/line two/"
check "fields come before the body" "$(fields $f)" "effort:"
check "the body ends at the end of the file" "$(tail -1 $f)" "line two"

echo "no derived data"
# The layout exists so that editing a body needs no bookkeeping. Nothing
# records where the body starts or ends, so there is nothing to fall out of
# sync with it.
before=$(cat $f)
printf 'appended by hand\n' >> $f
check "appending to a body needs no other change" \
	"$(body $f | tr '\n' '/')" "line one/line two/appended by hand/"
check "fields are unaffected" "$(fields $f)" "effort:"
printf '%s\n' "$before" > $f

printf 'one\n\ntwo\n' | $PIDLY new "blank inside the body" >/dev/null
check "a blank line inside a body does not end it" \
	"$(body .pidly/7/info | tr '\n' '/')" "one//two/"
printf 'x\nhandoff: not a field, this is body text\n' | \
	$PIDLY new "field-shaped body line" >/dev/null
check "a body line that looks like a field stays in the body" \
	"$(body .pidly/8/info | tail -1)" "handoff: not a field, this is body text"
check "and is not read as a field" "$(fields .pidly/8/info)" "effort:"

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

echo "concurrency ($PIDLY_TEST_RACE processes)"
before=$(find .pidly -name info | wc -l)
i=0; while [ $i -lt "$PIDLY_TEST_RACE" ]; do
	i=$((i+1))
	( $PIDLY new "parallel $i" </dev/null >/dev/null 2>&1 ) &
done
wait
after=$(find .pidly -name info | wc -l)
check "every parallel creation succeeds" "$((after - before))" "$PIDLY_TEST_RACE"
dupes=$(find .pidly -mindepth 1 -type d '!' -name c '!' -name '.*' -printf '%f\n' | sort | uniq -d | tr -d '\n')
check "and no number is issued twice" "$dupes" ""
check "no lock is left behind" "$(find .pidly -name '.lock*' | wc -l)" "0"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
