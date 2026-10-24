#!/usr/bin/env python3
"""Verify native ABI pairs and actual ELF headers in a Godot Android bundle.

This checks the built file, not Google Play account/release eligibility or signing.
Uses only Python's standard library; no extraction or Android SDK required.
"""
import argparse
import collections
import json
from pathlib import Path
import re
import struct
import sys
import zipfile

ABIS = {'armeabi-v7a': (1, 40), 'arm64-v8a': (2, 183),
        'x86': (1, 3), 'x86_64': (2, 62)}
PAIRS = {'armeabi-v7a': 'arm64-v8a', 'x86': 'x86_64'}


def android_preset(path):
    text = Path(path).read_text(encoding='utf-8-sig')
    sections = dict(re.findall(r'^\[([^\]]+)\]\s*\n(.*?)(?=^\[|\Z)', text, re.M | re.S))
    for name, body in sections.items():
        if re.fullmatch(r'preset\.\d+', name) and re.search(r'^name="Android"$', body, re.M):
            options = sections.get(name + '.options', '')
            def value(key, source=options):
                found = re.search(r'^' + re.escape(key) + r'=(.*)$', source, re.M)
                if not found: raise ValueError('Missing Android setting: ' + key)
                return found[1].strip().strip('"')
            if value('gradle_build/use_gradle_build') != 'true':
                raise ValueError('Android App Bundles require Gradle builds')
            if value('gradle_build/export_format') != '1':
                raise ValueError('Default Android export must be AAB (format 1)')
            if not value('export_path', body).lower().endswith('.aab'):
                raise ValueError('Default Android export_path must end in .aab')
            enabled = {abi for abi in ABIS if value('architectures/' + abi) == 'true'}
            if not enabled: raise ValueError('No native architectures selected')
            for narrow, wide in PAIRS.items():
                if narrow in enabled and wide not in enabled:
                    raise ValueError(narrow + ' enabled without corresponding ' + wide)
            if 'arm64-v8a' not in enabled:
                raise ValueError('This Android phone release must include arm64-v8a')
            return enabled
    raise ValueError('Android preset not found')


def inspect_bundle(path, expected=None):
    libs = collections.defaultdict(set)
    entries = 0
    with zipfile.ZipFile(path) as z:
        if 'BundleConfig.pb' not in z.namelist():
            raise ValueError('Not an Android App Bundle: missing BundleConfig.pb')
        for info in z.infolist():
            match = re.fullmatch(r'[^/]+/lib/([^/]+)/([^/]+\.so)', info.filename)
            if not match: continue
            abi, lib = match.groups()
            if abi not in ABIS: raise ValueError('Unknown native ABI: ' + abi)
            if lib in libs[abi]: raise ValueError('Duplicate native library for ' + abi + ': ' + lib)
            with z.open(info) as stream: header = stream.read(20)
            if len(header) < 20 or header[:4] != b'\x7fELF':
                raise ValueError('Native library has no valid ELF header: ' + info.filename)
            if header[5] not in (1, 2): raise ValueError('Invalid ELF byte order: ' + info.filename)
            machine = struct.unpack('<H' if header[5] == 1 else '>H', header[18:20])[0]
            if (header[4], machine) != ABIS[abi]:
                raise ValueError('Native ELF class/machine disagrees with ABI directory: ' + info.filename)
            libs[abi].add(lib)
            entries += 1
        actual = set(libs)
        if not actual: raise ValueError('Bundle contains no native libraries')
        if expected is not None and actual != set(expected):
            raise ValueError('Bundled ABIs differ from preset: expected ' + str(sorted(expected)) + ', got ' + str(sorted(actual)))
        if 'arm64-v8a' not in actual: raise ValueError('Bundle lacks ARM64 native code')
        for abi in actual:
            if 'libgodot_android.so' not in libs[abi]:
                raise ValueError('Godot runtime missing for ' + abi)
        for narrow, wide in PAIRS.items():
            if narrow in actual:
                missing = libs[narrow] - libs[wide]
                if missing:
                    raise ValueError('32-bit native code has no 64-bit counterpart: ' + narrow + ' -> ' + wide + ': ' + ', '.join(sorted(missing)))
    return {'bundle': str(path), 'architectures': sorted(libs),
            'native_libraries': {abi: sorted(names) for abi, names in sorted(libs.items())},
            'checked_ELF_headers': entries, 'ABI_pair_check': 'PASS',
            'google_play_submission_verified': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', nargs='?')
    parser.add_argument('--preset', default='export_presets.cfg')
    args = parser.parse_args()
    try:
        expected = android_preset(args.preset)
        result = inspect_bundle(args.bundle, expected) if args.bundle else {'preset_ABIs': sorted(expected), 'default_format': 'AAB', 'preset_check': 'PASS'}
        print(json.dumps(result, indent=2))
    except (ValueError, OSError, zipfile.BadZipFile) as error:
        print('ANDROID BUNDLE VALIDATION FAILED: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
