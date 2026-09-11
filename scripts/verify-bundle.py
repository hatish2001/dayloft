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
output = subprocess.check_output(['/usr/bin/otool', '-arch', platform.machine(), '-s', '__TEXT', '__info_plist', str(helper)], text=True)
raw = bytearray()
for line in output.splitlines():
    fields = line.split()
    if fields and re.fullmatch(r'[0-9a-fA-F]{16}', fields[0]):
        for word in fields[1:]:
            if re.fullmatch(r'[0-9a-fA-F]{8}', word):
                raw.extend(int(word, 16).to_bytes(4, 'little'))
            elif re.fullmatch(r'[0-9a-fA-F]{2}', word):
                # otool prints remaining bytes separately when the section size
                # is not divisible by four (for example, unsigned helper builds).
                raw.append(int(word, 16))
end = raw.find(b'</plist>')
assert end >= 0, 'Helper Info.plist section missing'
helper_info = plistlib.loads(bytes(raw[:end + len(b'</plist>')]))
assert helper_info['CFBundleIdentifier'] == 'org.dayloft.focusd'
client_rule = helper_info['SMAuthorizedClients'][0]
assert 'org.dayloft.Dayloft' in client_rule and 'org.dayloft.cli' in client_rule
assert 'org.eyebeam' not in client_rule and 'DAYLOFT_SIGNING_TEAM' not in client_rule
service_rule = info['SMPrivilegedExecutables']['org.dayloft.focusd']
assert 'org.dayloft.focusd' in service_rule
if '=' in service_rule and service_rule.rsplit('=', 1)[1].strip():
    team = service_rule.rsplit('=', 1)[1].strip()
    assert client_rule.endswith(team), 'App and helper signing teams disagree'
print('App resources and helper identity checks passed.')
