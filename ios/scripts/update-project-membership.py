#!/usr/bin/env python3
"""Regenerate source/resource membership while preserving every local build setting.

The clean generated project lives under ignored build/ for review/indexing. The
local project keeps all existing objects/settings; only generated membership lists
and new file/build references are reconciled. This script never stages anything.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sync-public-versions', action='store_true', help='Also copy only public marketing/build version values from the clean project')
parser.add_argument('--apply', action='store_true', help='Apply membership changes to the local project, preserving settings')
args = parser.parse_args()
clean = ROOT / 'build/GeneratedProject/Earshot.xcodeproj'
subprocess.run([sys.executable, str(ROOT / 'scripts/generate_project.py'), '--output-project', str(clean)], check=True)
local = ROOT / 'Earshot.xcodeproj/project.pbxproj'
def read(path):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))
existing, generated = read(local), read(clean / 'project.pbxproj')
# Never replace a configuration or a project/target attribute: these may hold
# device signing settings that the owner deliberately keeps out of source control.
objects = existing['objects']
settings = {key: value for key, value in objects.items() if value['isa'] in ('XCBuildConfiguration', 'PBXProject', 'PBXNativeTarget')}
# Opt-in version bumps are public project changes, separate from personal signing.
if args.sync_public_versions:
    for key, value in objects.items():
        if value['isa'] == 'XCBuildConfiguration' and key in generated['objects']:
            for field in ('MARKETING_VERSION', 'CURRENT_PROJECT_VERSION'):
                public = generated['objects'][key].get('buildSettings', {}).get(field)
                if public is not None: value['buildSettings'][field] = public
original_settings = json.dumps(settings, sort_keys=True)
added = 0
for key, value in generated['objects'].items():
    if key not in objects:
        if value['isa'] not in ('PBXFileReference', 'PBXBuildFile', 'PBXGroup'):
            raise SystemExit('Unexpected new target/configuration. Reconcile manually without replacing local settings.')
        objects[key] = value; added += 1
    elif value['isa'] in ('PBXGroup', 'PBXSourcesBuildPhase', 'PBXResourcesBuildPhase'):
        field = 'children' if value['isa'] == 'PBXGroup' else 'files'
        # Keep unknown local references. Only new generated entries are inserted.
        objects[key][field] = value[field] + [item for item in objects[key].get(field, []) if item not in value[field]]
assert json.dumps({key: objects[key] for key in settings}, sort_keys=True) == original_settings

def emit(value):
    if isinstance(value, dict): return '{ ' + ' '.join(f'{key} = {emit(item)};' for key, item in value.items()) + ' }'
    if isinstance(value, list): return '( ' + ', '.join(emit(item) for item in value) + ', )' if value else '()'
    return json.dumps(str(value))
if args.apply:
    candidate = ROOT / 'build/PrivateMembershipCandidate.pbxproj'
    candidate.write_text('// !$*UTF8*$!\n' + emit(existing) + '\n')
    reread = read(candidate)
    assert json.dumps({key: reread['objects'][key] for key in settings}, sort_keys=True) == original_settings
    candidate.replace(local)
print(f'{"Applied" if args.apply else "Previewed"} {added} new references; local signing and all other target/project settings preserved. Clean project: {clean}')
