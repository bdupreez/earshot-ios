#!/usr/bin/env python3
"""Check only the Git index before a fork push, without printing credential values.

AI-assisted port of Earshot by HellzYeahh and contributors (MIT).
Local, unstaged Xcode signing edits stay on the Mac. This is a targeted guard,
not a guarantee that arbitrary secrets can be recognized. It never pushes.
"""
import re
import subprocess
import sys
from pathlib import PurePosixPath

PRIVATE_SUFFIXES = {'.p8', '.p12', '.pfx', '.pem', '.key', '.cer', '.jks', '.keystore',
                    '.mobileprovision', '.provisionprofile', '.xcuserstate', '.xcsettings'}
PRIVATE_NAMES = {'.env', 'exportoptions.plist', '.netrc', '.npmrc', '.pypirc', '.git-credentials'}
# OpenStep, xcconfig and quoted JSON keys all occur in developer configuration.
# Match a nonempty quoted or unquoted value, not just the current account's ID shape.
KEY_END = r'''["']?[[:space:]]*[=:][[:space:]]*("[^"[:space:]][^"]*"|'[^'[:space:]][^']*'|[^"'[:space:];,})][^;,}]*)'''
PATTERNS = {
    'developer team identifier': r'''(^|[^[:alnum:]_])["']?(DEVELOPMENT_TEAM(_ID)?|[Dd]evelopment[Tt]eam)(\[[^]]*\])?''' + KEY_END,
    'provisioning profile assignment': r'''(^|[^[:alnum:]_])["']?PROVISIONING_PROFILE(_SPECIFIER)?(\[[^]]*\])?''' + KEY_END,
    'personal signing identity': r'Apple (Development|Distribution):|iPhone (Developer|Distribution):',
    'private key': r'^-----BEGIN ([A-Z0-9]+ )?PRIVATE KEY-----',
    'GitHub token': r'gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}',
    'AWS access key': r'(AKIA|ASIA)[A-Z0-9]{16}',
    'OpenAI API key': r'sk-(proj-|svcacct-)?[A-Za-z0-9_-]{40,}',
}


def private_filename(path):
    posix = PurePosixPath(path)
    name = posix.name.lower()
    return (posix.suffix.lower() in PRIVATE_SUFFIXES or 'xcuserdata' in posix.parts
            or name in PRIVATE_NAMES or name.startswith('.env.')
            or name.endswith('.local.xcconfig') or re.fullmatch(r'signing.*\.xcconfig', name) is not None)


def check_index(repository_root):
    result = subprocess.run(['git', 'ls-files', '-z'], cwd=repository_root, capture_output=True)
    if result.returncode:
        raise RuntimeError('The Git index could not be inspected.')
    findings = {(path, 'local configuration or signing material')
                for path in result.stdout.decode().split('\0') if path and private_filename(path)}
    for category, pattern in PATTERNS.items():
        result = subprocess.run(['git', 'grep', '--cached', '-I', '-l', '-z', '-E', '-e', pattern, '--'],
                                cwd=repository_root, capture_output=True)
        if result.returncode not in (0, 1):
            raise RuntimeError('The Git index could not be inspected.')
        findings.update((path, category) for path in result.stdout.decode().split('\0') if path)
    return findings


def main():
    result = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True)
    if result.returncode:
        print('Privacy check could not locate the Git index.', file=sys.stderr)
        return 2
    try:
        findings = check_index(result.stdout.strip())
    except (OSError, RuntimeError, UnicodeError):
        print('Privacy check could not inspect the Git index.', file=sys.stderr)
        return 2
    if findings:
        for path, category in sorted(findings):
            # repr strips terminal control effects from a malicious path, while
            # matched file contents and account/credential values remain hidden.
            print(f'BLOCKED: {path!r}: {category}', file=sys.stderr)
        return 1
    print('Indexed-file privacy check passed: no targeted signing/account/key findings.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
