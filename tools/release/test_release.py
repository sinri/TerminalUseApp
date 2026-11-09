import importlib.util
from pathlib import Path
import tempfile
import json
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release', Path(__file__).with_name('release.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_version_bumps_preserve_metadata_and_increment_build(self):
        for part, expected in [('major', '3.0.0+42'), ('minor', '2.4.0+42'),
                               ('patch', '2.3.5+42'), ('build', '2.3.4+42')]:
            with self.subTest(part=part), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                path = root / 'pubspec.yaml'
                path.write_text('name: example\nversion: 2.3.4+41\n# preserved\n')
                release.bump(part, root)
                self.assertEqual(path.read_text(), f'name: example\nversion: {expected}\n# preserved\n')

    def test_reject_missing_build_number(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'pubspec.yaml').write_text('version: 1.0.0\n')
            with self.assertRaises(ValueError):
                release.version(root)

    def test_dirty_tree_cannot_release(self):
        with patch.object(release, 'run', return_value=' M pubspec.yaml'):
            with self.assertRaisesRegex(ValueError, 'Commit all changes'):
                release.require_tag()

    def test_wrong_tag_cannot_release(self):
        with patch.object(release, 'run', side_effect=['', 'head', 'old']), \
             patch.object(release, 'tag_name', return_value='v1.0.0+1'):
            with self.assertRaisesRegex(ValueError, 'must point to HEAD'):
                release.require_tag()

    def test_rejected_notarization_cannot_pass(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / 'notary.json'
            with patch.object(release, 'run', return_value='{"status":"Invalid","id":"123"}'):
                with self.assertRaisesRegex(ValueError, 'Notarization failed'):
                    release.notarize(Path('test.zip'), 'profile', output)
            self.assertIn('Invalid', output.read_text())

    def test_missing_developer_id_cannot_pass(self):
        with patch.dict(release.os.environ, {'SIGN_IDENTITY': '-', 'NOTARY_PROFILE': 'profile'}):
            with self.assertRaisesRegex(ValueError, 'Set SIGN_IDENTITY'):
                release.credentials()

    def test_tampered_artifact_cannot_upload(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'release.json').write_text(json.dumps(dict(
                tag='v1.0.0+1', commit='abc', files=['test.dmg', 'test-SHA256SUMS.txt'])))
            (root / 'test.dmg').write_bytes(b'tampered')
            (root / 'test-SHA256SUMS.txt').write_text('wrong  test.dmg\n')
            with patch.object(release, 'require_tag', return_value=('v1.0.0+1', 'abc')), \
                 patch.object(release, 'run') as command:
                with self.assertRaisesRegex(ValueError, 'Checksum mismatch'):
                    release.publish(root)
                command.assert_not_called()


if __name__ == '__main__':
    unittest.main()
