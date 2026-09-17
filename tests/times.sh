#!/bin/sh
# Tests for created: the one timestamp the format records. It is written
# once, never updated, valid without the schema declaring it, and
# backfilled by init for tickets that predate it.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
has() { if printf '%s' "$2" | grep -qF "$3"; then ok "$1"; else no "$1 (missing '$3' in: $2)"; fi; }
created() { sed -n 's/^created: //p' "$(find .pidly -type d -name "$1")/info"; }
updated() { sed -n 's/^updated: //p' "$(find .pidly -type d -name "$1")/info"; }
iso='^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$'

tmp=$(mktemp -d); repo=""
trap 'rm -rf "$tmp" ${repo:+"$repo"}' EXIT
cd "$tmp"
PIDLY_PID=$$; export PIDLY_PID
$PIDLY init >/dev/null
$PIDLY new "first" </dev/null >/dev/null      # 1

echo "new"
check "writes a created field" "$(created 1 | grep -Ec "$iso")" "1"
check "in UTC" "$(created 1 | grep -c 'Z$')" "1"
check "on line 4, ahead of the project's own fields" \
	"$(sed -n 4p .pidly/1/info | cut -d: -f1)" "created"
check "and the ticket is valid" "$($PIDLY check >/dev/null && echo clean)" "clean"

echo "it is pidly's field, not the project's"
check "the schema does not declare it at all" \
	"$(grep -c '^field: created' .pidly/schema || true)" "0"
check "and a ticket carrying it still passes check" \
	"$($PIDLY check >/dev/null && echo clean)" "clean"
printf '\nfield: created\nnote: not yours to declare\n' >> .pidly/schema
has "declaring it is a finding" "$($PIDLY check 2>&1 || true)" \
	"schema: 'created' is pidly's own and is not declared here"
sed -i '/^field: created$/,+1d' .pidly/schema

echo "nothing updates created"
was=$(created 1)
$PIDLY claim 1 >/dev/null
printf 'more\n' | $PIDLY edit -a 1 >/dev/null
$PIDLY release -m "stopped here" 1 >/dev/null
$PIDLY close 1 >/dev/null
$PIDLY reopen 1 >/dev/null
check "a claim, an edit, a handoff, a close and a reopen leave it alone" \
	"$(created 1)" "$was"

echo "updated"
check "new stamps it alongside created" "$(updated 1 | grep -Ec "$iso")" "1"
# The stamp has one-second resolution, so a write has to land in a later
# second to be visibly later.
was=$(updated 1); sleep 1
$PIDLY claim 1 >/dev/null
now=$(updated 1)
check "a claim bumps it" "$([ "$now" != "$was" ] && echo bumped)" "bumped"
was=$now; sleep 1
printf 'and more\n' | $PIDLY edit -a 1 >/dev/null
now=$(updated 1)
check "so does an edit" "$([ "$now" != "$was" ] && echo bumped)" "bumped"
was=$now; sleep 1
$PIDLY release -m "here" 1 >/dev/null
now=$(updated 1)
check "and a release" "$([ "$now" != "$was" ] && echo bumped)" "bumped"
was=$now
$PIDLY close 1 >/dev/null
$PIDLY reopen 1 >/dev/null
check "a close and a reopen do not: they never open the file" "$(updated 1)" "$was"
sed -i '/^body/a hand written' .pidly/1/info
check "and neither does an edit pidly did not make" "$(updated 1)" "$was"

echo "the stale query"
$PIDLY new "fresh" </dev/null >/dev/null      # 2
sed -i 's/^updated: .*/updated: 2020-01-01T00:00:00Z/' .pidly/1/info
out=$($PIDLY list --stale 7d)
has "lists work nothing has written to" "$out" "1"
check "and not what was just touched" "$(printf '%s' "$out" | grep -c '^2 ' || true)" "0"
has "showing the day it was last written" "$out" "2020-01-01"
mkdir -p .pidly/3
printf 'claim:\nneeds:\ntitle: undated\n\nbody\n' > .pidly/3/info
out=$($PIDLY list --stale 7d)
has "a ticket with no stamp is listed rather than assumed fresh" "$out" "undated"
has "with its date unknown" "$out" "3     -"
check "oldest first" "$(printf '%s' "$out" | awk '{print $1}' | tr '\n' ' ')" "3 1 "
out=$($PIDLY list --stale nonsense 2>&1) && rc=0 || rc=$?
check "a duration that is not one is refused" "$rc" "1"
has "saying what one looks like" "$out" "90s, 30m, 2h or 7d"
rm -rf .pidly/3
sed -i "s/^updated: .*/updated: $was/" .pidly/1/info

echo "check"
sed -i 's/^created: .*/created: yesterday/' .pidly/1/info
out=$($PIDLY check 2>&1) && rc=0 || rc=$?
check "a timestamp that is not one is a finding" "$rc" "1"
has "saying what is wrong with it" "$out" "1: created is not an ISO-8601 UTC timestamp"
sed -i "s/^created: .*/created: $was/" .pidly/1/info
keep=$(updated 1)
sed -i 's/^updated: .*/updated: 2000-01-01T00:00:00Z/' .pidly/1/info
has "a ticket updated before it existed" "$($PIDLY check 2>&1 || true)" \
	"1: updated is before created"
sed -i "s/^updated: .*/updated: $keep/" .pidly/1/info

echo "init backfills"
mkdir -p .pidly/9
printf 'claim:\nneeds:\ntitle: made by hand\n\nbody\n' > .pidly/9/info
out=$($PIDLY init)
has "and says how many it dated" "$out" "dated 1 ticket(s)"
check "the hand-made ticket now has one" "$(created 9 | grep -Ec "$iso")" "1"
check "which check accepts" "$($PIDLY check >/dev/null && echo clean)" "clean"
again=$(created 9)
$PIDLY init >/dev/null && rc=0 || rc=$?
check "a second init exits 0 with nothing left to date" "$rc" "0"
check "and does not move the stamp" "$(created 9)" "$again"

echo "a ticket it cannot read"
mkdir -p .pidly/10
printf 'claim:\nneeds:\ntitle: unreadable\n\nbody\n' > .pidly/10/info
was=$(cksum < .pidly/10/info)
chmod 000 .pidly/10/info
$PIDLY init >/dev/null 2>&1 || true
chmod 644 .pidly/10/info
check "is skipped whole rather than rewritten" "$(cksum < .pidly/10/info)" "$was"
check "so it gains no created line" "$(created 10 | wc -l | tr -d ' ')" "0"
check "and leaves no half-written file behind" \
	"$(find .pidly/10 -name 'info.*' | wc -l | tr -d ' ')" "0"
check "the tracker is still valid" "$($PIDLY check >/dev/null && echo clean)" "clean"

echo "dating follows a move"
if command -v git >/dev/null 2>&1; then
	# Its own root: a tracker inside a tracker is refused, rightly.
	repo=$(mktemp -d); cd "$repo"
	git init -q .
	git config user.email t@example; git config user.name t
	$PIDLY init >/dev/null
	mkdir .pidly/1
	printf 'claim:\nneeds:\ntitle: born early\n\nbody\n' > .pidly/1/info
	git add -A
	GIT_AUTHOR_DATE='2020-01-01T00:00:00Z' GIT_COMMITTER_DATE='2020-01-01T00:00:00Z' \
		git commit -qm 'open 1'
	mkdir -p .pidly/c && mv .pidly/1 .pidly/c/
	git add -A
	GIT_AUTHOR_DATE='2021-06-06T12:00:00Z' GIT_COMMITTER_DATE='2021-06-06T12:00:00Z' \
		git commit -qm 'close 1'
	$PIDLY init >/dev/null
	# Closing is a move, and a move without --follow reads as an add. A
	# ticket dated the day it finished would be worse than an undated one.
	check "a closed ticket is dated when it was created, not when it closed" \
		"$(created 1)" "2020-01-01T00:00:00Z"
else
	ok "skipped: no git here to date anything from"
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
