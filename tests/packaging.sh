#!/bin/sh
# Tests for the package recipes in packaging/, which are kept ready to submit
# before anyone has approved submitting them.
#
# A recipe is a second place a version is written down, and the one nobody
# runs until release day. So this suite holds each of them to the script: the
# version it names is VERSION in bin/pidly, the files it installs exist, and
# the recipes agree with one another about the checksum. It cannot say the
# recipes build — that takes brew and makepkg — only that they have not
# drifted from what they package.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FORMULA=$ROOT/packaging/homebrew/pidly.rb
PKGBUILD=$ROOT/packaging/aur/PKGBUILD
SRCINFO=$ROOT/packaging/aur/.SRCINFO
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }

version=$(sed -n 's/^VERSION=//p' "$ROOT/bin/pidly")
tag=v$version

echo "the recipes are there"
for f in "$FORMULA" "$PKGBUILD" "$SRCINFO"; do
	check "${f#"$ROOT"/}" "$([ -f "$f" ] && echo yes || echo no)" "yes"
done

echo "they name the version the script carries"
check "the formula's url is the $tag tarball" \
	"$(sed -n 's/^  url "\(.*\)"$/\1/p' "$FORMULA")" \
	"https://github.com/ShannonTully/pidly/archive/refs/tags/$tag.tar.gz"
check "PKGBUILD's pkgver" "$(sed -n 's/^pkgver=//p' "$PKGBUILD")" "$version"
check ".SRCINFO's pkgver" "$(sed -n 's/^	pkgver = //p' "$SRCINFO")" "$version"
check ".SRCINFO's source" "$(sed -n 's/^	source = //p' "$SRCINFO")" \
	"pidly-$version.tar.gz::https://github.com/ShannonTully/pidly/archive/refs/tags/$tag.tar.gz"

echo "and agree with each other"
# The checksum is a placeholder until a tag is pushed and a real one once it
# is. Either way there is one tarball, so there is one answer.
sum=$(sed -n 's/^  sha256 "\(.*\)"$/\1/p' "$FORMULA")
check "PKGBUILD has the formula's checksum" \
	"$(sed -n "s/^sha256sums=('\(.*\)')$/\1/p" "$PKGBUILD")" "$sum"
check ".SRCINFO has it too" "$(sed -n 's/^	sha256sums = //p' "$SRCINFO")" "$sum"
check "a checksum is a sha256 or the placeholder" \
	"$(printf '%s\n' "$sum" | grep -Ec '^([0-9a-f]{64}|UNRELEASED)$')" "1"
check "the description is the same in all three" \
	"$({ sed -n 's/^  desc "\(.*\)"$/\1/p' "$FORMULA"
	    sed -n "s/^pkgdesc='\(.*\)'$/\1/p" "$PKGBUILD"
	    sed -n 's/^	pkgdesc = //p' "$SRCINFO"; } | sort -u | wc -l | tr -d ' ')" "1"
check ".SRCINFO's pkgrel is PKGBUILD's" \
	"$(sed -n 's/^	pkgrel = //p' "$SRCINFO")" "$(sed -n 's/^pkgrel=//p' "$PKGBUILD")"

echo "the licence is the one the script declares"
spdx=$(sed -n 's/^# SPDX-License-Identifier: //p' "$ROOT/bin/pidly")
check "the formula's" "$(sed -n 's/^  license "\(.*\)"$/\1/p' "$FORMULA")" "$spdx"
check "PKGBUILD's" "$(sed -n "s/^license=('\(.*\)')$/\1/p" "$PKGBUILD")" "$spdx"

echo "what they install exists"
for f in bin/pidly docs/pidly.1 LICENSE; do
	check "$f" "$([ -f "$ROOT/$f" ] && echo yes || echo no)" "yes"
done
check "and the script is executable" "$([ -x "$ROOT/bin/pidly" ] && echo yes || echo no)" "yes"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
