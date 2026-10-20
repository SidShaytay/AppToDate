"""Run with: python3 -m unittest discover -s tests -v."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "podman-update.sh"

FAKE = r'''#!/usr/bin/env python3
import os, sys
from pathlib import Path
a = sys.argv[1:]
command = Path(sys.argv[0]).name
state = Path(os.environ['FAKE_STATE'])
case = os.environ['CASE']
with (state / 'calls').open('a') as f:
    f.write(command + ' ' + ' '.join(a) + '\n')
if command == 'sleep':
    sys.exit(0)
if command == 'systemctl':
    sys.exit(1 if case == 'restart_failure' else 0)
if a[:2] == ['image', 'inspect']:
    print('new' if (state / a[-1].replace('/', '_')).exists() and case != 'unchanged' else 'old')
elif a[0] == 'pull':
    if case == 'pull_failure': sys.exit(1)
    (state / a[-1].replace('/', '_')).touch()
elif a[:2] == ['container', 'inspect']:
    image = 'old' if case == 'pinned' else 'new'
    running = 'false' if case == 'stopped' else 'true'
    health = 'unhealthy' if case == 'unhealthy' else 'none'
    print(image, running, health)
elif a[0] == 'ps':
    if case == 'shared': print('another-container')
    if case == 'list_failure': sys.exit(1)
elif a[:2] == ['image', 'rm']:
    assert '--force' not in a and '-f' not in a
    (state / 'removed').touch()
else:
    sys.exit('unexpected command: ' + repr(a))
'''


class PodmanUpdateTests(unittest.TestCase):
    def run_case(self, case):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ('podman', 'systemctl', 'sleep'):
                executable = root / name
                executable.write_text(FAKE)
                executable.chmod(0o755)
            result = subprocess.run(
                ['bash', str(SCRIPT)], capture_output=True, text=True,
                env={**os.environ, 'PATH': tmp + ':' + os.environ['PATH'],
                     'FAKE_STATE': tmp, 'CASE': case},
            )
            return result, (root / 'removed').exists(), (root / 'calls').read_text()

    def test_removes_replaced_image_after_verification(self):
        result, removed, calls = self.run_case('success')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(removed)
        self.assertLess(calls.index('container inspect'), calls.index('image rm'))
        self.assertIn('restart sillytavern.service', calls)

    def test_keeps_images_when_update_is_not_verified(self):
        for case in ('restart_failure', 'pull_failure', 'pinned', 'stopped',
                     'unhealthy', 'shared', 'list_failure', 'unchanged'):
            with self.subTest(case=case):
                _, removed, _ = self.run_case(case)
                self.assertFalse(removed)

    def test_does_not_restart_unchanged_images(self):
        _, _, calls = self.run_case('unchanged')
        self.assertNotIn('systemctl', calls)

    def test_only_cleans_images_with_managed_containers(self):
        _, _, calls = self.run_case('success')
        self.assertEqual(calls.count('image rm'), 4)


if __name__ == '__main__':
    unittest.main()
