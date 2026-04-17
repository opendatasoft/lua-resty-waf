OPENRESTY_PREFIX ?= /usr/local/openresty
LUA_LIB_DIR      ?= $(OPENRESTY_PREFIX)/site/lualib
INSTALL_SOFT     ?= ln -s
INSTALL          ?= install
RESTY_BINDIR      = $(OPENRESTY_PREFIX)/bin
OPM               = $(RESTY_BINDIR)/opm
OPM_LIB_DIR      ?= $(OPENRESTY_PREFIX)/site
PWD               = `pwd`
LUAROCKS         ?= luarocks

LIBS       = waf waf.lua htmlentities.lua
C_LIBS     = lua-aho-corasick lua-resty-htmlentities libinjection
OPM_LIBS   = hamishforbes/lua-resty-iputils p0pr0ck5/lua-resty-cookie \
	p0pr0ck5/lua-ffi-libinjection p0pr0ck5/lua-resty-logger-socket
MAKE_LIBS  = $(C_LIBS) decode
SO_LIBS    = libac.so libinjection.so libhtmlentities.so libdecode.so
RULES      = rules
ROCK_DEPS  = "lrexlib-pcre 2.7.2-1" lrexlib-pcre2 busted luafilesystem

LOCAL_LIB_DIR = lib/resty

.PHONY: all test install clean test-unit test-acceptance test-regression \
test-translate lua-aho-corasick lua-resty-htmlentities libinjection \
clean-libinjection clean-lua-aho-corasick install-opm-libs clean-opm-libs \
image test-docker shell-docker manifest verify-manifest

all: $(MAKE_LIBS) debug-macro

clean: clean-libinjection clean-lua-aho-corasick clean-lua-resty-htmlentities \
	clean-decode clean-libs clean-test clean-debug-macro

clean-debug-macro:
	./tools/debug-macro.sh clean

clean-install: clean-deps
	cd $(LUA_LIB_DIR) && rm -rf $(RULES) && rm -f $(SO_LIBS) && cd resty/ && \
		rm -rf $(LIBS)

clean-decode:
	cd src && make clean

clean-deps: clean-opm-libs clean-rocks

clean-lua-aho-corasick:
	cd lua-aho-corasick && make clean

clean-lua-resty-htmlentities:
	cd lua-resty-htmlentities && make clean
	rm -f lib/resty/htmlentities.lua

clean-libinjection:
	cd libinjection && make clean && git checkout -- .

clean-libs:
	cd lib && rm -f $(SO_LIBS)

clean-opm-libs:
	$(OPM) --install-dir=$(OPM_LIB_DIR) remove $(OPM_LIBS)

clean-rocks:
	for ROCK in $(ROCK_DEPS); do \
		$(LUAROCKS) remove --tree=$(OPENRESTY_PREFIX) $$ROCK; \
	done
	rm -f $(OPENRESTY_PREFIX)/lualib/rex_pcre2.so

clean-test:
	rm -rf t/servroot*

debug-macro:
	./tools/debug-macro.sh

decode:
	cd src/ && make
	cp src/libdecode.so lib/

lua-aho-corasick:
	cd $@ && make PREFIX=/usr
	cp $@/libac.so lib/

lua-resty-htmlentities:
	cd $@ && make
	cp $@/lib/resty/htmlentities.lua lib/resty
	cp $@/libhtmlentities.so lib/

libinjection:
	./tools/fix-libinjection-py3.sh
	cd $@ && make all
	cp $@/src/$@.so lib/

test-unit:
	PATH=$(OPENRESTY_PREFIX)/nginx/sbin:$$PATH prove -r ./t/unit

test-acceptance:
	PATH=$(OPENRESTY_PREFIX)/nginx/sbin:$$PATH prove -r ./t/acceptance

test-regression:
	PATH=$(OPENRESTY_PREFIX)/nginx/sbin:$$PATH prove -r ./t/regression

test-translate:
	prove -r ./t/translate/

test-lua-aho-corasick:
	cd lua-aho-corasick && make test

test-lua-resty-htmlentities:
	cd lua-resty-htmlentities && make test

test-libinjection:
	cd libinjection && make check

test: clean all test-unit test-acceptance test-regression test-translate

test-libs: clean all test-lua-aho-corasick test-lua-resty-htmlentities \
	test-libinjection

test-recursive: test test-libs

# hermetic container test environment
# The supported way to run the suite. Every pin lives in ci/versions.env;
# the image is built locally, used, and never pushed anywhere.
CI_DIR              = ci
CI_IMAGE           ?= lua-resty-waf-ci:local
CI_BUILD_ARGS       = $(shell sed -n 's/^\([A-Z_][A-Z0-9_]*\)=\(.*\)/--build-arg \1=\2/p' $(CI_DIR)/versions.env)
# Optional per-machine overrides for networks that block :80 or MITM TLS
# (e.g. APT_SCHEME=https). Gitignored: local infrastructure, not project
# configuration, so it must never change what CI or a laptop resolves.
CI_LOCAL_ARGS       = $(shell test -f $(CI_DIR)/local.env && sed -n 's/^\([A-Z_][A-Z0-9_]*\)=\(.*\)/--build-arg \1=\2/p' $(CI_DIR)/local.env)
DOCKER_BUILD_FLAGS ?=

image:
	docker build -t $(CI_IMAGE) $(CI_BUILD_ARGS) $(CI_LOCAL_ARGS) $(DOCKER_BUILD_FLAGS) \
		-f $(CI_DIR)/Dockerfile $(CI_DIR)

# --network none is load-bearing: it is what proves no test reaches
# outside the container. Source is read-only; the build happens on a
# copy inside (tools/debug-macro.sh rewrites lib/resty/**.lua in place).
# Narrow a run with: make test-docker SUITE=t/unit/util
test-docker: image
	docker run --rm --network none -v $(PWD):/src:ro -e SUITE="$(SUITE)" $(CI_IMAGE)

shell-docker: image
	docker run --rm -it --network none -v $(PWD):/src:ro $(CI_IMAGE) /bin/bash

manifest: image
	docker run --rm --entrypoint /ci/manifest.sh $(CI_IMAGE) > $(CI_DIR)/manifest.lock

verify-manifest: image
	docker run --rm --entrypoint /ci/manifest.sh $(CI_IMAGE) > /tmp/manifest.actual
	diff -u $(CI_DIR)/manifest.lock /tmp/manifest.actual

test-fast: all
	TEST_NGINX_RANDOMIZE=1 PATH=$(OPENRESTY_PREFIX)/nginx/sbin:$$PATH prove \
		-j16 -r ./t/translate
	TEST_NGINX_RANDOMIZE=1 PATH=$(OPENRESTY_PREFIX)/nginx/sbin:$$PATH prove \
		-j16 -r ./t/unit
	TEST_NGINX_RANDOMIZE=1 PATH=$(OPENRESTY_PREFIX)/nginx/sbin:$$PATH prove \
		-j16 -r ./t/regression
	TEST_NGINX_RANDOMIZE=1 PATH=$(OPENRESTY_PREFIX)/nginx/sbin:$$PATH prove \
		-j4 -r ./t/acceptance
	rebusted -k -o=TAP ./t/translation/*
	./tools/lua-releng -L

install-check:
	stat lib/*.so > /dev/null

install-deps: install-opm-libs install-rocks

install-opm-libs:
	$(OPM) --install-dir=$(OPM_LIB_DIR) get $(OPM_LIBS)

install-rocks:
	for ROCK in $(ROCK_DEPS); do \
		$(LUAROCKS) install --tree=$(OPENRESTY_PREFIX) $$ROCK; \
	done
	# translate.lua requires rex_pcre2, but luarocks' own --tree layout
	# ($(OPENRESTY_PREFIX)/lib/lua/5.1/) isn't on nginx's default
	# lua_package_cpath; copy it where nginx will actually find it
	cp $(OPENRESTY_PREFIX)/lib/lua/5.1/rex_pcre2.so $(OPENRESTY_PREFIX)/lualib/

install-link: install-check
	$(INSTALL_SOFT) $(PWD)/lib/resty/* $(LUA_LIB_DIR)/resty/
	$(INSTALL_SOFT) $(PWD)/lib/*.so $(LUA_LIB_DIR)
	$(INSTALL_SOFT) $(PWD)/rules/ $(LUA_LIB_DIR)

install: install-check install-deps
	$(INSTALL) -d $(LUA_LIB_DIR)/resty/waf/storage
	$(INSTALL) -d $(LUA_LIB_DIR)/rules
	$(INSTALL) -m 644 lib/resty/*.lua $(LUA_LIB_DIR)/resty/
	$(INSTALL) -m 644 lib/resty/waf/*.lua $(LUA_LIB_DIR)/resty/waf/
	$(INSTALL) -m 644 lib/resty/waf/storage/*.lua $(LUA_LIB_DIR)/resty/waf/storage/
	$(INSTALL) -m 644 lib/*.so $(LUA_LIB_DIR)
	$(INSTALL) -m 644 rules/*.json $(LUA_LIB_DIR)/rules/

install-soft: install-check install-deps install-link
