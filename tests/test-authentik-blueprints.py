"""The adapter must not turn a tagged reference into an exemption for its siblings."""

import importlib.util
import unittest
from pathlib import Path

MODULE = (
    Path(__file__).resolve().parents[1]
    / "modules/identity/authentik/_blueprint/assemble.py"
)
spec = importlib.util.spec_from_file_location("blueprints", MODULE)
blueprints = importlib.util.module_from_spec(spec)
spec.loader.exec_module(blueprints)

SCHEMA = {
    "oneOf": [
        {
            "type": "object",
            "required": ["model", "provider", "mode"],
            "properties": {
                "model": {"const": model},
                "provider": {"type": "integer"},
                "mode": {"enum": ["any", "all"]},
            },
        }
        for model in ["application", "other"]
    ]
}


class BlueprintValidation(unittest.TestCase):
    def document(self, text):
        doc = blueprints.YAML_READER.load(text)
        blueprints.check_tags(doc)
        return doc

    def test_reference_is_deferred_but_literal_siblings_are_not(self):
        doc = self.document(
            "model: application\nprovider: !KeyOf provider\nmode: all\n"
        )
        blueprints.validate(doc, SCHEMA)
        doc["mode"] = "invalid"
        with self.assertRaisesRegex(ValueError, "schema keyword"):
            blueprints.validate(doc, SCHEMA)

    def test_untagged_bad_foreign_key_is_rejected(self):
        doc = self.document("model: application\nprovider: not-an-id\nmode: all\n")
        with self.assertRaisesRegex(ValueError, "schema keyword"):
            blueprints.validate(doc, SCHEMA)

    def test_unknown_and_malformed_tags_are_rejected(self):
        for text in ["!Typo name", "!KeyOf [name]", "!KeyOf ''", "!Find [model]"]:
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, "tag"):
                self.document(text)


if __name__ == "__main__":
    unittest.main()
