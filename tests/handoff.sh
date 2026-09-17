#!/bin/sh
# Tests for the handoff field: what the last agent left behind.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
# A real agent exports PIDLY_PID once and keeps running, so claim and
# release from separate invocations still agree on who the holder is.
PIDLY_PID=$$; export PIDLY_PID

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"; mkdir .pidly
cat > .pidly/schema.md <<'EOF'
| field   | required | values |
|---------|----------|--------|
| effort  | yes      | S,M,L  |
| handoff | no       | one line |
EOF
printf 'Body line.\n' | $PIDLY new "A ticket" >/dev/null

echo "writing"
$PIDLY claim 1 >/dev/null
$PIDLY release -m "Parser works; lexer fails on nested quotes." 1 >/dev/null
check "release -m records a handoff" \
	"$(sed -n 's/^handoff: //p' .pidly/1/info)" \
	"Parser works; lexer fails on nested quotes."
check "the claim is still cleared" "$(sed -n 1p .pidly/1/info)" "claim:"

$PIDLY claim 1 >/dev/null
$PIDLY release -m "Second note." 1 >/dev/null
check "a later handoff replaces the earlier one" "$(grep -c '^handoff:' .pidly/1/info)" "1"
check "with the new text" "$(sed -n 's/^handoff: //p' .pidly/1/info)" "Second note."

echo "structure"
d=$(sed -n '4s/^desc://p' .pidly/1/info)
check "desc still points at the body's last line" "$d" "5"
check "the body is untouched" "$(sed -n "5,${d}p" .pidly/1/info)" "Body line."
check "handoff sits after the body, with the fields" \
	"$(tail -n +$((d+1)) .pidly/1/info | grep -c '^handoff:')" "1"
check "it does not become a header line" "$(sed -n 1,4p .pidly/1/info | grep -c handoff)" "0"

echo "surfacing"
out=$($PIDLY claim 1)
case $out in
*"handoff: Second note."*) ok "claiming prints the handoff waiting on the ticket" ;;
*) no "claim output was: $out" ;;
esac
out=$($PIDLY status 1)
case $out in
*"handoff: Second note."*) ok "status shows it too" ;;
*) no "status output was: $out" ;;
esac
$PIDLY release 1 >/dev/null
check "releasing without -m leaves the old note alone" \
	"$(sed -n 's/^handoff: //p' .pidly/1/info)" "Second note."

echo "limits"
out=$($PIDLY release -m "one
two" 1 2>&1) && rc=0 || rc=$?
check "a multi-line note is refused" "$rc" "1"
case $out in *"in the body"*) ok "and says where longer text belongs" ;; *) no "message: $out" ;; esac

printf 'Fresh.\n' | $PIDLY new "no handoff" >/dev/null
out=$($PIDLY claim 2)
case $out in
*handoff*) no "a ticket with no handoff should not mention one: $out" ;;
*) ok "a ticket without a handoff prints nothing extra" ;;
esac

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
