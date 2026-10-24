#!/bin/sh
# Ticket arguments: every command that takes <n> refuses anything but digits.
# A number used to reach find -name, which takes a glob: '1*' or '[3]'
# resolved to whichever ticket find met first, '.n' to the number registry,
# and '*' to the tracker root itself (ticket 59).
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
# Every path under .pidly and what each file holds, locks aside: a refused
# command must leave all of it as it was.
tree() {
	find .pidly -name '.lock*' -prune -o -print | sort | while IFS= read -r p; do
		if [ -f "$p" ]; then printf '%s %s\n' "$p" "$(cksum < "$p")"
		else printf '%s\n' "$p"; fi
	done
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pidly.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
PIDLY_PID=$$; export PIDLY_PID

echo "close '*' with no open top-level ticket"
# With nothing open at the top, the first directory find met for '*' was
# .pidly itself, so close ran `mv .pidly ./c/`.
mkdir star; cd star
$PIDLY init >/dev/null
$PIDLY new "only" </dev/null >/dev/null
$PIDLY close 1 >/dev/null
before=$(tree)
out=$($PIDLY close '*' 2>&1) && rc=0 || rc=$?
check "is refused" "$rc" "1"
case $out in *"not a ticket number: '*'"*) ok "as not a ticket number" ;; *) no "message: $out" ;; esac
check "and moves no tracker into ./c" "$([ -e c ] && echo moved || echo stayed)" "stayed"
check "and changes nothing" "$(tree)" "$before"
$PIDLY check >/dev/null 2>&1 && rc=0 || rc=$?
check "check still passes" "$rc" "0"
cd "$tmp"

echo "close .n"
# The registry is a directory under .pidly like a ticket's, and closing it
# silently removed the merge-conflict protection it exists for.
mkdir dotn; cd dotn
$PIDLY init >/dev/null
$PIDLY new "one" </dev/null >/dev/null
before=$(tree)
out=$($PIDLY close .n 2>&1) && rc=0 || rc=$?
check "is refused" "$rc" "1"
case $out in *"not a ticket number: '.n'"*) ok "as not a ticket number" ;; *) no "message: $out" ;; esac
check "and the registry stays where it is" "$(tree)" "$before"
cd "$tmp"

echo "every command that takes a ticket"
mkdir all; cd all
$PIDLY init >/dev/null
for t in one two three; do $PIDLY new "$t" </dev/null >/dev/null; done
$PIDLY close 3 >/dev/null
before=$(tree)
# Each command line, with {} where the argument goes; with no {}, it goes
# last. One per line, words split on spaces.
cmds='close
claim
release -m x
status
show
reopen
reap
needs
set {} title t
edit -a
new -p {} child
reparent {} 1
reparent 1 {}
reparent -r'
for arg in '*' '1*' '[3]' '?' '' '3x' '/' '.n'; do
	bad=""
	while IFS= read -r cmd; do
		set -- $cmd
		placed=no
		for w in "$@"; do
			shift
			if [ "$w" = "{}" ]; then set -- "$@" "$arg"; placed=yes
			else set -- "$@" "$w"; fi
		done
		[ "$placed" = yes ] || set -- "$@" "$arg"
		out=$(printf 'body\n' | $PIDLY "$@" 2>&1) && rc=0 || rc=$?
		if [ "$rc" -eq 0 ]; then
			bad="$bad [$cmd: exit 0]"
		else
			case $out in
			*"not a ticket number: '$arg'"*) ;;
			*) bad="$bad [$cmd: $out]" ;;
			esac
		fi
		[ "$(tree)" = "$before" ] || { bad="$bad [$cmd: changed the tracker]"; break; }
	done <<EOF
$cmds
EOF
	if [ -z "$bad" ]; then ok "'$arg' is refused by every command"
	else no "'$arg':$bad"; fi
done
cd "$tmp"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
