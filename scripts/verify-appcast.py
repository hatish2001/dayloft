#!/usr/bin/env python3
"""Fail packaging if the update feed does not describe this exact installer."""
import base64
from pathlib import Path
import plistlib
import sys
import xml.etree.ElementTree as ET

feed, app, archive = map(Path, sys.argv[1:])
with (app / 'Contents/Info.plist').open('rb') as handle:
    info = plistlib.load(handle)
sparkle = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = ET.parse(feed).findall('./channel/item')
assert len(items) == 1, 'Expected one full update'
item = items[0]
enclosure = item.find('enclosure')
assert enclosure is not None, 'Missing installer'
assert item.findtext(sparkle + 'version') == info['CFBundleVersion'], 'Build mismatch'
assert item.findtext(sparkle + 'shortVersionString') == info['CFBundleShortVersionString'], 'Version mismatch'
expected = f"https://github.com/hatish2001/dayloft/releases/download/v{info['CFBundleShortVersionString']}/{archive.name}"
assert enclosure.get('url') == expected, 'Incorrect release URL'
assert int(enclosure.get('length', '0')) == archive.stat().st_size, 'Size mismatch'
assert len(base64.b64decode(enclosure.get(sparkle + 'edSignature', ''), validate=True)) == 64, 'Missing update signature'
assert len(base64.b64decode(info['SUPublicEDKey'], validate=True)) == 32, 'Missing public key'
print('Update feed matches the packaged version, installer, and release URL.')
