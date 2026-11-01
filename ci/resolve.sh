#!/usr/bin/env bash
# Read sources.lock, clone the screen mirror and say what to build, as KEY=value lines for
# $GITHUB_ENV (or eval in a local run).
#
# Usage: ci/resolve.sh <kit dir> <clone dir> [<ref> <run id>]
#   no <ref>  the pinned build: screen's commit from sources.lock, which must still be the tip
#             of its release branch (a release never moves), and the pinned screen-base as
#             the control
#   <ref>     a test build of another mirror branch or commit (e.g. integration-screen before
#             a pick), version <upstream>+ci<run id>.<sha7>-1, control = its merge-base with
#             screen-base's branch; never published
#
# Prints SHA, VERSION, CONTROL ("-" when sources.lock has no screen-base), SRC (the mirror's
# URL), REF (what was asked for) and PINNED (true or false).
set -euo pipefail
kit=$1 clone=$2 ref=${3:-} run=${4:-0}

field() { awk -v n="$1" -v c="$2" '$1 == n { print $c; exit }' "$kit/sources.lock"; }
version=$(field screen 2) url=$(field screen 3) commit=$(field screen 4)
base_branch=$(field screen-base 2) base_commit=$(field screen-base 4)
[ -n "$commit" ] || { echo "::error::sources.lock has no screen line" >&2; exit 1; }
src=${url#git+} branch=${src#*#}
src=${src%%#*}

[ -d "$clone/.git" ] || git clone -q --no-checkout "$src" "$clone"
g() { git -C "$clone" "$@"; }

if [ -z "$ref" ]; then
	sha=$(g rev-parse --verify "$commit^{commit}")
	tip=$(g rev-parse --verify "origin/$branch^{commit}")
	if [ "$tip" != "$sha" ]; then
		echo "::error::$branch is at ${tip:0:12} on the mirror, sources.lock pins ${sha:0:12}; a release must never move" >&2
		exit 1
	fi
	control=-
	if [ -n "$base_commit" ]; then
		control=$(g rev-parse --verify "$base_commit^{commit}")
		g merge-base --is-ancestor "$control" "$sha" ||
			{ echo "::error::screen-base ${control:0:12} is not an ancestor of ${sha:0:12}" >&2; exit 1; }
	fi
	pinned=true
else
	sha=$(g rev-parse --verify -q "origin/$ref^{commit}" || g rev-parse --verify "$ref^{commit}")
	up=$(g describe --tags --abbrev=0 --match 'v.*' --match 'v[0-9]*' "$sha")
	up=${up#v.}
	up=${up#v}
	version=$up+ci$run.${sha:0:7}-1
	control=-
	[ -z "$base_branch" ] || control=$(g merge-base "$sha" "origin/$base_branch")
	pinned=false
fi

printf 'SHA=%s\nVERSION=%s\nCONTROL=%s\nSRC=%s\nREF=%s\nPINNED=%s\n' \
	"$sha" "$version" "$control" "$src" "${ref:-$branch}" "$pinned"
