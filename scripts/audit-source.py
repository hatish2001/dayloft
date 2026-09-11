#!/usr/bin/env python3
"""Check the public Git file set, without printing potential secret values."""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
paths = subprocess.check_output(
    ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root
).decode().split('\0')
problems = []
secret_patterns = [
    re.compile(r'-----BEGIN ' + r'(?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    re.compile(r'gh[pousr]_' + r'[A-Za-z0-9]{30,}'),
    re.compile(r'AKIA' + r'[A-Z0-9]{16}'),
    re.compile(r'xox[baprs]-' + r'[A-Za-z0-9-]{20,}'),
]
for name in sorted(set(paths)):
    if not name:
        continue
    path = root / name
    if not path.is_file():
        continue
    if path.suffix.lower() in {'.p12', '.p8', '.mobileprovision', '.provisionprofile'}:
        problems.append((name, 'private signing material'))
    if any(part in {'.git', 'xcuserdata', 'DerivedData', 'artifacts', 'build', 'dist'} for part in path.relative_to(root).parts):
        problems.append((name, 'local/generated content'))
    if path.stat().st_size > 10 * 1024 * 1024:
        problems.append((name, 'unexpected large binary'))
    try:
        content = path.read_text()
    except (UnicodeDecodeError, OSError):
        continue
    if any(pattern.search(content) for pattern in secret_patterns):
        problems.append((name, 'possible credential; inspect locally'))
    if re.search(r'/Users/' + r'[^/\s]+/', content):
        problems.append((name, 'machine-specific absolute path'))
for required in ['LICENSE', 'NOTICE.md', 'Gemfile.lock', 'SelfControl/Podfile.lock',
                 'Dayloft.xcworkspace/contents.xcworkspacedata',
                 'SelfControl/SelfControl.xcodeproj/xcshareddata/xcschemes/Dayloft.xcscheme']:
    if required not in paths:
        problems.append((required, 'missing from public file set'))
if problems:
    for name, reason in problems:
        print(f'{name}: {reason}', file=sys.stderr)
    sys.exit(1)
print(f'Public source audit passed ({len(set(paths)) - 1} files).')
