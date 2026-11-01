#!/usr/bin/env bash
# Prints what a push needs, from what changed between two commits, as rdp-release-kit's
# build/changes.sh does:
#
#   ci/changes.sh <before> <after>     "none", "test" or "release"
#
# - none: nothing a build reads changed: only docs (*.md, LICENSE) or the comments of
#   sources.lock. No build, no release.
# - release: an input of the package changed: a pin line of sources.lock, packaging/ or
#   ci/build.sh (the kit-key's inputs). Build, test, and publish the rolling release
#   (unless that key or version is already released).
# - test: anything else the build reads (the other scripts, the workflow): build and test,
#   so the change is proven, but the package is the same, so nothing is published.
#   Unknown <before> (a new branch, a force-push, a commit this clone lacks) counts as
#   release; the publish step still refuses what is already released.
set -euo pipefail
before=${1:-} after=${2:-HEAD}

release() { echo release; exit 0; }
[[ $before =~ ^[0-9a-f]{7,40}$ ]] && [[ ! $before =~ ^0+$ ]] || release
git cat-file -e "$before^{commit}" 2> /dev/null || release

pins() { git show "$1:sources.lock" | grep -v -E '^\s*(#|$)' || true; }

scope="none"
while IFS= read -r path; do
	case $path in
	*.md | LICENSE) ;;
	sources.lock) [ "$(pins "$before")" = "$(pins "$after")" ] || release ;;
	packaging/* | ci/build.sh) release ;;
	*) scope="test" ;;
	esac
done < <(git diff --name-only "$before" "$after")
echo "$scope"
