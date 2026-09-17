#!/bin/sh
# Run every suite. Exits nonzero if any of them fail.
set -eu
cd "$(dirname "$0")"
rc=0
for t in new.sh claim.sh identity.sh agents.sh; do
	printf '\n=== %s ===\n' "$t"
	./"$t" || rc=1
done
printf '\n'
[ "$rc" -eq 0 ] && echo "all suites passed" || echo "SOME SUITES FAILED"
exit "$rc"
