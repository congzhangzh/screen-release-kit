#!/usr/bin/env bash
# Build one commit of screen as a Debian package and as a binary tarball, from one build.
#
# Usage: ci/build.sh <screen repo> <commit> <package version> <out dir>
#   <screen repo>      a clone with history and tags
#   <package version>  the Debian version to build, e.g. 5.0.2+r20261101.1-1 for a release
#                      (from sources.lock) or 5.0.2+ci12.abcdef0-1 for a test build; its
#                      upstream part must be the newest upstream tag before <commit>
# Needs Debian's build tools and screen's build dependencies (see packaging/debian/control).
#
# The packaging is Debian's own (screen 5.0.2-1, from packaging/debian), with the patches that
# upstream already has dropped from its series. The upstream part is the newest upstream tag
# before <commit> (v.5.0.2 -> 5.0.2), so a build of screen-v5 is 5.0.2+<pick>-<revision>: newer
# than Debian's 5.0.2-N, older than a future 5.0.3.
set -euo pipefail
repo=$(realpath "$1") commit=$2 full=$3 out=$(realpath -m "$4")
here=$(dirname "$(realpath "$0")")/..

sha=$(git -C "$repo" rev-parse --verify "$commit^{commit}")
up=$(git -C "$repo" describe --tags --abbrev=0 --match 'v.*' --match 'v[0-9]*' "$sha")
up=${up#v.}
up=${up#v}
ver=${full%-*}
if [[ $ver != "$up+"* ]]; then
	echo "::error::version $full does not start with $up+, the newest upstream tag before ${sha:0:12}" >&2
	exit 1
fi
work=$(mktemp -d)
mkdir -p "$out"

echo "building screen $full from ${sha:0:12} (newest upstream tag: $up)"
git -C "$repo" archive --format=tar --prefix="screen-$ver/" "$sha:src" | gzip -9n > "$work/screen_$ver.orig.tar.gz"
tar -xzf "$work/screen_$ver.orig.tar.gz" -C "$work"
cp -r "$here/packaging/debian" "$work/screen-$ver/"

# A changelog entry of our own on top of Debian's.
{
	printf 'screen (%s) unstable; urgency=medium\n\n' "$full"
	printf '  * Build of %s (%s) from the GitHub mirror of GNU screen, by\n' "${sha:0:12}" "$commit"
	printf '    screen-release-kit.\n'
	printf '  * Upstream screen-v5 plus the fix-* branches; drop the Debian patches upstream\n'
	printf '    already has (91, 95, 98, 99, 100).\n\n'
	printf ' -- Cong Zhang <13283869+congzhangzh@users.noreply.github.com>  %s\n\n' "$(date -R -u)"
	cat "$here/packaging/debian/changelog"
} > "$work/screen-$ver/debian/changelog"

(cd "$work/screen-$ver" && dpkg-buildpackage -us -uc -b)

# The tarball: the same binary, the man page and the encodings, laid out for a prefix such
# as ~/.local. The binary was configured for /usr, so it reads /etc/screenrc, keeps its
# sockets in /run/screen and its encodings in /usr/share/screen, as Debian's does.
root="$work/screen-$ver/debian/screen"
tb="$work/tar/screen-$full"
mkdir -p "$tb/bin" "$tb/share/man/man1" "$tb/share/screen"
cp -a "$root/usr/bin/screen" "$tb/bin/"
cp -a "$root/usr/share/man/man1/screen.1.gz" "$tb/share/man/man1/"
cp -a "$root/usr/share/screen/utf8encodings" "$tb/share/screen/"
printf '%s\n' "$sha" > "$tb/SOURCE_COMMIT"
tar -C "$work/tar" -czf "$out/screen-$full-linux-$(dpkg --print-architecture).tar.gz" "screen-$full"

cp "$work"/*.deb "$work"/*.buildinfo "$work"/*.changes "$out/" 2>/dev/null || cp "$work"/*.deb "$out/"
cp "$root/usr/bin/screen" "$out/screen.bin"
(cd "$out" && sha256sum -- *.deb *.tar.gz > SHA256SUMS)
printf 'version=%s\nsha=%s\n' "$full" "$sha" > "$out/build.env"
ls -l "$out"
