# Hermetic test image for lua-resty-waf.
#
# Built locally by `make image`, used by `make test-docker`, never pushed.
# Contains no repo source: the working tree is mounted at /src at run time
# and copied to /build, because `make` rewrites lib/resty/**.lua in place
# via tools/debug-macro.sh and must not touch the host tree.
#
# Every version comes from ci/versions.env as a --build-arg.

ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG DEBIAN_SNAPSHOT
ARG APT_SCHEME=http
ARG OPENRESTY_VERSION
ARG OPENRESTY_OPENSSL3
ARG OPENRESTY_PCRE2
ARG OPENRESTY_ZLIB
ARG OPENRESTY_PREFIX
ARG OPM_IPUTILS
ARG OPM_COOKIE
ARG OPM_LIBINJECTION
ARG OPM_LOGGER
ARG ROCK_LREXLIB_PCRE
ARG ROCK_LREXLIB_PCRE2
ARG ROCK_BUSTED
ARG ROCK_LUAFILESYSTEM
ARG REBUSTED_SHA
ARG FIXTURE_URL
ARG FIXTURE_SHA256

ENV DEBIAN_FRONTEND=noninteractive
ENV OPENRESTY_PREFIX=${OPENRESTY_PREFIX}
ENV PATH=${OPENRESTY_PREFIX}/nginx/sbin:${OPENRESTY_PREFIX}/bin:${OPENRESTY_PREFIX}/luajit/bin:/usr/local/openresty/bin:$PATH

# optional CA bootstrap (for networks that MITM TLS or block :80)
# Empty by default, so this is a no-op on a laptop or in CI. Debian base
# images ship no CA bundle at all, and the ca-certificates package cannot
# be installed before apt can fetch, so any .crt dropped in ci/extra-ca/
# is written straight into the bundle path apt's TLS stack reads.
COPY extra-ca/ /tmp/extra-ca/
RUN set -eux; \
    if ls /tmp/extra-ca/*.crt >/dev/null 2>&1; then \
        mkdir -p /etc/ssl/certs; \
        cat /tmp/extra-ca/*.crt >> /etc/ssl/certs/ca-certificates.crt; \
        echo "seeded CA bundle from ci/extra-ca/"; \
    fi; \
    rm -rf /tmp/extra-ca

# distro packages, pinned to a Debian snapshot
# Check-Valid-Until must be off: snapshot Release files are long expired
# by definition. Snapshots are immutable, so this is not a weakened check.
#
# APT_SCHEME defaults to http because Debian archives are GPG-signed (so
# transport integrity is not what protects them) and the base image has
# no CA bundle yet. Override to https where :80 egress is blocked, which
# requires seeding ci/extra-ca/ above.
RUN set -eux; \
    printf 'deb %s://snapshot.debian.org/archive/debian/%s bookworm main\n\
deb %s://snapshot.debian.org/archive/debian-security/%s bookworm-security main\n' \
      "${APT_SCHEME}" "${DEBIAN_SNAPSHOT}" "${APT_SCHEME}" "${DEBIAN_SNAPSHOT}" > /etc/apt/sources.list; \
    rm -f /etc/apt/sources.list.d/debian.sources; \
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/10no-check-valid-until; \
    echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/10retries; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        gnupg \
        cpanminus \
        liblua5.1-0-dev \
        libpcre2-dev \
        libpcre3-dev \
        luarocks \
        make \
        memcached \
        perl \
        python3 \
        python-is-python3 \
        redis-server \
        unzip; \
    rm -rf /var/lib/apt/lists/*

# OpenResty (debug build only)
# Debian component is 'openresty', not 'main'.
RUN set -eux; \
    curl -fsSL https://openresty.org/package/pubkey.gpg \
      | gpg --dearmor -o /usr/share/keyrings/openresty.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/debian bookworm openresty" \
      > /etc/apt/sources.list.d/openresty.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        openresty-debug="${OPENRESTY_VERSION}" \
        openresty-opm="${OPENRESTY_VERSION}" \
        openresty-openssl3-debug="${OPENRESTY_OPENSSL3}" \
        openresty-pcre2="${OPENRESTY_PCRE2}" \
        openresty-zlib="${OPENRESTY_ZLIB}"; \
    rm -rf /var/lib/apt/lists/*; \
    "${OPENRESTY_PREFIX}/nginx/sbin/nginx" -V 2>&1 | grep -q -- --with-debug

# OPM modules, into the debug prefix
# Installing these into the *wrong* prefix is the trap that made
# 01_protocol_violations.t fail with a misleading "loop or previous error
# loading module 'resty.waf'". Only one prefix exists here, so it cannot
# recur, but assert anyway.
RUN set -eux; \
    /usr/local/openresty/bin/opm --install-dir="${OPENRESTY_PREFIX}/site" get \
        "${OPM_IPUTILS}" \
        "${OPM_COOKIE}" \
        "${OPM_LIBINJECTION}" \
        "${OPM_LOGGER}"; \
    test -f "${OPENRESTY_PREFIX}/site/lualib/resty/logger/socket.lua"

# LuaRocks
# rex_pcre2 is copied to lualib/ because luarocks' own --tree layout
# (lib/lua/5.1) is not on nginx's default lua_package_cpath.
RUN set -eux; \
    luarocks install --tree="${OPENRESTY_PREFIX}" lrexlib-pcre "${ROCK_LREXLIB_PCRE}"; \
    luarocks install --tree="${OPENRESTY_PREFIX}" lrexlib-pcre2 "${ROCK_LREXLIB_PCRE2}"; \
    luarocks install --tree="${OPENRESTY_PREFIX}" busted "${ROCK_BUSTED}"; \
    luarocks install --tree="${OPENRESTY_PREFIX}" luafilesystem "${ROCK_LUAFILESYSTEM}"; \
    cp "${OPENRESTY_PREFIX}/lib/lua/5.1/rex_pcre2.so" "${OPENRESTY_PREFIX}/lualib/"

# Perl test harness, exact versions
# ci/cpan.lock pins the whole closure, not just the nine roots this
# project names; the script asserts the result still matches it.
COPY cpan.lock cpan-install.sh /ci/
RUN set -eux; bash /ci/cpan-install.sh /ci/cpan.lock

# rebusted (runs the t/translation busted specs under resty)
RUN set -eux; \
    curl -fsSL -o /usr/local/bin/rebusted \
      "https://raw.githubusercontent.com/thibaultcha/lua-resty-busted/${REBUSTED_SHA}/bin/busted"; \
    chmod +x /usr/local/bin/rebusted

# test fixtures, baked in so no test needs the network
# lua-aho-corasick/tests/Makefile wants testinput/{text.tar,image.bin}.
# image.bin is only bulk binary input for the stress test, never decoded
# as an image, so the same tarball serves for both.
RUN set -eux; \
    mkdir -p /opt/fixtures/aho-corasick; \
    curl -fsSL -o /tmp/fixture.tar.gz "${FIXTURE_URL}"; \
    echo "${FIXTURE_SHA256}  /tmp/fixture.tar.gz" | sha256sum -c -; \
    cp /tmp/fixture.tar.gz /opt/fixtures/aho-corasick/image.bin; \
    gzip -dc /tmp/fixture.tar.gz > /opt/fixtures/aho-corasick/text.tar; \
    rm -f /tmp/fixture.tar.gz

# git ownership
# The mounted checkout (and therefore the copy built from it) is owned
# by whoever cloned it: a laptop user, or the runner user under GitHub
# Actions. This container runs as root, and git refuses to operate on a
# repository owned by someone else ("detected dubious ownership"), which
# breaks `make test-libs`: clean-libinjection runs `git checkout` inside
# the submodule. The container is disposable and the repository is the
# user's own, so there is nothing to protect against here.
RUN git config --global --add safe.directory '*'

COPY entrypoint.sh run-tests.sh manifest.sh /ci/
RUN chmod +x /ci/*.sh

WORKDIR /build
ENTRYPOINT ["/ci/entrypoint.sh"]
CMD ["/ci/run-tests.sh"]
