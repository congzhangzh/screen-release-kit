# screen-release-kit

Builds, tests and releases [GNU Screen](https://www.gnu.org/software/screen/) with our fixes,
as a Debian package and a binary tarball. The screen code itself lives in the mirror,
[congzhangzh/screen](https://github.com/congzhangzh/screen); this repository holds only what
turns a commit of it into a release: the pin, the packaging, the build and the tests.

## Install

Take the newest [release](../../releases/latest). On Debian testing/unstable (amd64):

```sh
sudo apt install ./screen_<version>_amd64.deb
```

This replaces Debian's `screen` package. The tarball holds the same binary with its man page
and encodings, for a prefix such as `~/.local` beside Debian's package; the release notes give
the commands. Note that `~/.local/bin` comes first in most `PATH`s, so a `screen` there hides
`/usr/bin/screen`.

## From a fix to a release

| Where | What |
|---|---|
| mirror, `fix-*` | One fix each, on upstream `screen-v5`, also reported upstream |
| mirror, `integration-screen` | `screen-v5` plus every `fix-*` branch, rebuilt whenever one of them or the base moves |
| kit, run with `ref` | Tests a mirror branch before it is picked: `gh workflow run kit.yml -R congzhangzh/screen-release-kit -f ref=integration-screen` |
| mirror, `release-YYYYMMDD.N` | A tested `integration-screen` commit, picked as a release; never moves |
| kit, `sources.lock` | Pins that commit and the package version; the push to `main` builds and tests it and publishes the rolling release |

**Rolling releases**, as [rdp-release-kit](https://github.com/congzhangzh/rdp-release-kit)
makes them: every push to `main` that passes publishes the release `<YYYYMMDD>.<N>` (the day
it is published, then a counter), as GitHub's latest release, once, never replaced. So
[releases/latest](../../releases/latest) always leads to a tested build. A push that changes
nothing the package is made of (the pin, the packaging, `ci/build.sh`) publishes nothing: the
notes of each release carry a `kit-key` naming those inputs. Pull requests and runs with
`ref` only build and test. The package
version comes from `sources.lock`: `<upstream>+r<YYYYMMDD>.<N>-<revision>`, e.g.
`5.0.2+r20261101.1-1`, where `r<YYYYMMDD>.<N>` names the mirror's release branch. That makes it
newer than Debian's `5.0.2-N` and older than a future `5.0.3`, so apt moves to Debian's
package once Debian ships a newer upstream release. A new pick starts at revision 1; a change
to the kit's packaging alone bumps the revision. A package version is released once: when a
release here or in the mirror already has it, the run publishes nothing and warns that the
revision needs a bump.

The first release, `5.0.2+r20261101.1-1`, was published from the mirror before this kit
existed: <https://github.com/congzhangzh/screen/releases/tag/r20261101.1>.

## What a run does

[`.github/workflows/kit.yml`](.github/workflows/kit.yml) runs on a push to `main` that changes
the pin, the packaging or the scripts, on pull requests, and by hand. In a `debian:testing`
container:

1. [`ci/resolve.sh`](ci/resolve.sh) reads [`sources.lock`](sources.lock), clones the mirror
   and checks the pin: the pinned commit must still be the tip of its release branch, and the
   pinned base an ancestor of it. With `ref`, it resolves that branch instead and names the
   build `<upstream>+ci<run>.<sha>-1`.
2. [`ci/run.sh`](ci/run.sh) installs the build dependencies and runs the next three steps.
3. [`ci/build.sh`](ci/build.sh) builds the commit with Debian's packaging and flags (PAM,
   `/run/screen`, `/etc/screenrc`) and makes the tarball from the same build.
4. [`ci/build-control.sh`](ci/build-control.sh) builds the base, plain upstream without our
   fixes, as a control.
5. [`ci/test.sh`](ci/test.sh) runs [`ci/repro.py`](ci/repro.py) as a normal user: the build
   must survive 10 runs with two attached displays and 3 with one, and the control must crash
   at least once, or the test no longer reproduces the bug
   ([Savannah #67589](https://savannah.gnu.org/bugs/?67589)).
6. On `main`, for the pin only, and only when every test passed,
   [`ci/publish-release.py`](ci/publish-release.py) publishes the rolling release unless its
   inputs or its version are already released: a draft with the assets first, then the
   release, which creates the tag, so a failure leaves at most a draft. Every run also keeps
   its build as a workflow artifact.

The same pipeline runs locally in a container:

```sh
podman run --rm -v "$PWD":/kit:ro -v /some/work/dir:/w -w /w debian:testing bash -c '
  apt-get update -q && apt-get install -y -q --no-install-recommends git ca-certificates
  eval "$(/kit/ci/resolve.sh /kit screen)"
  /kit/ci/run.sh screen "$SHA" "$CONTROL" "$VERSION" out'
```

Keep the work dir short: screen's socket path, under it, must fit in 108 bytes.

## Packaging

[`packaging/debian`](packaging/debian) is Debian's screen 5.0.2-1
(<https://tracker.debian.org/pkg/screen>), unchanged except that its patch series drops the
five patches upstream `screen-v5` already has (91, 95, 98, 99, 100). The other 16 apply as
they are.

## License

The kit's own files (`ci/`, `.github/`, this README) are under the Apache License 2.0
([`LICENSE`](LICENSE)). [`packaging/debian`](packaging/debian) keeps Debian's terms, GPL-3+
(see its [`copyright`](packaging/debian/copyright)), as screen does.
