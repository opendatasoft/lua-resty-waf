# Vendored third-party code

lua-resty-waf is GPL-3.0 (`COPYING`). Every licence below is compatible
with that.

## Why it is in-tree

Upstream (`p0pr0ck5/lua-resty-waf`) is discontinued and this fork has to
keep building without it. Anything resolved over the network at build
time (`git submodule update`, `opm get`) depends on someone else's
namespace still existing. None of the code below has moved in years, and
two of the sources are archived read-only upstream, so tracking it bought
nothing.

Nothing is modified except where stated, so each entry can be verified
against the upstream bytes it was taken from.

## Verifying

`ci/vendor.lock` pins every path below by content hash. It is to the
vendored code what `ci/manifest.lock` is to the test image.

```sh
make verify-vendor    # fail if any vendored path no longer hashes as recorded
make vendor-lock      # regenerate, after a deliberate re-vendor
```

`.github/workflows/test.yml` runs the check on every push and pull
request. It is what the gitlink SHAs used to do for free: without it an
edit to libinjection's SQLi detector, or to any vendored Lua module,
passes all seven test gates unnoticed. `tools/vendor-hash` hashes the
tracked files' working-tree content, so committed and uncommitted changes
are caught alike, and build artifacts are excluded because they are
untracked.

Re-vendoring is therefore: replace the path, update the table below, run
`make vendor-lock`, and commit the three together.

## C libraries (formerly git submodules)

Built by `make`, installed as `.so` files.

| path | upstream | pinned at | licence |
|---|---|---|---|
| `libinjection/` | https://github.com/client9/libinjection | `e1cd4e447c1352f1b3cd2169299b6b67556eb922` | BSD-3-Clause, `libinjection/COPYING` |
| `lua-aho-corasick/` | https://github.com/cloudflare/lua-aho-corasick | `db91eeda60e210fa2a816cb120124b42169a6f0d` | BSD-3-Clause, `lua-aho-corasick/LICENSE` |
| `lua-resty-htmlentities/` | https://github.com/detailyang/lua-resty-htmlentities | `b1c01a9f3df7744c752b7486f752a07eb9cb9f9b` | MIT, `lua-resty-htmlentities/LICENSE` |

`lua-aho-corasick` is archived upstream; the others were last pushed in
2023 and 2017.


**One local modification:** `libinjection/src/{make_parens,sqlparse_map,sqlparse2c}.py`
are patched to run under python3. That used to be applied at build time
by `tools/fix-libinjection-py3.sh`; it is now a commit and the script is
gone.

**A second local modification:** `src/fingerprints.txt`,
`src/sqlparse_data.json` and `src/libinjection_sqli_data.h` are committed
as the build produces them, not as upstream ships them.

libinjection's `src/Makefile` makes the phony `fingerprints` target a
prerequisite of `sqlparse_data.json`, so its code generators rerun on
every build regardless of mtimes, and they rewrite those three tracked
files in place. Upstream's committed copies are not a fixed point of
their own generators: one pass adds four fingerprints, eighteen table
entries, and fills `sqlparse_data.json`, which upstream commits empty.
A second and third pass change nothing.

Committing the converged output makes `make` idempotent on the working
tree. Without it every build left three tracked files modified, which a
`git commit -a` would quietly pick up, and `make clean` had to run `git
checkout` to undo, which meant `make clean`, `make test` and `make
test-libs` all failed outside a git checkout. The build still regenerates
these files and still produces byte-identical `.so` output; it now
produces byte-identical *sources* too, so the tree stays clean.

The in-tree copies are therefore the ones the shipped library is actually
built from, which is what anyone auditing the SQLi fingerprint tables
wants to read.

## Lua modules (formerly OPM packages)

Installed by `make install` with the rest of `lib/`. Byte-for-byte what
`opm get` serves for the versions `ci/versions.env` used to pin, so
behaviour is unchanged.

| path | OPM package | version | licence |
|---|---|---|---|
| `lib/resty/cookie.lua` | `p0pr0ck5/lua-resty-cookie` | `0.01` | BSD-2-Clause (Cloudflare) |
| `lib/resty/iputils.lua` | `hamishforbes/lua-resty-iputils` | `0.3.0` | MIT |
| `lib/resty/libinjection.lua` | `p0pr0ck5/lua-ffi-libinjection` | `0.1.1` | BSD-3-Clause |
| `lib/resty/logger/socket.lua` | `p0pr0ck5/lua-resty-logger-socket` | `0.03` | BSD-2-Clause (Cloudflare) |
| `lib/util.lua` | n/a | n/a | MPL-2.0 (Mozilla heka) |

That is all of them, so the project has no OPM dependency and the test
image installs no OPM client. `ci/manifest.sh` asserts that under
`## opm` so it cannot come back by accident.

`lua-resty-cookie` and `lua-resty-logger-socket` are not p0pr0ck5's own
work; they republish `cloudflare/lua-resty-cookie` and
`cloudflare/lua-resty-logger-socket`. The OPM metadata for the logger
claims `license = gpl3`, which matches neither the file's copyright
header nor its upstream README. The Cloudflare terms are what is honoured
here. Neither Cloudflare repository ships a `LICENSE` file, so the text
is reproduced below, as BSD requires of redistributed source.

Both Cloudflare originals have moved on since the versions OPM served:
`lua-resty-logger-socket` master differs from `0.03` by about two dozen
lines. Taking those is a deliberate upgrade, not done here.

`lib/util.lua` is unchanged and predates this file. It is required under
the bare name `util` by `lib/resty/waf/util.lua`, which is why it sits at
the root of the Lua path rather than under `resty/`.

### BSD licence, as published by Cloudflare

Applies to `lib/resty/cookie.lua` and `lib/resty/logger/socket.lua`.

```
Copyright (C) 2013, by Jiale Zhi <vipcalio@gmail.com>, CloudFlare Inc.
Copyright (C) 2013, by Yichun Zhang <agentzh@gmail.com>, CloudFlare Inc.

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

* Redistributions of source code must retain the above copyright notice,
  this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in the
  documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### BSD licence, lua-ffi-libinjection

Applies to `lib/resty/libinjection.lua`. From `LICENSE` in
https://github.com/p0pr0ck5/lua-ffi-libinjection, which the OPM package
does not carry and the file itself has no header for.

```
Copyright 2017 Robert Paprocki

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

1. Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### MIT licence, lua-resty-iputils

Applies to `lib/resty/iputils.lua`. From `LICENSE.txt` in
https://github.com/hamishforbes/lua-resty-iputils, which the OPM package
does not carry.

```
The MIT License (MIT)

Copyright (c) 2013 Hamish Forbes

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

## Still fetched

LuaRocks (`lrexlib-pcre`, `lrexlib-pcre2`, `busted`, `luafilesystem`),
OpenResty and its Debian packages, and the CPAN test harness. All pinned
in `ci/versions.env` and `ci/cpan.lock`.
