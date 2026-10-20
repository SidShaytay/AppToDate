"""Offline regression tests: python3 -m unittest discover -s tests -v."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FAKE = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
a = sys.argv[1:]
name = Path(sys.argv[0]).name
home = Path(os.environ['HOME'])
with (home / 'calls').open('a') as f:
    f.write(name + ' ' + ' '.join(a) + '\n')
if name == 'curl':
    if '%{url_effective}' in a:
        print('https://example.org/LM-Studio-1.2.3-1-x64.AppImage')
    elif '-o' in a:
        Path(a[a.index('-o') + 1]).write_text('download')
    else:
        print(json.dumps({'tag_name': 'v1.2.3', 'assets': [
            {'name': 'OneDriveGUI-x86_64.AppImage', 'browser_download_url': 'https://example.org/app'}]}))
elif name == 'git':
    if 'branch' in a: print('master')
    elif 'rev-parse' in a: print('true' if '--is-inside-work-tree' in a else os.environ.get('REV', 'abc123'))
    elif 'diff' in a: sys.exit(1 if os.environ.get('DIRTY') else 0)
elif name == 'toolbox':
    if '--version' not in a:
        if os.environ.get('BUILD_FAIL'): sys.exit(1)
        binary = home / 'build/bin/llama-server'
        binary.parent.mkdir(parents=True, exist_ok=True)
        binary.write_text('#!/bin/sh\nexit 0\n')
        binary.chmod(0o755)
elif name == 'rsync':
    import shutil
    shutil.copy2(home / 'build/bin/llama-server', home / 'Apps/llama.cpp/llama-server')
elif name == 'systemctl':
    if os.environ.get('RESTART_FAIL'): sys.exit(1)
elif name == 'flatpak':
    if a[0] == 'list': print('app 1.0 ' + ('new' if (home / 'updated').exists() and os.environ.get('CHANGED') else 'old'))
    elif a[0] == 'update': (home / 'updated').touch()
'''


class UpdateSkipTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        for name in ('curl', 'git', 'toolbox', 'rsync', 'systemctl', 'flatpak'):
            p = self.bin / name
            p.write_text(FAKE)
            p.chmod(0o755)
        self.env = {**os.environ, 'HOME': str(self.home),
                    'PATH': str(self.bin) + ':' + os.environ['PATH']}

    def run_script(self, name, *args):
        script = ROOT / name
        if name == 'llama.cpp-update.sh':
            # Keep production path guards, but redirect the fixed data mount into the sandbox.
            script = self.home / name
            script.write_text((ROOT / name).read_text().replace(
                '/var/mnt/data/projects/ai/llama.cpp', str(self.home / 'data')).replace(
                'BUILD_DIR="${DEST_ROOT}/build-rocm-7.2.3"', 'BUILD_DIR="${HOME}/build"'))
        result = subprocess.run(['bash', str(script), *args], env=self.env,
                                capture_output=True, text=True)
        return result

    def calls(self):
        return (self.home / 'calls').read_text()

    def appimage(self, app, version):
        app_path = self.home / f'Apps/{app}.appimage'
        app_path.parent.mkdir(exist_ok=True)
        app_path.write_text('original')
        app_path.chmod(0o755)
        desktop = self.home / f'.local/share/applications/{app}.desktop'
        desktop.parent.mkdir(parents=True, exist_ok=True)
        desktop.write_text(f'X-AppImage-Version={version}\n')
        return app_path

    def test_onedrive_skips_same_or_newer_version(self):
        for version in ('1.2.3', 'v1.2.3', '1.2.4'):
            with self.subTest(version=version):
                app = self.appimage('onedrivegui', version)
                result = self.run_script('onedrivegui-update.sh')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(app.read_text(), 'original')

    def test_appimages_remember_update_without_desktop_file(self):
        for app, script in (('onedrivegui', 'onedrivegui-update.sh'),
                            ('lm_studio', 'lmstudio-update.DISABLED.sh')):
            with self.subTest(app=app):
                self.appimage(app, 'old')
                (self.home / f'.local/share/applications/{app}.desktop').unlink()
                self.assertEqual(self.run_script(script).returncode, 0)
                (self.home / 'calls').write_text('')
                self.assertEqual(self.run_script(script).returncode, 0)
                self.assertNotIn('-o ' + str(self.home / 'Apps'), self.calls())

    def test_lmstudio_uses_head_and_skips_current_version(self):
        app = self.appimage('lm_studio', '1.2.3-1')
        result = self.run_script('lmstudio-update.DISABLED.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(app.read_text(), 'original')
        self.assertIn('--head', self.calls())

    def prepare_llama(self):
        for directory in ('Projects/ai/llama.cpp', 'data', 'Apps/llama.cpp'):
            (self.home / directory).mkdir(parents=True)

    def test_llama_skips_only_after_successful_install(self):
        self.prepare_llama()
        self.assertEqual(self.run_script('llama.cpp-update.sh').returncode, 0)
        (self.home / 'calls').write_text('')
        result = self.run_script('llama.cpp-update.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('bash -lc', self.calls())
        self.assertNotIn('rsync', self.calls())
        self.assertNotIn('systemctl', self.calls())
        self.env['REV'] = 'def456'
        self.assertEqual(self.run_script('llama.cpp-update.sh').returncode, 0)
        self.assertIn('rsync', self.calls())

    def test_llama_rebuilds_when_binary_missing(self):
        self.prepare_llama()
        self.assertEqual(self.run_script('llama.cpp-update.sh').returncode, 0)
        (self.home / 'Apps/llama.cpp/llama-server').unlink()
        (self.home / 'calls').write_text('')
        self.assertEqual(self.run_script('llama.cpp-update.sh').returncode, 0)
        self.assertIn('rsync', self.calls())

    def test_llama_retries_after_restart_failure(self):
        self.prepare_llama()
        self.env['RESTART_FAIL'] = '1'
        self.assertNotEqual(self.run_script('llama.cpp-update.sh').returncode, 0)
        del self.env['RESTART_FAIL']
        (self.home / 'calls').write_text('')
        self.assertEqual(self.run_script('llama.cpp-update.sh').returncode, 0)
        self.assertIn('rsync', self.calls())

    def test_llama_retries_failed_build_and_allows_dirty_rebuild(self):
        self.prepare_llama()
        self.env['BUILD_FAIL'] = '1'
        self.assertNotEqual(self.run_script('llama.cpp-update.sh').returncode, 0)
        del self.env['BUILD_FAIL']
        self.assertEqual(self.run_script('llama.cpp-update.sh').returncode, 0)
        (self.home / 'calls').write_text('')
        self.env['DIRTY'] = '1'
        self.assertEqual(self.run_script('llama.cpp-update.sh', '--allow-dirty').returncode, 0)
        self.assertIn('rsync', self.calls())

    def test_flatpak_restarts_only_after_changed_install(self):
        result = self.run_script('flatpak-update.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('systemctl', self.calls())
        self.env['CHANGED'] = '1'
        (self.home / 'updated').unlink()
        self.assertEqual(self.run_script('flatpak-update.sh').returncode, 0)
        self.assertIn('systemctl', self.calls())


if __name__ == '__main__':
    unittest.main()
