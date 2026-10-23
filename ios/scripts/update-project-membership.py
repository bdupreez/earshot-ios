#!/usr/bin/env python3
"""Reconcile generated membership, preserving local project/target/configuration settings.

AI-assisted port of Earshot by HellzYeahh and contributors (MIT). Clean output
stays under ignored build/. No file is staged and no Git command is executed.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TARGETS = ('Earshot', 'EarshotTests', 'EarshotUITests', 'EarshotWidget')
PROTECTED = ('XCBuildConfiguration', 'PBXProject', 'PBXNativeTarget')
PUBLIC_VERSIONS = ('MARKETING_VERSION', 'CURRENT_PROJECT_VERSION')


def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def read(path):
    result = subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(path)], capture_output=True)
    if result.returncode:
        raise SystemExit('Project parsing failed; the local project was not changed.')
    return json.loads(result.stdout)


def emit(value):
    if isinstance(value, dict):
        return '{ ' + ' '.join(f'{key} = {emit(item)};' for key, item in value.items()) + ' }'
    if isinstance(value, list):
        return '( ' + ', '.join(emit(item) for item in value) + ', )' if value else '()'
    return json.dumps(str(value))


def reconcile(existing, generated, sync_public_versions=False):
    """Pure reconciliation; unknown custom references and their objects survive.

    A source entry is ours only when both its file and target-specific build IDs
    match the deterministic generator. Legacy resource IDs depended on an absolute
    checkout path: canonicalise redundant plain build refs to a known generated
    resource, while preserving custom build settings and unrelated resource refs.
    Unused old objects remain so a custom group can still refer to one safely.
    """
    result = copy.deepcopy(existing)
    objects, clean = result['objects'], generated['objects']
    if sync_public_versions:
        for key, value in objects.items():
            if value['isa'] == 'XCBuildConfiguration' and key in clean:
                for field in PUBLIC_VERSIONS:
                    public = clean[key].get('buildSettings', {}).get(field)
                    if public is not None:
                        value['buildSettings'][field] = public
    protected = copy.deepcopy({key: value for key, value in objects.items() if value['isa'] in PROTECTED})
    source_phases = {ident('sources:' + target): target for target in TARGETS}
    resource_phases = {ident('resources:' + target) for target in TARGETS}
    generated_files = {key for key, value in clean.items() if value['isa'] == 'PBXFileReference'}
    generated_resources = {
        clean[build]['fileRef']
        for key in resource_phases if key in clean
        for build in clean[key].get('files', [])
    }

    def owned_path(file_id):
        value = objects.get(file_id, {})
        path = value.get('path')
        if (value.get('isa') == 'PBXFileReference' and isinstance(path, str)
                and value.get('sourceTree') == 'SOURCE_ROOT' and ident('file:' + path) == file_id):
            return path
        return None

    def obsolete_source_file(file_id):
        path = owned_path(file_id)
        return (path is not None and path.endswith('.swift')
                and path.split('/')[0] in (*TARGETS, 'Shared') and file_id not in generated_files)

    def keep_old_member(phase_id, member):
        value = objects.get(member, {})
        if phase_id in source_phases and value.get('isa') == 'PBXBuildFile':
            path = owned_path(value.get('fileRef'))
            if path and member == ident('build:' + source_phases[phase_id] + ':' + path):
                return False  # Removed/renamed/moved out of this target by the generator.
        if (phase_id in resource_phases and value.get('isa') == 'PBXBuildFile'
                and value.get('fileRef') in generated_resources
                and set(value) == {'isa', 'fileRef'}):
            return False  # Identical resource, including a legacy absolute-path ID.
        return not obsolete_source_file(member)

    added = 0
    for key, value in clean.items():
        if key not in objects:
            if value['isa'] not in ('PBXFileReference', 'PBXBuildFile', 'PBXGroup'):
                raise ValueError('Unexpected new target/configuration; reconcile manually.')
            objects[key] = copy.deepcopy(value)
            added += 1
        elif value['isa'] in ('PBXGroup', 'PBXSourcesBuildPhase', 'PBXResourcesBuildPhase'):
            field = 'children' if value['isa'] == 'PBXGroup' else 'files'
            merged = list(value[field])
            for member in objects[key].get(field, []):
                if member not in merged and keep_old_member(key, member):
                    merged.append(member)
            objects[key][field] = merged
    if {key: objects[key] for key in protected} != protected:
        raise ValueError('Local project settings changed unexpectedly.')
    return result, added


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sync-public-versions', action='store_true', help='Copy only public marketing/build version values from the clean project')
    parser.add_argument('--apply', action='store_true', help='Apply reconciled membership while preserving local settings')
    args = parser.parse_args(argv)
    clean = ROOT / 'build/GeneratedProject/Earshot.xcodeproj'
    subprocess.run([sys.executable, str(ROOT / 'scripts/generate_project.py'), '--output-project', str(clean)], check=True)
    local = ROOT / 'Earshot.xcodeproj/project.pbxproj'
    existing, generated = read(local), read(clean / 'project.pbxproj')
    try:
        result, added = reconcile(existing, generated, args.sync_public_versions)
    except (KeyError, TypeError, ValueError):
        raise SystemExit('Project reconciliation failed; the local project was not changed.') from None
    if args.apply:
        candidate = None
        try:
            with tempfile.NamedTemporaryFile(dir=ROOT / 'build', prefix='PrivateMembership-', suffix='.pbxproj', mode='w', delete=False) as stream:
                candidate = Path(stream.name)
                stream.write('// !$*UTF8*$!\n' + emit(result) + '\n')
            candidate.chmod(stat.S_IMODE(local.stat().st_mode))
            reread = read(candidate)
            if reread != result:
                raise SystemExit('Project validation failed; the local project was not changed.')
            candidate.replace(local)
        finally:
            if candidate is not None:
                candidate.unlink(missing_ok=True)
    print(f'{"Applied" if args.apply else "Previewed"} {added} new references; local signing and target/project settings preserved. Clean project: {clean}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
