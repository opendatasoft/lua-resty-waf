#!/usr/bin/env bash
# Runs the whole suite against a pristine copy of the mounted source.
#
# SUITE=<path>  narrow the run to one directory or .t file (prove only)
set -euo pipefail

SRC=${SRC:-/src}
BUILD=${BUILD:-/build}

# `make` is destructive to the source tree: tools/debug-macro.sh rewrites
# the --_LOG_ macros in lib/resty/**.lua in place, leaving 11 tracked
# files modified. Always build on a copy so the host tree stays pristine
# and a read-only mount is possible.
if [[ -d "$SRC" ]]; then
    rm -rf "$BUILD"
    cp -a "$SRC" "$BUILD"
fi
cd "$BUILD"

export OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-/usr/local/openresty-debug}"
export PATH="${OPENRESTY_PREFIX}/nginx/sbin:${OPENRESTY_PREFIX}/bin:${OPENRESTY_PREFIX}/luajit/bin:${PATH}"

# The aho-corasick test Makefile would otherwise curl these over ftp://
# mid-test. Pre-seeded from the image so `make test-libs` never needs the
# network.
mkdir -p lua-aho-corasick/tests/testinput
cp -n /opt/fixtures/aho-corasick/text.tar  lua-aho-corasick/tests/testinput/ 2>/dev/null || true
cp -n /opt/fixtures/aho-corasick/image.bin lua-aho-corasick/tests/testinput/ 2>/dev/null || true

echo "=== build ==="
make

# Narrow run: everything below is skipped.
if [[ -n "${SUITE:-}" ]]; then
    echo "=== prove ${SUITE} ==="
    exec prove -r "${SUITE}"
fi

fail=0
gate() {
    local name=$1; shift
    echo
    echo "=== ${name} ==="
    if "$@"; then
        echo "--- ${name}: PASS"
    else
        echo "--- ${name}: FAIL" >&2
        fail=1
    fi
}

# Run every gate even when an early one fails, so that one run reports
# the whole picture, not just the first thing to break.
gate "t/unit"        prove -r ./t/unit
gate "t/acceptance"  prove -r ./t/acceptance
gate "t/regression"  prove -r ./t/regression
gate "t/translate"   prove -r ./t/translate
# t/translation runs under rebusted, i.e. busted inside `resty`. Unlike the
# .t suites, which get the library from lua_package_path in each test's
# own nginx config, rebusted inherits nothing: both busted (a luarocks
# tree) and the project's lib/ must be on LUA_PATH.
#
# Critically, LUA_PATH is set *only* in this subshell. Exporting it for
# the whole script silently breaks t/acceptance/logging/01_configurables.t
# (tests 40/45/50), because it leaks into the nginx-based suites too.
#
# No -k (.travis.yml used it): it continues past failures and can mask a
# non-zero exit, which is how this suite stayed broken without anyone
# noticing.
gate "t/translation" bash -c '
    eval "$(luarocks --tree="${OPENRESTY_PREFIX}" path)"
    export LUA_PATH="${PWD}/lib/?.lua;${PWD}/lib/?/init.lua;${LUA_PATH}"
    rebusted -o=TAP ./t/translation/*
'
gate "test-libs"     make test-libs
gate "lua-releng"    ./tools/lua-releng -L

echo
if (( fail )); then
    echo "RESULT: FAIL"
    exit 1
fi
echo "RESULT: PASS"
