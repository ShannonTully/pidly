#!/bin/sh
# Tests for reap: it clears a claim whose process is positively gone, and
# nothing else. The states it refuses matter more than the one it clears.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
has() { if printf '%s' "$2" | grep -qF "$3"; then ok "$1"; else no "$1 (missing '$3' in: $2)"; fi; }
line1() { sed -n 1p "$(find .pidly -type d -name "$1")/info"; }
# A claim from a process that has since exited: the subshell holds it, then
# goes away, which is exactly the state reap exists for.
dead_claim() { sh -c "PIDLY_PID=\$\$ $PIDLY claim $1 >/dev/null"; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
PIDLY_PID=$$; export PIDLY_PID
$PIDLY init >/dev/null
$PIDLY new "one" </dev/null >/dev/null      # 1
$PIDLY new "two" </dev/null >/dev/null      # 2
$PIDLY new "three" </dev/null >/dev/null    # 3

echo "a named ticket"
dead_claim 1
check "check sees the dead claim" \
	"$($PIDLY check 2>&1 | grep -c 'which is gone' || true)" "1"
out=$($PIDLY reap 1)
has "reap clears it" "$out" "1: cleared the claim by"
has "and says it is gone" "$out" "which is gone"
check "line 1 is empty again" "$(line1 1)" "claim:"
check "and check is clean" "$($PIDLY check >/dev/null && echo clean)" "clean"

echo "what it will not touch"
$PIDLY claim 2 >/dev/null
held=$(line1 2)
out=$($PIDLY reap 2 2>&1) && rc=0 || rc=$?
check "a live claim is refused" "$rc" "1"
has "saying the holder is running" "$out" "which is running"
check "and it is still held" "$(line1 2)" "$held"
$PIDLY release 2 >/dev/null

out=$($PIDLY reap 2 2>&1) && rc=0 || rc=$?
check "an unclaimed ticket is refused" "$rc" "1"
has "saying so" "$out" "2 is not claimed"

dead_claim 2
sed -i "1s|@[^ ]*|@someother.u0|" .pidly/2/info
held=$(line1 2)
out=$($PIDLY reap 2 2>&1) && rc=0 || rc=$?
check "an unverifiable claim is refused" "$rc" "1"
has "and says a claim it cannot check is not a dead one" "$out" "not a dead one"
check "leaving it exactly as it was" "$(line1 2)" "$held"

PIDLY_AGENT=cloud-x PIDLY_LEASE=1s $PIDLY claim 3 >/dev/null
sleep 2
held=$(line1 3)
out=$($PIDLY reap 3 2>&1) && rc=0 || rc=$?
check "an expired lease is refused" "$rc" "1"
has "because claim already takes it" "$out" "already takeable"
check "so the line is left alone" "$(line1 3)" "$held"
sed -i '1s/.*/claim:/' .pidly/3/info
sed -i '1s/.*/claim:/' .pidly/2/info

echo "the sweep"
out=$($PIDLY reap)
has "says when there is nothing to do" "$out" "nothing to reap"
dead_claim 1
dead_claim 3
$PIDLY claim 2 >/dev/null
out=$($PIDLY reap)
has "clears one dead claim" "$out" "1: cleared the claim by"
has "and the other" "$out" "3: cleared the claim by"
has "counting what it did" "$out" "2 claim(s) cleared"
check "the live claim is untouched" \
	"$([ "$(line1 2)" = "claim:" ] && echo cleared || echo held)" "held"
$PIDLY release 2 >/dev/null

echo "closed work"
dead_claim 1
$PIDLY close 1 >/dev/null
has "a dead claim on a finished ticket is still swept" "$($PIDLY reap)" "1: cleared"
check "and check is clean afterwards" "$($PIDLY check >/dev/null && echo clean)" "clean"

echo "the tracker is otherwise untouched"
before=$(find .pidly -type f -exec cksum {} + | sort)
$PIDLY reap >/dev/null
check "a sweep with nothing to clear writes nothing" \
	"$(find .pidly -type f -exec cksum {} + | sort)" "$before"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
