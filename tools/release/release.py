#!/usr/bin/env python3
"""Local Developer ID release pipeline. Requires Python 3.9+ and macOS."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
VERSION = re.compile(r'^version: (\d+)\.(\d+)\.(\d+)\+(\d+)$', re.MULTILINE)
REPO = 'sinri/TerminalUseApp'
APP_NAME = 'Terminal Use APP.app'


def run(*args, capture=False, cwd=None):
    result = subprocess.run(args, cwd=cwd or ROOT, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def version(root=ROOT):
    match = VERSION.search((root / 'pubspec.yaml').read_text())
    if not match:
        raise ValueError('Expected version: MAJOR.MINOR.PATCH+BUILD in pubspec.yaml')
    return tuple(map(int, match.groups()))


def version_text(value):
    return '%d.%d.%d+%d' % value


def bump(part, root=ROOT):
    path = root / 'pubspec.yaml'
    old = version(root)
    major, minor, patch, build = old
    if part == 'major':
        major, minor, patch = major + 1, 0, 0
    elif part == 'minor':
        minor, patch = minor + 1, 0
    elif part == 'patch':
        patch += 1
    text = version_text((major, minor, patch, build + 1))
    path.write_text(VERSION.sub('version: ' + text, path.read_text(), count=1))
    print(f'{version_text(old)} -> {text}')


def tag_name():
    return 'v' + version_text(version())


def require_tag():
    if run('git', 'status', '--porcelain', capture=True):
        raise ValueError('Commit all changes before building a release.')
    tag = tag_name()
    head = run('git', 'rev-parse', 'HEAD', capture=True)
    target = run('git', 'rev-list', '-n', '1', tag, capture=True)
    if target != head:
        raise ValueError(f'{tag} must point to HEAD.')
    return tag, head


def credentials():
    identity = os.environ.get('SIGN_IDENTITY', '')
    profile = os.environ.get('NOTARY_PROFILE', '')
    if not identity.startswith('Developer ID Application:') or not profile:
        raise ValueError('Set SIGN_IDENTITY="Developer ID Application: … (TEAMID)" and NOTARY_PROFILE.')
    identities = run('security', 'find-identity', '-v', '-p', 'codesigning', capture=True)
    if f'"{identity}"' not in identities:
        raise ValueError('Signing identity/private key not available in the keychain.')
    return identity, profile


def doctor():
    if sys.platform != 'darwin':
        raise ValueError('Release packaging requires macOS.')
    for command in ['flutter', 'xcodebuild', 'xcrun', 'codesign', 'security', 'hdiutil', 'ditto', 'gh']:
        if not shutil.which(command):
            raise ValueError(f'Missing command: {command}')
    run('xcrun', '--find', 'notarytool')
    credentials()
    run('xcrun', 'notarytool', 'history', '--keychain-profile', os.environ['NOTARY_PROFILE'])
    run('gh', 'auth', 'status')
    print('Release prerequisites ready.')


def notarize(path, profile, output):
    result = run('xcrun', 'notarytool', 'submit', str(path), '--keychain-profile', profile,
                 '--wait', '--output-format', 'json', capture=True)
    output.write_text(result + '\n')
    response = json.loads(result)
    if response.get('status') != 'Accepted':
        raise ValueError(f'Notarization failed; submission {response.get("id")}. See {output}; use notarytool log.')


def is_macho(path):
    if path.is_symlink() or not path.is_file():
        return False
    with path.open('rb') as stream:
        return stream.read(4) in [b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe',
                                  b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe',
                                  b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca']


def sign_app(app, identity):
    def sign(path, entitlements=False):
        args = ['codesign', '--force', '--timestamp', '--options', 'runtime', '--sign', identity]
        if entitlements:
            args += ['--entitlements', str(ROOT / 'macos/Runner/Release.entitlements')]
        run(*args, str(path))
    # Sign every native binary, then enclosing bundles from the inside out.
    # Do not use --deep to sign: it can apply inappropriate entitlements to children.
    for path in sorted(app.rglob('*')):
        if is_macho(path):
            sign(path)
    bundles = [p for p in app.rglob('*') if not p.is_symlink() and
               p.suffix in ('.framework', '.app', '.xpc') and p.is_dir()]
    for path in sorted(bundles, key=lambda p: len(p.parts), reverse=True):
        sign(path)
    sign(app, entitlements=True)
    run('codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app))


def build():
    doctor()
    tag, commit = require_tag()
    arch = platform.machine()
    if arch not in ('arm64', 'x86_64'):
        raise ValueError(f'Unsupported architecture: {arch}')
    identity, profile = credentials()
    destination = ROOT / 'dist' / tag / arch
    destination.mkdir(parents=True, exist_ok=False)
    run('flutter', 'pub', 'get', '--enforce-lockfile')
    run('flutter', 'analyze', '--no-pub')
    run('flutter', 'test', '--no-pub')
    run('flutter', 'build', 'macos', '--release', '--config-only', '--no-pub')
    run('xcodebuild', '-workspace', 'macos/Runner.xcworkspace', '-scheme', 'Runner',
        '-configuration', 'Release', '-destination', f'platform=macOS,arch={arch}',
        '-derivedDataPath', 'build/macos', '-quiet', f'ARCHS={arch}', 'ONLY_ACTIVE_ARCH=YES',
        'CODE_SIGNING_ALLOWED=NO', 'ENABLE_HARDENED_RUNTIME=YES', 'build')
    stage = destination / 'staging'
    stage.mkdir()
    app = stage / APP_NAME
    run('ditto', str(ROOT / 'build/macos/Build/Products/Release/terminal_use_app.app'), str(app))
    info = run('plutil', '-extract', 'CFBundleShortVersionString', 'raw', str(app / 'Contents/Info.plist'), capture=True)
    number = run('plutil', '-extract', 'CFBundleVersion', 'raw', str(app / 'Contents/Info.plist'), capture=True)
    if f'{info}+{number}' != version_text(version()):
        raise ValueError('Built app version differs from pubspec.yaml.')
    run('lipo', '-verify_arch', arch, str(app / 'Contents/MacOS/terminal_use_app'))
    sign_app(app, identity)
    submission = destination / 'app-notarization.zip'
    run('ditto', '-c', '-k', '--keepParent', str(app), str(submission))
    notarize(submission, profile, destination / 'app-notary.json')
    run('xcrun', 'stapler', 'staple', str(app))
    run('xcrun', 'stapler', 'validate', str(app))
    run('spctl', '--assess', '--type', 'execute', '--verbose=2', str(app))
    (stage / 'Applications').symlink_to('/Applications')
    shutil.copy2(ROOT / 'LICENSE', stage / 'LICENSE.txt')
    (stage / '安装说明.txt').write_text('将 Terminal Use APP 拖入 Applications 后启动。\n需要 macOS 12 或更高版本。\n' +
                                      f'架构：{arch}\n项目：https://github.com/{REPO}\n' +
                                      '第三方许可证位于 App 的“关于”窗口。SSH 和 Python MCP 功能需要系统提供相应命令。\n')
    stem = f'TerminalUseAPP-{tag}-macos-{arch}'
    dmg = destination / (stem + '.dmg')
    run('hdiutil', 'create', '-volname', 'Terminal Use APP', '-srcfolder', str(stage),
        '-format', 'UDZO', str(dmg))
    run('codesign', '--timestamp', '--sign', identity, str(dmg))
    notarize(dmg, profile, destination / 'dmg-notary.json')
    run('xcrun', 'stapler', 'staple', str(dmg))
    run('xcrun', 'stapler', 'validate', str(dmg))
    run('spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', str(dmg))
    source = destination / (stem + '-source.tar.gz')
    run('git', 'archive', '--format=tar.gz', f'--prefix=TerminalUseApp-{tag}/', '-o', str(source), tag)
    manifest = destination / (stem + '-manifest.json')
    manifest.write_text(json.dumps(dict(version=version_text(version()), tag=tag, commit=commit,
                                       architecture=arch, identity=identity, repository=REPO), indent=2) + '\n')
    artifacts = [dmg, source, manifest]
    checksum = destination / (stem + '-SHA256SUMS.txt')
    checksum.write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in artifacts))
    require_tag()
    # A receipt only exists after every signing/notarization/assessment gate passes.
    (destination / 'release.json').write_text(json.dumps(dict(tag=tag, commit=commit,
        files=[p.name for p in artifacts + [checksum]]), indent=2) + '\n')
    submission.unlink()
    print(f'Release candidate ready: {destination}')


def publish(directory):
    tag, commit = require_tag()
    directory = Path(directory).resolve()
    receipt = json.loads((directory / 'release.json').read_text())
    if (receipt['tag'], receipt['commit']) != (tag, commit):
        raise ValueError('Release receipt does not match current tag/commit.')
    files = [directory / name for name in receipt['files']]
    checksums = next(p for p in files if p.name.endswith('-SHA256SUMS.txt'))
    for line in checksums.read_text().splitlines():
        digest, name = line.split('  ', 1)
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != digest:
            raise ValueError(f'Checksum mismatch: {name}')
    run('git', 'push', 'origin', f'refs/tags/{tag}')
    run('gh', 'release', 'create', tag, '--repo', REPO, '--verify-tag', '--draft',
        '--title', f'Terminal Use APP {tag}', '--generate-notes', *map(str, files))
    print('Draft created. Complete the installation smoke test before publishing it on GitHub.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest='command', required=True)
    subs.add_parser('version')
    b = subs.add_parser('bump')
    b.add_argument('part', choices=['major', 'minor', 'patch', 'build'])
    subs.add_parser('doctor')
    subs.add_parser('build')
    p = subs.add_parser('publish')
    p.add_argument('directory')
    args = parser.parse_args()
    try:
        if args.command == 'version':
            print(version_text(version()))
        elif args.command == 'bump':
            bump(args.part)
        elif args.command == 'doctor':
            doctor()
        elif args.command == 'build':
            build()
        else:
            publish(args.directory)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Release stopped: {error}\n')


if __name__ == '__main__':
    main()
