#!/bin/sh
# The number registry exists to turn a silent merge into a refused one.
# These tests drive real git merges, because the feature is entirely a claim
# about what git does.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }

command -v git >/dev/null 2>&1 || { echo "  skipped: git not available"; exit 0; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pidly.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
git init -q .
git config user.email t@example.com
git config user.name tester
git config commit.gpgsign false
$PIDLY init >/dev/null
$PIDLY new "parent" </dev/null >/dev/null          # ticket 1
git add -A && git commit -qm base
base=$(git rev-parse HEAD)

echo "the registry is committed"
check "it is not ignored" "$(git check-ignore .pidly/.n/1 >/dev/null 2>&1 && echo ignored || echo tracked)" "tracked"
check "and the entry for 1 is in the tree" "$(git ls-files .pidly/.n/1)" ".pidly/.n/1"

echo "colliding branches"
git checkout -qb branch-a
$PIDLY new "from A" </dev/null >/dev/null          # ticket 2, at the root
git add -A && git commit -qm "A adds 2"
git checkout -q "$base" 2>/dev/null
git checkout -qb branch-b
$PIDLY new -p 1 "from B" </dev/null >/dev/null     # also 2, under ticket 1
git add -A && git commit -qm "B adds 2"
check "both branches issued the same number" \
	"$(git show branch-a:.pidly/.n/2 >/dev/null 2>&1 && git show branch-b:.pidly/.n/2 >/dev/null 2>&1 && echo yes)" "yes"
check "at different paths" \
	"$(git ls-tree -r --name-only branch-a | grep -c '^\.pidly/2/info')$(git ls-tree -r --name-only branch-b | grep -c '^\.pidly/1/2/info')" "11"

git checkout -q branch-a
git merge branch-b >/dev/null 2>&1 && rc=0 || rc=$?
check "git refuses the merge" "$([ "$rc" -ne 0 ] && echo refused || echo merged)" "refused"
check "and names the number" "$(git diff --name-only --diff-filter=U)" ".pidly/.n/2"
git merge --abort

echo "no false conflicts"
git checkout -q "$base" 2>/dev/null
git checkout -qb branch-c
$PIDLY new "from C" </dev/null >/dev/null          # ticket 2 on this branch
git add -A && git commit -qm "C adds 2"
git checkout -q "$base" 2>/dev/null
git checkout -qb branch-d
$PIDLY new "first on D" </dev/null >/dev/null      # 2
$PIDLY new "second on D" </dev/null >/dev/null     # 3
rm -rf .pidly/2 .pidly/.n/2                        # pretend D only ever made 3
git add -A && git commit -qm "D adds 3"
git checkout -q branch-c
git merge branch-d >/dev/null 2>&1 && rc=0 || rc=$?
check "distinct numbers merge cleanly" "$([ "$rc" -eq 0 ] && echo merged || echo refused)" "merged"
check "both tickets survive" "$(find .pidly -name info | wc -l)" "3"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
