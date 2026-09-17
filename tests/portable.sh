#!/bin/sh
# Tests that pidly keeps to a portable find. The suite runs on one machine,
# so it cannot prove pidly works on macOS; what it can do is refuse the
# extensions that would stop it — statically, and by running the commands
# with a find that rejects them.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }

# -mindepth is the one non-POSIX primary allowed: BSD and GNU both have it,
# which is the bar everything here has to clear.
gnuisms='-printf -print0 -maxdepth -quit -regextype -newermt -delete -execdir -ls -iname -ipath -regex -samefile'

echo "the script itself"
# Comments are stripped first: this file and the script both have to be able
# to name an option in order to explain why it is not used.
code() { grep -v '^[[:space:]]*#' "$1"; }
for opt in $gnuisms; do
	n=$(code "$PIDLY" | grep -c -- "find .*$opt" || true)
	check "no $opt in a find" "$n" "0"
done

echo "the idioms it publishes"
# The reference and the AGENTS.md block hand agents find commands to run, and
# those are the ones no test would otherwise exercise.
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
PIDLY_PID=$$; export PIDLY_PID
$PIDLY init >/dev/null
for opt in $gnuisms; do
	n=$(cat .pidly/README.md AGENTS.md | grep -c -- "find .*$opt" || true)
	check "no $opt in a published idiom" "$n" "0"
done

echo "running under a find that has none of them"
mkdir bin
real=$(command -v find)
{
	printf '#!/bin/sh\n'
	printf '# A find with nothing BSD lacks. Anything else is the bug.\n'
	printf 'for a in "$@"; do\n'
	printf '\tcase $a in\n'
	printf '\t%s)\n' "$(printf '%s\n' $gnuisms | tr '\n' '|' | sed 's/|$//')"
	printf '\t\techo "find: $a is not portable" >&2; exit 2 ;;\n'
	printf '\tesac\n'
	printf 'done\n'
	printf 'exec %s "$@"\n' "$real"
} > bin/find
chmod +x bin/find
PATH="$tmp/bin:$PATH"; export PATH
check "the shim refuses what it is meant to" \
	"$(find . -printf '%f\n' >/dev/null 2>&1 || echo $?)" "2"

$PIDLY new -f handoff=x "first" </dev/null >/dev/null 2>&1 || true
out=$($PIDLY new "one" </dev/null 2>&1) && rc=0 || rc=$?
check "new works" "$rc" "0"
$PIDLY new -p 1 "a child" </dev/null >/dev/null
$PIDLY list >/dev/null && ok "list works" || no "list"
$PIDLY list -a >/dev/null && ok "list -a works" || no "list -a"
$PIDLY list --stale 1s >/dev/null && ok "list --stale works" || no "list --stale"
$PIDLY tree >/dev/null && ok "tree works" || no "tree"
$PIDLY field handoff >/dev/null && ok "field works" || no "field"
$PIDLY fields >/dev/null && ok "fields works" || no "fields"
$PIDLY set 1 handoff "note" >/dev/null && ok "set works" || no "set"
$PIDLY claim 1 >/dev/null && ok "claim works" || no "claim"
$PIDLY status 1 >/dev/null && ok "status works" || no "status"
$PIDLY release 1 >/dev/null && ok "release works" || no "release"
$PIDLY reap >/dev/null && ok "reap works" || no "reap"
printf 'a body\n' | $PIDLY edit -b 1 >/dev/null && ok "edit works" || no "edit"
$PIDLY close 2 >/dev/null && ok "close works" || no "close"
$PIDLY reopen 2 >/dev/null && ok "reopen works" || no "reopen"
$PIDLY init >/dev/null && ok "init works" || no "init"
$PIDLY agents >/dev/null && ok "agents works" || no "agents"
$PIDLY check >/dev/null && ok "check works" || no "check"

echo "and gives the same answers"
tree_shim=$($PIDLY tree)
PATH=${PATH#"$tmp/bin:"}
check "tree is unchanged with the real find back" "$($PIDLY tree)" "$tree_shim"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
