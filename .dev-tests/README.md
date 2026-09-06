# Dev tests

Not loaded by WoW. Run with a Python that has `lupa` installed:

    pip install lupa
    python .dev-tests/run_tests.py

Syntax-checks every Lua file under Lua 5.1 and runs the logic tests against a small WoW API mock.

## Building a release zip

    python .dev-tests/build_release.py

Writes `dist/QuestPrism-<version>.zip` laid out the way CurseForge expects, from the
git-tracked files minus everything `.pkgmeta` ignores. It refuses to build if the TOC
loads a file the package would not contain. The BigWigs packager builds the same thing
from the tag; this is for checking or uploading by hand.
