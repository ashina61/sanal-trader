import tempfile
import unittest
from pathlib import Path

from scripts.version_web_bootstrap import version_bootstrap


class WebBootstrapTests(unittest.TestCase):
    def test_new_release_gets_new_script_urls_and_preserves_base(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            index = '<base href="/sanal-trader/"><script src="flutter_bootstrap.js" async></script>'
            bootstrap = '_flutter.buildConfig={"builds":[{"mainJsPath":"main.dart.js"}]};'
            (root / 'index.html').write_text(index)
            (root / 'flutter_bootstrap.js').write_text(bootstrap)
            (root / 'main.dart.js').write_bytes(b'first release')
            first_entry, first_boot = version_bootstrap(root)
            self.assertIn('src="' + first_boot + '"', (root / 'index.html').read_text())
            self.assertIn('/sanal-trader/', (root / 'index.html').read_text())
            self.assertIn(first_entry, (root / first_boot).read_text())
            self.assertEqual((root / first_entry).read_bytes(), b'first release')
            self.assertTrue((root / 'main.dart.js').exists())
            (root / 'index.html').write_text(index)
            (root / 'main.dart.js').write_bytes(b'next release')
            second_entry, second_boot = version_bootstrap(root)
            self.assertNotEqual(first_entry, second_entry)
            self.assertNotEqual(first_boot, second_boot)

    def test_invalid_loader_stops_packaging_without_changing_index(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            index = '<script src="unexpected.js"></script>'
            (root / 'index.html').write_text(index)
            (root / 'flutter_bootstrap.js').write_text('"main.dart.js"')
            (root / 'main.dart.js').write_bytes(b'code')
            with self.assertRaises(ValueError):
                version_bootstrap(root)
            self.assertEqual((root / 'index.html').read_text(), index)
            self.assertEqual(len(list(root.iterdir())), 3)
