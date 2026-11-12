#!/bin/bash
# Mutated copies of the Chromium fixtures through their parsers, under AddressSanitizer
# (Tests/FuzzTests.swift). CRA_FUZZ_ITERATIONS (default 20000) and CRA_FUZZ_SEED; a crash
# leaves its input in build/fuzz/crash-input.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-fuzz.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p build/fuzz
xcrun swiftc -swift-version 5 -parse-as-library -sanitize=address -g \
  Packages/CraCore/Sources/CraCore/*.swift Packages/CraCore/Sources/CraCore/Perf/*.swift Sources/Cra/Perf/Perf.swift \
  Sources/Cra/Services/ExtensionImporter.swift \
  Tests/FuzzTests.swift -o "$TEST_DIR/fuzz"
CRA_FUZZ_OUT="$PWD/build/fuzz" "$TEST_DIR/fuzz"
