import importlib.util
import tempfile
import unittest
from pathlib import Path

from botocore.exceptions import ClientError

loader = importlib.util.spec_from_file_location(
    "publisher", Path(__file__).resolve().parents[1] / "modules/assets/_publish.py"
)
publisher = importlib.util.module_from_spec(loader)
loader.loader.exec_module(publisher)
SVG = b'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><path d="M0 0h10v10z"/></svg>'


class Storage:
    def __init__(self):
        self.objects = {"shrublab/wallpaper.jpg": {"Body": b"operator-owned"}}
        self.writes = 0
        self.deny = False

    def head_object(self, *, Bucket, Key):
        if self.deny or Key not in self.objects:
            code = "AccessDenied" if self.deny else "404"
            raise ClientError({"Error": {"Code": code}}, "HeadObject")
        return self.objects[Key]

    def put_object(self, *, Bucket, Key, **value):
        self.objects[Key] = value
        self.writes += 1


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.file = Path(self.directory.name) / "icon.svg"
        self.file.write_bytes(SVG)
        self.spec = {"bucket": "assets", "key": "icons/test", "file": str(self.file)}
        self.storage = Storage()

    def test_changed_and_unchanged_content(self):
        self.assertTrue(publisher.publish(self.spec, self.storage))
        self.assertFalse(publisher.publish(self.spec, self.storage))
        self.assertEqual(self.storage.writes, 1)
        self.file.write_bytes(SVG.replace(b"10 10", b"20 20"))
        self.assertTrue(publisher.publish(self.spec, self.storage))
        self.assertEqual(self.storage.writes, 2)
        self.assertEqual(
            self.storage.objects["shrublab/wallpaper.jpg"]["Body"], b"operator-owned"
        )

    def test_wrong_stored_content_type_is_corrected(self):
        publisher.publish(self.spec, self.storage)
        self.storage.objects["icons/test"]["ContentType"] = "text/xml"
        self.assertTrue(publisher.publish(self.spec, self.storage))
        self.assertEqual(
            self.storage.objects["icons/test"]["ContentType"], "image/svg+xml"
        )

    def test_failed_read_preserves_last_good(self):
        publisher.publish(self.spec, self.storage)
        self.file.unlink()
        with self.assertRaises(FileNotFoundError):
            publisher.publish(self.spec, self.storage)
        self.assertEqual(self.storage.writes, 1)
        self.assertEqual(self.storage.objects["icons/test"]["Body"], SVG)

    def test_storage_permission_error_is_not_treated_as_absence(self):
        publisher.publish(self.spec, self.storage)
        self.file.write_bytes(SVG.replace(b"10 10", b"20 20"))
        self.storage.deny = True
        with self.assertRaises(ClientError):
            publisher.publish(self.spec, self.storage)
        self.assertEqual(self.storage.writes, 1)
        self.assertEqual(self.storage.objects["icons/test"]["Body"], SVG)


class PublicationListTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        changed = Path(self.directory.name) / "icon.svg"
        changed.write_bytes(SVG)
        unchanged = Path(self.directory.name) / "logo.svg"
        unchanged.write_bytes(SVG)
        missing = Path(self.directory.name) / "gone.svg"
        self.spec = {
            "bucket": "assets",
            "objects": [
                {"key": "icon.svg", "file": str(changed)},
                {"key": "logo.svg", "file": str(unchanged)},
            ],
        }
        self.storage = Storage()

    def test_identical_objects_publish_once(self):
        self.assertEqual(publisher.publish_all(self.spec, self.storage), 0)
        self.assertEqual(self.storage.writes, 2)
        self.assertEqual(publisher.publish_all(self.spec, self.storage), 0)
        self.assertEqual(self.storage.writes, 2)

    def test_a_failed_object_does_not_block_the_rest(self):
        self.spec["objects"].append(
            {"key": "gone.svg", "file": "/nonexistent/gone.svg"}
        )
        self.assertEqual(publisher.publish_all(self.spec, self.storage), 1)
        self.assertEqual(self.storage.writes, 2)
        self.assertIn("icon.svg", self.storage.objects)


if __name__ == "__main__":
    unittest.main()
