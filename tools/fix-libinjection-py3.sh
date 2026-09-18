#!/bin/bash
# libinjection's vendored build scripts (make_parens.py,
# sqlparse_map.py, sqlparse2c.py) use python2-only syntax (the old
# `print x` statement, dict.iterkeys()). python2 is obsolete now, so
# this patches those scripts to run under python3, in the submodule's
# *working tree* only; nothing is ever committed inside the
# submodule. `clean` reverts them to the submodule's tracked,
# pristine content.
set -euo pipefail

cd "$(dirname "$0")/../libinjection/src"

if [ "${1:-}" == "clean" ]; then
	git checkout -- make_parens.py sqlparse_map.py sqlparse2c.py fingerprints.txt 2>/dev/null || true
	exit 0
fi

# these scripts are run by libinjection's Makefile through their own
# shebang, which is `#!/usr/bin/env python`. Debian has shipped no
# `python` binary since python2 was removed, so point them at python3
# explicitly rather than relying on a python-is-python3 alias being
# installed on the build host.
sed -i '1s|^#!/usr/bin/env python$|#!/usr/bin/env python3|' \
	make_parens.py sqlparse_map.py sqlparse2c.py

# every print statement touched below has a single argument, so
# wrapping it in parens is valid syntax under both python 2 and 3
sed -i 's/^\(\s*\)print \(.*\)$/\1print(\2)/' make_parens.py
sed -i 's/^\(\s*\)print \(.*\)$/\1print(\2)/' sqlparse_map.py

# sqlparse2c.py also has bare `print` (blank line) statements, a
# print of a triple-quoted multi-line string literal, and a dict
# .iterkeys() call, none of which python 3 supports
sed -i \
	-e 's/^\(\s*\)print$/\1print()/' \
	-e '17s/^    print """$/    print("""/' \
	-e '51s/^"""$/""")/' \
	-e 's/^\(\s*\)print \(".*\)$/\1print(\2)/' \
	-e 's/\.iterkeys()/.keys()/' \
	sqlparse2c.py
