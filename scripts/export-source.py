#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 1anzii

"""Export reviewed source inputs, never the whole development directory."""
from pathlib import Path
import hashlib
import json
import plistlib
import re
import shutil
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
VERSION = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())['CFBundleShortVersionString']
if not re.fullmatch(r'\d+\.\d+\.\d+', VERSION):
    raise SystemExit('Invalid release version')

FILES = [
    '.gitignore', 'README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'CHANGELOG.md',
    'CONTRIBUTING.md', 'PUBLISHING.md', 'package.json', 'package-lock.json',
    '.github/ISSUE_TEMPLATE/bug_report.md',
    'docs/DEVELOPMENT.md', 'docs/VALIDATION.md',
    'docs/images/slowfast-overview.png', 'docs/images/connections.png', 'docs/images/slowfast-icon.png',
    'Resources/Info.plist', 'Resources/entitlements.plist', 'Resources/video.js',
    'Resources/ConnectionTest.html', 'Resources/connection-test.mp4',
    'Resources/使用说明.html', 'Resources/安装说明.txt',
    'Resources/Fonts/Michroma-Regular.ttf', 'Resources/Fonts/OFL.txt', 'Resources/Fonts/SOURCE.txt',
    'Resources/Textures/BrushedAluminum-v2.png', 'Resources/Textures/BrushedAluminum-v2-prompt.txt',
    'Resources/Textures/SOURCE.txt',
    'BrowserExtension/README.md', 'BrowserExtension/manifest.json',
    'BrowserExtension/background.js', 'BrowserExtension/popup.js',
    'BrowserExtension/popup.html', 'BrowserExtension/popup.css',
    'Tests/CoreTests.swift', 'Tests/DisplayRenderingTests.swift', 'Tests/ReelRenderingTests.swift',
    'Tests/VisualPreview.swift', 'Tests/ManualTest.html', 'Tests/browser.cjs', 'Tests/extension.cjs', 'Tests/protocols.py',
    'scripts/build.sh', 'scripts/package.sh', 'scripts/cassette-icon.swift', 'scripts/preview.sh',
    'scripts/test.sh', 'scripts/test-display.sh', 'scripts/test-reels.sh', 'scripts/export-source.py'
]
FILES += [str(p.relative_to(ROOT)) for p in sorted((ROOT / 'Sources').glob('*.swift'))]
assert len(FILES) == len(set(FILES)), 'Duplicate allowlist entries'
assert len([f for f in FILES if f.startswith('Sources/')]) >= 15, 'Incomplete application source'

private_paths = re.compile('/' + r'Users/[^/\s]+|/' + r'home/[^/\s]+|/' + r'(?:private/)?var/folders/')
credentials = re.compile(r'gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|-----BEGIN [A-Z ]*PRIVATE KEY-----')
binary_types = {'.png', '.ttf', '.mp4'}
for relative in FILES:
    source = ROOT / relative
    if not source.is_file() or any(p.is_symlink() for p in [source, *source.parents] if p != ROOT.parent):
        raise SystemExit(f'Missing or linked input: {relative}')
    if source.suffix not in binary_types:
        content = source.read_text(encoding='utf-8')
        if private_paths.search(content) or credentials.search(content):
            raise SystemExit(f'Private path or credential pattern in {relative}; no content printed')

dist = ROOT / 'dist'
if dist.is_symlink():
    raise SystemExit('dist must not be a symlink')
dist.mkdir(exist_ok=True)
target = dist / f'open-source-{VERSION}'
archive_path = dist / f'SlowFast-{VERSION}-source.zip'
if target.exists() or archive_path.exists():
    raise SystemExit('Export already exists; choose a new version or back up previous outputs first')

with tempfile.TemporaryDirectory(prefix='.source-export-', dir=dist) as temporary:
    staged = Path(temporary) / 'SlowFast'
    for relative in FILES:
        destination = staged / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, destination)
        destination.chmod(0o755 if relative.startswith('scripts/') and destination.suffix in {'.sh', '.py'} else 0o644)
    manifest = ''.join(hashlib.sha256((staged / name).read_bytes()).hexdigest() + '  ' + name + '\n' for name in sorted(FILES))
    (staged / 'SOURCE-MANIFEST.sha256').write_text(manifest, encoding='utf-8')
    for doc in staged.rglob('*.md'):
        text = doc.read_text(encoding='utf-8')
        links = re.findall(r'\]\(([^)]+)\)', text) + re.findall(r'<img\s+[^>]*src="([^"]+)"', text)
        for link in links:
            if link.startswith(('http:', 'https:', '#', 'mailto:')):
                continue
            local = (doc.parent / link.split('#')[0]).resolve()
            if not local.is_relative_to(staged.resolve()) or not local.exists():
                raise SystemExit(f'Broken local link in {doc.relative_to(staged)}: {link}')
    with zipfile.ZipFile(archive_path, 'x', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for source in sorted(staged.rglob('*')):
            if source.is_file():
                archive.write(source, source.relative_to(staged.parent).as_posix())
    target.mkdir()
    shutil.move(str(staged), str(target / 'SlowFast'))
print(json.dumps({'version': VERSION, 'source_files': len(FILES), 'directory': str(target / 'SlowFast'), 'archive': str(archive_path)}, ensure_ascii=False))
