#!/usr/bin/env bash
# Dumps the fully-resolved dependency set of this image.
#
# Docker images are not bit-reproducible by default (timestamps, layer
# ordering), so the image digest is the wrong thing to assert on. What
# actually matters is that the same inputs resolve to the same package
# versions. That is what this captures, and what `make verify-manifest`
# diffs against the committed ci/manifest.lock.
set -euo pipefail

PREFIX="${OPENRESTY_PREFIX:-/usr/local/openresty-debug}"

echo "# lua-resty-waf test image manifest"
echo "# Regenerate with: make manifest"

echo
echo "## nginx"
"${PREFIX}/nginx/sbin/nginx" -V 2>&1 | sed -n '1p;2p'
"${PREFIX}/nginx/sbin/nginx" -V 2>&1 | tr ' ' '\n' | grep -c -- '--with-debug' \
    | sed 's/^/with-debug occurrences: /'

echo
echo "## dpkg"
dpkg-query -W -f='${Package}=${Version}\n' | sort

# Nothing to enumerate: every module this project once fetched from OPM
# is vendored. This records only whether a client is present. It is not
# the check that an OPM dependency has not returned, because `make
# manifest` writes whatever this prints straight into manifest.lock and
# would launder a regression into the baseline. ci/Dockerfile asserts it
# at build time, where it can fail.
echo
echo "## opm"
if command -v opm >/dev/null 2>&1; then echo "client present"; else echo "none (all vendored)"; fi

echo
echo "## luarocks"
luarocks --tree="${PREFIX}" list --porcelain 2>/dev/null | sort || true

echo
echo "## perl"
perl -MExtUtils::Installed -e '
    my $i = ExtUtils::Installed->new;
    for my $m (sort $i->modules) {
        my $v = eval { $i->version($m) } // "undef";
        print "$m=$v\n";
    }
' 2>/dev/null || true

echo
echo "## tooling"
printf 'rebusted=%s\n' "$(sha256sum /usr/local/bin/rebusted | cut -d' ' -f1)"
printf 'fixture.text.tar=%s\n'  "$(sha256sum /opt/fixtures/aho-corasick/text.tar  | cut -d' ' -f1)"
printf 'fixture.image.bin=%s\n' "$(sha256sum /opt/fixtures/aho-corasick/image.bin | cut -d' ' -f1)"
