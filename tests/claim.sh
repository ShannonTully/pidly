#!/bin/sh
# Regression tests for pidly claim/release and the lock.
# Builds a throwaway .pidly in a temp directory; touches nothing else.

set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/config.sh"
pass=0; fail=0

ok()   { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no()   { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pidly.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
mkdir -p .pidly/c/1 .pidly/2 .pidly/3
for n in 1 2 3; do
	d=$(find .pidly -type d -name $n)
	printf 'claim:\nneeds:\ntitle: ticket %s\n\nbody\n' "$n" > "$d/info"
done
printf 'claim:\nneeds: 2\ntitle: ticket 3\n\nbody\n' > .pidly/3/info

echo "claim"
out=$(sh -c "PIDLY_PID=\$\$ $PIDLY claim 2" 2>&1) && rc=0 || rc=$?
check "a free ticket can be claimed" "$rc" "0"
case $(sed -n 1p .pidly/2/info) in claim:[0-9]*@?*) ok "line 1 is claim:<pid>@<id>" ;; *) no "line 1 malformed: $(sed -n 1p .pidly/2/info)" ;; esac

sedi '1s/.*/claim:/' .pidly/2/info
echo "blocking"
out=$($PIDLY claim 3 2>&1) && rc=0 || rc=$?
check "a blocked ticket is refused" "$rc" "1"
case $out in *"blocked by open tickets: 2"*) ok "the blocker is named" ;; *) no "message was: $out" ;; esac

sedi '2s/.*/needs: 999/' .pidly/3/info
out=$($PIDLY claim 3 2>&1) && rc=0 || rc=$?
check "a dangling need is refused" "$rc" "1"
sedi '2s/.*/needs: 1/' .pidly/3/info
out=$(sh -c "PIDLY_PID=\$\$ $PIDLY claim 3" 2>&1) && rc=0 || rc=$?
check "a need satisfied by a closed ticket allows the claim" "$rc" "0"
sedi '1s/.*/claim:/' .pidly/3/info

echo "the lock"
echo 999999 > .pidly/2/.lock
out=$(sh -c "PIDLY_PID=\$\$ $PIDLY claim 2" 2>&1) && rc=0 || rc=$?
check "a lock held by a dead pid is broken" "$rc" "0"
check "and cleaned up afterwards" "$([ -e .pidly/2/.lock ] && echo present || echo gone)" "gone"

sedi '1s/.*/claim:/' .pidly/2/info
echo $$ > .pidly/2/.lock
out=$($PIDLY claim 2 2>&1) && rc=0 || rc=$?
check "a lock held by a live pid is respected" "$rc" "1"

printf '' > .pidly/2/.lock
out=$($PIDLY claim 2 2>&1) && rc=0 || rc=$?
check "an empty lock is never broken (holder is mid-write)" "$rc" "1"
rm -f .pidly/2/.lock
rm -f .pidly/2/.lock

echo "concurrency ($PIDLY_TEST_RACE processes)"
sedi '1s/.*/claim:/' .pidly/2/info
i=0; while [ $i -lt "$PIDLY_TEST_RACE" ]; do
	i=$((i+1))
	( sh -c "PIDLY_PID=\$\$ exec $PIDLY claim 2" >/dev/null 2>&1; echo $? > "rc.$i" ) &
done
wait
won=$(cat rc.* | grep -c '^0$' || true)
check "exactly one racing claim wins" "$won" "1"
check "no lock is left behind" "$([ -e .pidly/2/.lock ] && echo present || echo gone)" "gone"
rm -f rc.*

echo "release"
out=$($PIDLY release 2 2>&1) && rc=0 || rc=$?
check "a claim from a dead agent is not released" "$rc" "1"
sedi "1s|@.*|@elsewhere|" .pidly/2/info
out=$($PIDLY release 2 2>&1) && rc=0 || rc=$?
check "a foreign claim is not released" "$rc" "1"
sedi '1s/.*/claim:/' .pidly/2/info
out=$($PIDLY release 2 2>&1) && rc=0 || rc=$?
check "an unclaimed ticket cannot be released" "$rc" "1"
sh -c "export PIDLY_PID=\$\$; $PIDLY claim 2 >/dev/null && $PIDLY release 2 >/dev/null" && rc=0 || rc=$?
check "an agent can release its own live claim" "$rc" "0"
check "line 1 is blank again" "$(sed -n 1p .pidly/2/info)" "claim:"

echo "renewing"
# Claiming what you already hold renews it. A lease's runtime is `-`, which
# never matches this machine's, so a live lease read as unverifiable and its
# own agent was refused when it claimed again to extend it (ticket 77).
mkdir .pidly/4
printf 'claim:\nneeds:\ntitle: ticket 4\n\nbody\n' > .pidly/4/info
line() { sed -n 1p .pidly/4/info; }
out=$(PIDLY_AGENT=a PIDLY_LEASE=1h $PIDLY claim 4 2>&1) && rc=0 || rc=$?
check "an agent takes a lease" "$rc" "0"
before=$(line)
out=$(PIDLY_AGENT=a PIDLY_LEASE=3h $PIDLY claim 4 2>&1) && rc=0 || rc=$?
check "and claiming it again succeeds" "$rc" "0"
case $out in "4 renewed by a@- "*) ok "and says it renewed" ;; *) no "message was: $out" ;; esac
after=$(line)
case $after in "claim:a@- "*) ok "the claim is still the agent's lease" ;; *) no "line 1 is: $after" ;; esac
# ISO-8601 UTC sorts chronologically, so the 3h lease ends later.
later=$(printf '%s\n%s\n' "${before##* }" "${after##* }" | sort | tail -n 1)
if [ "$later" = "${after##* }" ] && [ "$after" != "$before" ]
then ok "with a later expiry"; else no "expiry did not move: $before -> $after"; fi

out=$(PIDLY_AGENT=b PIDLY_LEASE=1h $PIDLY claim 4 2>&1) && rc=0 || rc=$?
check "another agent still cannot take a live lease" "$rc" "1"
case $out in *"cannot check"*) ok "and is told why" ;; *) no "message was: $out" ;; esac
check "and the lease is untouched" "$(line)" "$after"

sedi '1s/.*/claim:/' .pidly/4/info
out=$(PIDLY_PID=$$ $PIDLY claim 4 2>&1) && rc=0 || rc=$?
check "a process takes a pid claim" "$rc" "0"
before=$(line)
out=$(PIDLY_PID=$$ $PIDLY claim 4 2>&1) && rc=0 || rc=$?
check "and the same process claiming again renews it" "$rc" "0"
case $out in "4 renewed by "*) ok "and says so" ;; *) no "message was: $out" ;; esac
check "a pid claim renews to itself" "$(line)" "$before"
out=$(PIDLY_PID=$PPID $PIDLY claim 4 2>&1) && rc=0 || rc=$?
check "another live process is still refused" "$rc" "1"
case $out in *"which is running"*) ok "and is told why" ;; *) no "message was: $out" ;; esac
check "and the claim is untouched" "$(line)" "$before"

# holder and lease_expiry can die. They used to run under the ticket's lock,
# and a die there left the lock behind.
sedi '1s/.*/claim:/' .pidly/4/info
out=$(PIDLY_AGENT=a PIDLY_LEASE=bogus $PIDLY claim 4 2>&1) && rc=0 || rc=$?
check "a bad lease is refused" "$rc" "1"
check "without leaving the lock behind" "$(find .pidly/4 -name '.lock*' | wc -l | tr -d ' ')" "0"
out=$(PIDLY_PID=999999 $PIDLY claim 4 2>&1) && rc=0 || rc=$?
check "a PIDLY_PID that is not running is refused" "$rc" "1"
check "without leaving the lock behind either" "$(find .pidly/4 -name '.lock*' | wc -l | tr -d ' ')" "0"
check "and the ticket stays free" "$(line)" "claim:"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
