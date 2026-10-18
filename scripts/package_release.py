#!/usr/bin/env python3
"""Archive a clean committed source tree and a previously built preview app."""
from pathlib import Path
import argparse, hashlib, plistlib, re, subprocess, tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('version')
args = parser.parse_args()
version = args.version
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise SystemExit('Expected a numeric major.minor.patch version.')
if subprocess.check_output(['git', 'status', '--porcelain'], cwd=root):
    raise SystemExit('Commit the intended release files before creating source assets.')
app = root / 'build/Minecraft on Mac.app'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
if info['CFBundleShortVersionString'] != version:
    raise SystemExit('Built app version differs from requested release.')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
output = root / 'build' / ('release-' + version)
output.mkdir(exist_ok=True)
archive = output / f'Minecraft-on-Mac-{version}-preview-arm64.zip'
disk = output / f'Minecraft-on-Mac-{version}-preview-arm64.dmg'
source = output / f'Minecraft-on-Mac-{version}-source.zip'
for path in [archive, disk, source]:
    if path.exists():
        raise SystemExit('Refusing to overwrite release asset: ' + str(path))
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
with tempfile.TemporaryDirectory(prefix='minecraft-release-', dir=root/'build') as temporary:
    stage = Path(temporary)
    subprocess.run(['ditto', str(app), str(stage/app.name)], check=True)
    (stage/'Applications').symlink_to('/Applications')
    (stage/'START-HERE.txt').write_text(
        'Drag Minecraft on Mac.app to Applications, then eject this disk.\n\n'
        'Requires an Apple silicon Mac, macOS 14+, a separately installed and licensed\n'
        'CrossOver, a Microsoft game license, internet and 35 GB free to install a game.\n'
        'Bedrock requires CrossOver 26.3.x. No developer tools or existing bottle needed.\n\n'
        'This preview is ad-hoc signed and unnotarized. If macOS blocks first launch,\n'
        'use System Settings > Privacy & Security > Open Anyway for this app.\n'
        'Microsoft sign-in and Keychain access are requested by the launcher.\n\n'
        'Guide: https://github.com/rafaelreverberi/Minecraft-on-Mac/blob/v'+version+'/docs/INSTALL.md\n'
    )
    subprocess.run(['hdiutil', 'create', '-volname', 'Minecraft on Mac '+version,
                    '-srcfolder', str(stage), '-format', 'UDZO', str(disk)], check=True)
subprocess.run(['git', 'archive', '--format=zip', '--prefix=Minecraft-on-Mac-'+version+'/',
                '--output', str(source), 'HEAD'], cwd=root, check=True)
lines = [hashlib.sha256(path.read_bytes()).hexdigest()+'  '+path.name for path in [archive, disk, source]]
(output/f'SHA256SUMS-{version}.txt').write_text('\n'.join(lines)+'\n')
print('Release assets created in '+str(output))
