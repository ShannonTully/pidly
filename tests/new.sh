#!/bin/sh
# Tests for `pidly new`: numbering, the header it writes, and placement.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
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
check "an empty body gives desc:4" "$(sed -n 4p $f)" "desc:4"
check "required schema fields are stubbed" "$(sed -n 5p $f)" "effort:"
check "optional ones are not" "$(grep -c '^area:' $f || true)" "0"

printf 'line one\nline two\n' | $PIDLY new "with body" >/dev/null
f=.pidly/6/info
check "desc points at the body's last line" "$(sed -n 4p $f)" "desc:6"
check "the body starts at line 5" "$(sed -n 5p $f)" "line one"
d=$(sed -n '4s/^desc://p' $f)
check "reading 5..desc gives exactly the body" "$(sed -n "5,${d}p" $f | tr '\n' '/')" "line one/line two/"
check "fields follow the body" "$(tail -n +$((d+1)) $f)" "effort:"

echo "placement and needs"
$PIDLY new -p 1 "a child" </dev/null >/dev/null
check "-p puts the ticket under its parent" "$([ -f .pidly/1/7/info ] && echo yes)" "yes"
$PIDLY new -n "1 3" "blocked" </dev/null >/dev/null
check "-n records the dependencies" "$(sed -n 2p .pidly/8/info)" "needs: 1 3"

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

echo "concurrency"
before=$(find .pidly -name info | wc -l)
i=0; while [ $i -lt 6 ]; do
	i=$((i+1))
	( $PIDLY new "parallel $i" </dev/null >/dev/null 2>&1 ) &
done
wait
after=$(find .pidly -name info | wc -l)
check "six parallel creations all succeed" "$((after - before))" "6"
dupes=$(find .pidly -mindepth 1 -type d '!' -name c '!' -name '.*' -printf '%f\n' | sort | uniq -d | tr -d '\n')
check "and no number is issued twice" "$dupes" ""
check "no lock is left behind" "$(find .pidly -name '.lock*' | wc -l)" "0"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
