"""Build the upload zip for CurseForge.

    python .dev-tests/build_release.py [output-dir]

Takes the git-tracked files, drops everything `.pkgmeta` ignores, and writes
`dist/QuestPrism-<version>.zip` with a single `QuestPrism/` folder inside, which is the
layout CurseForge expects. Fails if the TOC loads a file the package would not contain.

This is a local convenience: the BigWigs packager builds the same thing from the tag.
"""
import os
import re
import subprocess
import sys
import zipfile

# Kept in step with the ignore list in .pkgmeta.
IGNORE = ['.dev-tests', '.gitignore', '.gitattributes', '.pkgmeta', 'README.md', 'CHANGELOG.md', 'docs', 'dist']

ADDON = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def shipped_files():
    tracked = subprocess.run(['git', '-C', ADDON, 'ls-files'], capture_output=True, text=True).stdout.split('\n')
    return [f for f in tracked if f and not any(f == i or f.startswith(i + '/') for i in IGNORE)]


def toc_version(toc_text):
    match = re.search(r'^## Version:\s*(\S+)', toc_text, re.M)
    if not match:
        raise SystemExit('no "## Version:" line in QuestPrism.toc')
    return match.group(1)


def toc_entries(toc_text):
    entries = []
    for line in toc_text.split('\n'):
        line = line.strip()
        if line and not line.startswith('#'):
            entries.append(line.replace(chr(92), '/'))
    return entries


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ADDON, 'dist')
    os.makedirs(out_dir, exist_ok=True)

    toc_text = open(os.path.join(ADDON, 'QuestPrism.toc'), encoding='utf-8').read()
    version = toc_version(toc_text)
    ship = shipped_files()

    missing = [e for e in toc_entries(toc_text) if e not in ship]
    if missing:
        raise SystemExit('the TOC loads files the package would not contain: ' + ', '.join(missing))

    zip_path = os.path.join(out_dir, 'QuestPrism-' + version + '.zip')
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for f in ship:
            archive.write(os.path.join(ADDON, f), 'QuestPrism/' + f)

    print('QuestPrism ' + version)
    print(str(len(ship)) + ' files, ' + str(round(os.path.getsize(zip_path) / 1024)) + ' KB')
    print(zip_path)


if __name__ == '__main__':
    main()
