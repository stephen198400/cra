# The development commands in one list: `just` prints it (brew install just).
# Each recipe runs one script in scripts/ or Tests/ and passes its arguments on, so
# `just build debug` is `scripts/build.sh debug`. The scripts' header comments have the
# details, and the scripts work the same without just.

set positional-arguments
set shell := ["bash", "-euo", "pipefail", "-c"]

[private]
default:
    @{{just_executable()}} --justfile {{quote(justfile())}} --list --unsorted

# Downloads the pinned CEF into vendor/ (build does this too)
[group('build')]
fetch:
    scripts/fetch-cef.sh

# Builds build/From.app; `debug` for a debug build
[group('build')]
build *args:
    scripts/build.sh "$@"

# Opens build/From.app, building it if missing: [--rebuild [debug] [app arguments…]]
[group('build')]
run *args:
    scripts/run.sh "$@"

# Dev loop: debug CraDev.app, rebuilt and relaunched on save; --once builds and launches once
[group('build')]
dev *args:
    scripts/dev.sh "$@"

# What CI runs on every pull request, in seconds, no CEF needed; `core` for CraCore only
[group('test')]
test *args:
    scripts/test.sh "$@"

# Cra's own lint rules (part of test); --update-baseline lowers Tests/lint-baseline.txt
[group('test')]
lint *args:
    scripts/lint.py "$@"

# Launches build/From.app (or the app given) three times with crash checks, about 30 s
[group('test')]
smoke *args:
    Tests/smoke-launch.sh "$@"

# A user journey from Tests/Scenarios in build/From.app, or `all` (about 6 minutes)
[group('test')]
scenario name:
    scripts/scenario.sh "$@"

# Line coverage and the changed-lines gate; --base <ref> (default origin/main)
[group('test')]
coverage *args:
    scripts/coverage.py "$@"

# The Chromium file parsers (bookmark import, extension prefs) on mutated fixtures, under AddressSanitizer
[group('test')]
fuzz:
    scripts/fuzz.sh

# Mutation testing of the pure code, minutes; a word limits it to matching files
[group('test')]
mutate *args:
    scripts/mutate.py "$@"

# Packages build/From.app (or the app given) into build/dist: DMG, zip, checksums
[group('release')]
package *args:
    scripts/package.sh "$@"

# Build, sign, notarize and package as <version>; tags run this in CI
[group('release')]
release version:
    CRA_VERSION="$1" scripts/release.sh

# Is a newer stable CEF out? Prints only; the daily workflow opens the issue
[group('cef')]
check-cef-update:
    scripts/check-cef-update.sh --dry-run

# Builds the pinned CEF from source with H.264/AAC and scripts/cef-patches (~80 GB, hours)
[group('cef')]
build-cef:
    scripts/build-cef.sh

# Uploads that build as the pre-release cef-<version>-codecsN
[group('cef')]
publish-cef:
    scripts/publish-cef.sh

# Moves Cra to <cef_version>: build, publish, pin, rebuild
[group('cef')]
update-cef cef_version:
    scripts/update-cef.sh "$1"
