"""Synthetic regression projects/repos only; never inspect the owner's Xcode project.

AI-assisted port of Earshot by HellzYeahh and contributors (MIT).
"""
import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
TEAM_KEY = 'DEVELOPMENT_' + 'TEAM'
TEAM = 'TEST' + 'TEAM01'
PROFILE_KEY = 'PROVISIONING_' + 'PROFILE_SPECIFIER'


def load_module(name, filename):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


membership = load_module('earshot_membership_test_module', 'update-project-membership.py')
privacy = load_module('earshot_privacy_test_module', 'check-push-privacy.py')


def project(sources=(), resource_style='relative'):
    ident = membership.ident
    objects = {}
    files, builds = [], []
    for path in sources:
        file_id = ident('file:' + path)
        build_id = ident('build:Earshot:' + path)
        objects[file_id] = {'isa': 'PBXFileReference', 'path': path, 'sourceTree': 'SOURCE_ROOT'}
        objects[build_id] = {'isa': 'PBXBuildFile', 'fileRef': file_id}
        files.append(file_id); builds.append(build_id)
    resource = 'Earshot/Resources/LICENSE.txt'
    resource_id = ident('file:' + resource)
    objects[resource_id] = {'isa': 'PBXFileReference', 'path': resource, 'sourceTree': 'SOURCE_ROOT'}
    resource_build = ident('resource:' + (resource if resource_style == 'relative' else '/synthetic/old/ios/' + resource))
    objects[resource_build] = {'isa': 'PBXBuildFile', 'fileRef': resource_id}
    objects[ident('group:Earshot')] = {'isa': 'PBXGroup', 'children': files}
    objects[ident('group:resources')] = {'isa': 'PBXGroup', 'children': [resource_id]}
    objects[ident('sources:Earshot')] = {'isa': 'PBXSourcesBuildPhase', 'files': builds}
    objects[ident('resources:Earshot')] = {'isa': 'PBXResourcesBuildPhase', 'files': [resource_build]}
    objects[ident('config')] = {'isa': 'XCBuildConfiguration', 'name': 'Debug', 'buildSettings': {'MARKETING_VERSION': '1.0', 'CURRENT_PROJECT_VERSION': '1'}}
    objects[ident('target:Earshot')] = {'isa': 'PBXNativeTarget', 'name': 'Earshot', 'customAttribute': 'preserve'}
    objects[ident('project')] = {'isa': 'PBXProject', 'attributes': {'CustomLocal': 'preserve'}}
    return {'objects': objects, 'rootObject': ident('project')}


def parse_project(path):
    result = subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(path)], capture_output=True, check=True)
    return json.loads(result.stdout)


def synthetic_ios(directory):
    root = Path(directory) / 'ios'
    (root / 'scripts').mkdir(parents=True)
    for name in ('generate_project.py', 'update-project-membership.py'):
        shutil.copyfile(SCRIPTS / name, root / 'scripts' / name)
    for path in ('Earshot', 'EarshotTests', 'EarshotUITests', 'EarshotWidget', 'Shared', 'Earshot/Resources/Assets.xcassets', 'Earshot/Resources/Fonts'):
        (root / path).mkdir(parents=True, exist_ok=True)
    (root / 'Earshot/Example.swift').write_text('import Foundation\n')
    return root


class GeneratorProtectionTests(unittest.TestCase):
    def test_default_explicit_and_symlink_destinations_all_protect_local_signing(self):
        for destination in ('default', 'explicit', 'symlink'):
            for key in (TEAM_KEY, TEAM_KEY + '_ID', PROFILE_KEY):
                with self.subTest(destination=destination, field=key), tempfile.TemporaryDirectory() as directory:
                    root = synthetic_ios(directory)
                    local = root / 'Earshot.xcodeproj'
                    local.mkdir()
                    path = local / 'project.pbxproj'
                    original = json.dumps({'buildSettings': {key: TEAM}})
                    path.write_text(original)
                    args = [sys.executable, str(root / 'scripts/generate_project.py')]
                    if destination == 'explicit': args += ['--output-project', str(local)]
                    if destination == 'symlink':
                        alias = Path(directory) / 'project-alias'
                        alias.symlink_to(local, target_is_directory=True)
                        args += ['--output-project', str(alias)]
                    run = subprocess.run(args, capture_output=True, text=True)
                    self.assertEqual(run.returncode, 2)
                    self.assertNotIn(TEAM, run.stdout + run.stderr)
                    self.assertEqual(path.read_text(), original)

    def test_unquoted_assignment_personal_identity_and_empty_public_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            root = synthetic_ios(directory)
            local = root / 'Earshot.xcodeproj'
            local.mkdir(); path = local / 'project.pbxproj'
            for original in (TEAM_KEY + ' = ' + TEAM + ';', 'CODE_SIGN_IDENTITY = "Apple ' + 'Development: Synthetic Person";'):
                path.write_text(original)
                run = subprocess.run([sys.executable, str(root / 'scripts/generate_project.py')], capture_output=True)
                self.assertEqual(run.returncode, 2)
                self.assertEqual(path.read_text(), original)
            path.write_text(json.dumps({TEAM_KEY: '', PROFILE_KEY: ''}))
            run = subprocess.run([sys.executable, str(root / 'scripts/generate_project.py')], capture_output=True)
            self.assertEqual(run.returncode, 0)

    def test_alternate_output_cannot_overwrite_a_different_signed_project(self):
        with tempfile.TemporaryDirectory() as directory:
            root = synthetic_ios(directory)
            output = Path(directory) / 'OtherSignedProject.xcodeproj'
            output.mkdir(); path = output / 'project.pbxproj'
            original = json.dumps({TEAM_KEY: TEAM})
            path.write_text(original)
            run = subprocess.run([sys.executable, str(root / 'scripts/generate_project.py'), '--output-project', str(output)], capture_output=True)
            self.assertEqual(run.returncode, 2)
            self.assertEqual(path.read_text(), original)

    @unittest.skipUnless(sys.platform == 'darwin' and shutil.which('plutil'), 'macOS project parser required')
    def test_generated_resource_ids_and_entire_project_are_checkout_location_independent(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            projects = []
            for directory in (first, second):
                root = synthetic_ios(directory)
                output = root / 'build/Clean/Earshot.xcodeproj'
                run = subprocess.run([sys.executable, str(root / 'scripts/generate_project.py'), '--output-project', str(output)], capture_output=True)
                self.assertEqual(run.returncode, 0)
                projects.append(parse_project(output / 'project.pbxproj'))
            self.assertEqual(projects[0], projects[1])
            phase = projects[0]['objects'][membership.ident('resources:Earshot')]
            expected = membership.ident('resource:Earshot/Resources/LICENSE.txt')
            self.assertIn(expected, phase['files'])


class MembershipTests(unittest.TestCase):
    def test_removed_and_renamed_owned_sources_leave_no_stale_build_membership(self):
        existing = project(['Earshot/Keep.swift', 'Earshot/Removed.swift', 'Earshot/OldName.swift'])
        generated = project(['Earshot/Keep.swift', 'Earshot/NewName.swift'])
        result, _ = membership.reconcile(existing, generated)
        objects = result['objects']
        self.assertEqual(objects[membership.ident('sources:Earshot')]['files'], generated['objects'][membership.ident('sources:Earshot')]['files'])
        self.assertEqual(objects[membership.ident('group:Earshot')]['children'], generated['objects'][membership.ident('group:Earshot')]['children'])
        self.assertEqual(len(existing['objects'][membership.ident('sources:Earshot')]['files']), 3, 'Pure reconciliation must not mutate its input')

    def test_unknown_custom_source_group_and_resource_references_are_preserved(self):
        existing = project(['Earshot/Old.swift'])
        generated = project(['Earshot/New.swift'])
        objects = existing['objects']
        custom_file, custom_build, custom_group = [membership.ident('custom:' + name) for name in ('file', 'build', 'group')]
        objects[custom_file] = {'isa': 'PBXFileReference', 'path': '../Private/Custom.swift', 'sourceTree': 'SOURCE_ROOT'}
        objects[custom_build] = {'isa': 'PBXBuildFile', 'fileRef': custom_file, 'settings': {'COMPILER_FLAGS': '-DLOCAL'}}
        objects[custom_group] = {'isa': 'PBXGroup', 'children': [custom_file], 'name': 'Local'}
        objects[membership.ident('sources:Earshot')]['files'].append(custom_build)
        objects[membership.ident('group:Earshot')]['children'].append(custom_group)
        custom_resource = membership.ident('custom:resource')
        objects[custom_resource] = {'isa': 'PBXBuildFile', 'fileRef': custom_file, 'settings': {'ATTRIBUTES': ['CodeSignOnCopy']}}
        objects[membership.ident('resources:Earshot')]['files'].append(custom_resource)
        result, _ = membership.reconcile(existing, generated)
        self.assertIn(custom_build, result['objects'][membership.ident('sources:Earshot')]['files'])
        self.assertIn(custom_group, result['objects'][membership.ident('group:Earshot')]['children'])
        self.assertIn(custom_resource, result['objects'][membership.ident('resources:Earshot')]['files'])
        self.assertEqual(result['objects'][custom_build], objects[custom_build])

    def test_legacy_absolute_resource_ids_are_deduplicated_without_touching_custom_settings(self):
        existing = project(resource_style='legacy')
        generated = project()
        objects = existing['objects']; phase = membership.ident('resources:Earshot')
        ref = membership.ident('file:Earshot/Resources/LICENSE.txt')
        another = membership.ident('resource:/another/checkout/ios/Earshot/Resources/LICENSE.txt')
        objects[another] = {'isa': 'PBXBuildFile', 'fileRef': ref}
        objects[phase]['files'].append(another)
        result, _ = membership.reconcile(existing, generated)
        self.assertEqual(result['objects'][phase]['files'], generated['objects'][phase]['files'])
        again, added = membership.reconcile(result, generated)
        self.assertEqual(again, result)
        self.assertEqual(added, 0)

    def test_all_local_target_project_and_configuration_settings_survive_and_versions_are_opt_in(self):
        existing = project(); generated = project()
        config = membership.ident('config'); target = membership.ident('target:Earshot'); root = membership.ident('project')
        existing['objects'][config]['buildSettings'].update({TEAM_KEY: TEAM, PROFILE_KEY: 'Synthetic profile', 'PRODUCT_BUNDLE_IDENTIFIER': 'local.example', 'OTHER_SWIFT_FLAGS': ['-DLOCAL']})
        existing['objects'][root]['attributes']['Development' + 'Team'] = TEAM
        generated['objects'][config]['buildSettings'].update({'MARKETING_VERSION': '2.0', 'CURRENT_PROJECT_VERSION': '5'})
        result, _ = membership.reconcile(existing, generated)
        for key in (config, target, root): self.assertEqual(result['objects'][key], existing['objects'][key])
        bumped, _ = membership.reconcile(existing, generated, sync_public_versions=True)
        expected = copy.deepcopy(existing['objects'][config])
        expected['buildSettings'].update({'MARKETING_VERSION': '2.0', 'CURRENT_PROJECT_VERSION': '5'})
        self.assertEqual(bumped['objects'][config], expected)
        for key in (target, root): self.assertEqual(bumped['objects'][key], existing['objects'][key])

    def test_unexpected_new_target_refuses_instead_of_replacing_local_settings(self):
        existing = project(); generated = project()
        generated['objects'][membership.ident('new:target')] = {'isa': 'PBXNativeTarget', 'name': 'Unexpected'}
        original = copy.deepcopy(existing)
        with self.assertRaises(ValueError): membership.reconcile(existing, generated)
        self.assertEqual(existing, original)

    @unittest.skipUnless(sys.platform == 'darwin' and shutil.which('plutil'), 'macOS project parser required')
    def test_apply_only_updates_synthetic_membership_and_preserves_private_fields_and_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = synthetic_ios(directory)
            generator = root / 'scripts/generate_project.py'
            local = root / 'Earshot.xcodeproj'
            subprocess.run([sys.executable, str(generator)], capture_output=True, check=True)
            path = local / 'project.pbxproj'
            data = parse_project(path)
            for value in data['objects'].values():
                if value['isa'] == 'XCBuildConfiguration': value['buildSettings'][TEAM_KEY] = TEAM
            path.write_text(json.dumps(data)); path.chmod(0o600)
            (root / 'Earshot/Example.swift').unlink()
            (root / 'Earshot/Renamed.swift').write_text('import Foundation\n')
            run = subprocess.run([sys.executable, str(root / 'scripts/update-project-membership.py'), '--apply'], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertNotIn(TEAM, run.stdout + run.stderr)
            result = parse_project(path)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertFalse(list((root / 'build').glob('PrivateMembership-*')))
            for key, value in data['objects'].items():
                if value['isa'] in membership.PROTECTED: self.assertEqual(result['objects'][key], value)
            files = result['objects'][membership.ident('sources:Earshot')]['files']
            self.assertNotIn(membership.ident('build:Earshot:Earshot/Example.swift'), files)
            self.assertIn(membership.ident('build:Earshot:Earshot/Renamed.swift'), files)


class IndexedPrivacyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True, capture_output=True)

    def stage(self, path, value, force=False):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(value if isinstance(value, bytes) else value.encode())
        subprocess.run(['git', 'add'] + (['-f'] if force else []) + ['--', path], cwd=self.root, check=True, capture_output=True)

    def test_forced_staged_binary_keystores_and_private_config_names_are_blocked(self):
        paths = ['signing.jks', 'signing.keystore', 'account.p8', '.env.private', '.netrc', 'ios/Signing.local.xcconfig', 'Project.xcodeproj/xcuserdata/user.xcuserdatad/Settings.plist']
        (self.root / '.gitignore').write_text('\n'.join(paths) + '\n')
        for path in paths: self.stage(path, b'\x00synthetic binary\x00', force=True)
        findings = privacy.check_index(self.root)
        self.assertEqual({path for path, _ in findings}, set(paths))

    def test_staged_team_aliases_quoted_json_and_profiles_block_without_values_in_output(self):
        values = {
            'settings.xcconfig': TEAM_KEY + ' = ' + TEAM + ';',
            'settings.json': json.dumps({TEAM_KEY + '_ID': TEAM}),
            'camel.json': json.dumps({'Development' + 'Team': TEAM}),
            'profile.json': json.dumps({PROFILE_KEY: 'SYNTHETIC_PRIVATE_PROFILE'}),
        }
        for path, value in values.items(): self.stage(path, value)
        findings = privacy.check_index(self.root)
        self.assertEqual({path for path, _ in findings}, set(values))
        run = subprocess.run([sys.executable, str(SCRIPTS / 'check-push-privacy.py')], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(run.returncode, 1)
        self.assertNotIn(TEAM, run.stdout + run.stderr)
        self.assertNotIn('SYNTHETIC_PRIVATE_PROFILE', run.stdout + run.stderr)

    def test_public_tool_and_regression_sources_do_not_self_report_fixture_placeholders(self):
        for filename in ('generate_project.py', 'update-project-membership.py', 'check-push-privacy.py'):
            self.stage('scripts/' + filename, (SCRIPTS / filename).read_bytes())
        self.stage('tests/test_project_privacy.py', Path(__file__).read_bytes())
        self.assertEqual(privacy.check_index(self.root), set())

    def test_private_key_content_is_blocked_even_under_an_innocent_filename(self):
        private = '-----BEGIN ' + 'PRIVATE KEY-----\nsynthetic\n-----END ' + 'PRIVATE KEY-----\n'
        self.stage('ordinary.txt', private)
        self.assertIn(('ordinary.txt', 'private key'), privacy.check_index(self.root))

    def test_unstaged_signing_is_ignored_and_empty_public_assignments_pass(self):
        path = 'Project.xcodeproj/project.pbxproj'
        clean = json.dumps({TEAM_KEY: '', PROFILE_KEY: '', 'PRODUCT_BUNDLE_IDENTIFIER': 'dev.earshot.ios'})
        self.stage(path, clean)
        (self.root / path).write_text(json.dumps({TEAM_KEY: TEAM}))
        self.assertEqual(privacy.check_index(self.root), set())
        run = subprocess.run([sys.executable, str(SCRIPTS / 'check-push-privacy.py')], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(run.returncode, 0)
        self.assertNotIn(TEAM, run.stdout + run.stderr)


if __name__ == '__main__':
    unittest.main()
