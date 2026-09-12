#!/usr/bin/env python3
"""The app, privileged helper, and Xcode-generated header must ship one version."""
from pathlib import Path
import plistlib
import re

root = Path(__file__).resolve().parent.parent / 'SelfControl'
app = plistlib.loads((root / 'Info.plist').read_bytes())
helper = plistlib.loads((root / 'Daemon/selfcontrold-Info.plist').read_bytes())
version, build = app['CFBundleShortVersionString'], app['CFBundleVersion']
assert re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version), 'Use a semantic release version'
assert build.isdecimal() and int(build) > 0, 'Use a positive, increasing build number'
assert (version, build) == (helper['CFBundleShortVersionString'], helper['CFBundleVersion']), 'App/helper version mismatch'
project = (root / 'SelfControl.xcodeproj/project.pbxproj').read_text()
assert set(re.findall(r'MARKETING_VERSION = ([^;]+);', project)) == {version}, 'Xcode display version mismatch'
assert set(re.findall(r'CURRENT_PROJECT_VERSION = ([^;]+);', project)) == {build}, 'Xcode build number mismatch'
assert (root / 'version-header.h').read_text().strip() == f'#define SELFCONTROL_VERSION_STRING @"{version}"', 'Helper runtime version mismatch'
print(f'App, helper, Xcode, and runtime version agree: {version} ({build}).')
