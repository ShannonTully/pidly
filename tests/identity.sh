#!/bin/sh
# Tests for claim identity (pid + start time + runtime) and leases.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
. "$(dirname "$0")/lib.sh"
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
state() { $PIDLY status "$1" | cut -f2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pidly.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"; mkdir -p .pidly/1
printf 'claim:\nneeds:\ntitle: one\n\nbody\n' > .pidly/1/info

echo "process identity"
check "an unclaimed ticket is free" "$(state 1)" "unclaimed"
sh -c "PIDLY_PID=\$\$ $PIDLY claim 1 >/dev/null; $PIDLY status 1 > st"
check "a claim is live while its process runs" "$(cut -f2 st)" "live"
check "and dead once it exits" "$(state 1)" "dead"

held=$(sed -n '1s/^claim://p' .pidly/1/info)
case $held in
*.*@*) ok "the claim records pid.starttime@runtime" ;;
*)     no "claim has no start time or runtime: $held" ;;
esac

# Same pid, different start time: a recycled number must not read as the
# original process.
sh -c "PIDLY_PID=\$\$ $PIDLY claim 1 >/dev/null 2>&1" || true
sedi '1s|\.[0-9]*@|.999999999@|' .pidly/1/info
check "a recycled pid is not mistaken for its predecessor" "$(state 1)" "dead"

# A claim from another process table cannot be judged at all.
sedi '1s|@[^ ]*|@someother.u0|' .pidly/1/info
check "a claim from another runtime is unverifiable" "$(state 1)" "unverifiable"
out=$($PIDLY claim 1 2>&1) && rc=0 || rc=$?
check "and cannot be taken" "$rc" "1"
case $out in *"cannot check"*) ok "the refusal says why" ;; *) no "message: $out" ;; esac
sedi '1s/.*/claim:/' .pidly/1/info

echo "leases"
out=$(PIDLY_AGENT=cloud-1 $PIDLY claim 1 2>&1) && rc=0 || rc=$?
check "an agent with no process must carry a lease" "$rc" "1"
case $out in *PIDLY_LEASE*) ok "the refusal names PIDLY_LEASE" ;; *) no "message: $out" ;; esac

PIDLY_AGENT=cloud-1 PIDLY_LEASE=2h $PIDLY claim 1 >/dev/null
check "a leased claim is unverifiable, not dead" "$(state 1)" "unverifiable"
case $(sed -n 1p .pidly/1/info) in
"claim:cloud-1@- "*Z) ok "line 1 carries holder and expiry" ;;
*) no "line 1 is $(sed -n 1p .pidly/1/info)" ;;
esac
out=$(sh -c "PIDLY_PID=\$\$ $PIDLY claim 1" 2>&1) && rc=0 || rc=$?
check "a live lease blocks other claimants" "$rc" "1"

sedi '1s|[0-9-]*T[0-9:]*Z|2020-01-01T00:00:00Z|' .pidly/1/info
check "an expired lease reads as expired" "$(state 1)" "expired"
sh -c "PIDLY_PID=\$\$ $PIDLY claim 1 >/dev/null" && rc=0 || rc=$?
check "and the ticket can be taken over" "$rc" "0"

out=$(PIDLY_AGENT="bad@name" PIDLY_LEASE=1h $PIDLY claim 1 2>&1) && rc=0 || rc=$?
check "an agent name with @ is rejected" "$rc" "1"
out=$(PIDLY_AGENT=cloud-2 PIDLY_LEASE=banana $PIDLY claim 1 2>&1) && rc=0 || rc=$?
check "a malformed lease is rejected" "$rc" "1"

# Set but empty is a variable that did not exist. It used to fall through to
# the pid branch and record a local pid for an agent with no local process,
# silently — which is what the published PIDLY_AGENT=$SESSION_ID line did.
sedi '1s/.*/claim:/' .pidly/1/info
out=$(PIDLY_AGENT='' PIDLY_LEASE=1h $PIDLY claim 1 2>&1) && rc=0 || rc=$?
check "an empty agent name is rejected, not a fallback to the pid" "$rc" "1"
case $out in *PIDLY_AGENT*) ok "the refusal names PIDLY_AGENT" ;; *) no "message: $out" ;; esac
check "and nothing was claimed" "$(state 1)" "unclaimed"

# Unset is the caller who does want pid identity, and still gets it.
sh -c "unset PIDLY_AGENT; PIDLY_PID=\$\$ $PIDLY claim 1 >/dev/null"
case $(sed -n 1p .pidly/1/info) in
claim:[0-9]*) ok "an unset agent name still claims as the process" ;;
*) no "line 1 is $(sed -n 1p .pidly/1/info)" ;;
esac

sedi '1s/.*/claim:/' .pidly/1/info
for d in 90s 30m 2h 3d 45; do
	PIDLY_AGENT=a PIDLY_LEASE=$d $PIDLY claim 1 >/dev/null
	case $(sed -n 1p .pidly/1/info) in
	*" "[0-9][0-9][0-9][0-9]-*Z) ;;
	*) no "lease $d produced $(sed -n 1p .pidly/1/info)"; continue ;;
	esac
	sedi '1s/.*/claim:/' .pidly/1/info
done
ok "durations 90s 30m 2h 3d and bare seconds all parse"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
