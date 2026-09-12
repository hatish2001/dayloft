#!/usr/bin/env python3
"""Validate launch resources, isolated identifiers, and embedded helper requirements."""
import platform
import plistlib
from pathlib import Path
import re
import subprocess
import sys

app = Path(sys.argv[1])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'org.dayloft.Dayloft'
assert info['CFBundleName'] == 'Dayloft'
resources = app / 'Contents/Resources'
for name in ['Base.lproj/MainMenu.nib', 'Base.lproj/TimerWindow.nib', 'DayloftIcon.icns', 'ThirdPartyNotices.txt']:
    assert (resources / name).exists(), f'Missing launch/runtime resource: {name}'
assert (app / 'Contents/Frameworks/Sparkle.framework').is_dir(), 'Missing update framework'
for name in ['Sentry.framework']:
    assert not (app / 'Contents/Frameworks' / name).exists(), f'Unexpected upstream service: {name}'
helper = app / 'Contents/Library/LaunchServices/org.dayloft.focusd'
assert helper.is_file(), 'Missing privileged helper'
assert (app / 'Contents/MacOS/dayloft-cli').is_file(), 'Missing CLI'
def embedded_plist(section):
    output = subprocess.check_output(
        ['/usr/bin/otool', '-arch', platform.machine(), '-s', '__TEXT', section, str(helper)],
        text=True,
    )
    raw = bytearray()
    for line in output.splitlines():
        fields = line.split()
        if fields and re.fullmatch(r'[0-9a-fA-F]{16}', fields[0]):
            for word in fields[1:]:
                if re.fullmatch(r'[0-9a-fA-F]{8}', word):
                    raw.extend(int(word, 16).to_bytes(4, 'little'))
                elif re.fullmatch(r'[0-9a-fA-F]{2}', word):
                    raw.append(int(word, 16))
    end = raw.find(b'</plist>')
    assert end >= 0, f'Helper {section} section missing'
    return plistlib.loads(bytes(raw[:end + len(b'</plist>')]))

helper_info = embedded_plist('__info_plist')
assert helper_info['CFBundleIdentifier'] == 'org.dayloft.focusd'
for version_key in ['CFBundleVersion', 'CFBundleShortVersionString']:
    assert helper_info[version_key] == info[version_key], 'App and helper versions disagree'
client_rule = helper_info['SMAuthorizedClients'][0]
assert 'org.dayloft.Dayloft' in client_rule and 'org.dayloft.cli' in client_rule
assert 'org.eyebeam' not in client_rule and 'DAYLOFT_SIGNING_TEAM' not in client_rule
launchd_info = embedded_plist('__launchd_plist')
assert launchd_info['MachServices']['org.dayloft.focusd'] is True
assert launchd_info['RunAtLoad'] is True
assert launchd_info['KeepAlive'] is False, 'Idle helper must remain registered without being kept alive'
service_rule = info['SMPrivilegedExecutables']['org.dayloft.focusd']
assert 'org.dayloft.focusd' in service_rule
if '=' in service_rule and service_rule.rsplit('=', 1)[1].strip():
    team = service_rule.rsplit('=', 1)[1].strip()
    assert client_rule.endswith(team), 'App and helper signing teams disagree'
print('App resources and helper identity checks passed.')

if '--universal' in sys.argv[2:]:
    count = 0
    for binary in app.rglob('*'):
        if binary.is_file() and not binary.is_symlink() and 'Mach-O' in subprocess.check_output(['file', '-b', str(binary)], text=True):
            subprocess.run(['lipo', str(binary), '-verify_arch', 'arm64', 'x86_64'], check=True)
            count += 1
    assert count >= 3, 'Missing app, CLI, or helper binaries'
    print(f'Both architectures verified in {count} binaries.')
