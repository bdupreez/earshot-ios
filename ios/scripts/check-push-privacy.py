#!/usr/bin/env python3
"""Check the Git index before a fork push, without printing credential values.

AI-assisted port of Earshot by HellzYeahh and contributors (MIT).
This checks indexed files, so local, unstaged Xcode signing edits stay on the Mac.
It is a targeted guard, not a guarantee that arbitrary secrets can be recognized.
"""
import re
import subprocess
import sys
from pathlib import PurePosixPath

repository_root = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=repository_root)


paths = git("ls-files", "-z").decode().split("\0")
findings = set()
private_suffixes = {".p8", ".p12", ".pfx", ".pem", ".key", ".cer", ".mobileprovision", ".provisionprofile", ".xcuserstate", ".xcsettings"}
for path in filter(None, paths):
    name = PurePosixPath(path).name
    if (PurePosixPath(path).suffix.lower() in private_suffixes or "xcuserdata" in PurePosixPath(path).parts
            or name in {".env", "ExportOptions.plist"} or name.startswith(".env.")
            or name.endswith(".local.xcconfig") or re.fullmatch(r"Signing.*\.xcconfig", name)):
        findings.add((path, "local configuration or signing material"))

# git grep reads the index, excludes binary data and emits paths only. Never
# echo matched lines: a failed privacy check must not itself disclose a secret.
patterns = {
    "developer team identifier": r'(DEVELOPMENT_TEAM|DevelopmentTeam|developmentTeam)[[:space:]]*[=:][[:space:]]*"?[A-Z0-9]{10}("[[:space:]]*;?|[[:space:]]*;|[[:space:]]*$)',
    "provisioning profile assignment": r'PROVISIONING_PROFILE(_SPECIFIER)?[[:space:]]*=[[:space:]]*"?[^";[:space:]][^;]*;',
    "personal signing identity": r'Apple (Development|Distribution):|iPhone (Developer|Distribution):',
    "private key": r'^-----BEGIN ([A-Z0-9]+ )?PRIVATE KEY-----',
    "GitHub token": r'gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}',
    "AWS access key": r'(AKIA|ASIA)[A-Z0-9]{16}',
    "OpenAI API key": r'sk-(proj-|svcacct-)?[A-Za-z0-9_-]{40,}',
}
for category, pattern in patterns.items():
    result = subprocess.run(["git", "grep", "--cached", "-I", "-l", "-z", "-E", "-e", pattern, "--"], cwd=repository_root, capture_output=True)
    if result.returncode not in (0, 1):
        print("Privacy check could not inspect the Git index.", file=sys.stderr)
        sys.exit(2)
    for path in filter(None, result.stdout.decode().split("\0")):
        findings.add((path, category))

if findings:
    for path, category in sorted(findings):
        print(f"BLOCKED: {path}: {category}", file=sys.stderr)
    sys.exit(1)
print("Indexed-file privacy check passed: no targeted signing/account/key findings.")
