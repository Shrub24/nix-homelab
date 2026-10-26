"""Build-time YAML handling; Authentik resolves expressions at runtime."""

import argparse
import json
import sys
from pathlib import Path

from jsonschema import Draft7Validator, FormatChecker, validators
from ruamel.yaml import YAML
from ruamel.yaml.comments import CommentedMap, CommentedSeq, TaggedScalar
from ruamel.yaml.error import YAMLError
from ruamel.yaml.scalarstring import LiteralScalarString

YAML_READER = YAML()
TAGS = {
    "!KeyOf": "scalar",
    "!Env": "scalar",
    "!Context": "scalar",
    "!Find": "sequence",
    "!Format": "sequence",
}


def expression(value):
    return str(getattr(value, "tag", "")) in TAGS


def defer_expression(validate):
    def check(validator, constraint, instance, schema):
        if not expression(instance):
            yield from validate(validator, constraint, instance, schema)

    return check


BlueprintValidator = validators.extend(
    Draft7Validator,
    {
        keyword: defer_expression(check)
        for keyword, check in Draft7Validator.VALIDATORS.items()
    },
)


def check_tags(value):
    tag = str(getattr(value, "tag", ""))
    if tag.startswith("!"):
        shape = TAGS.get(tag)
        if (
            shape == "scalar"
            and isinstance(value, TaggedScalar)
            and str(value.value).strip()
        ):
            return
        if shape == "sequence" and isinstance(value, CommentedSeq) and len(value) >= 2:
            for item in value:
                check_tags(item)
            return
        raise ValueError("unsupported tag or invalid tag argument")
    if isinstance(value, dict):
        for key, item in value.items():
            if not isinstance(key, str):
                raise ValueError("mapping keys must be literal strings")
            check_tags(item)
    elif isinstance(value, list):
        for item in value:
            check_tags(item)


def load(path):
    with open(path) as source:
        document = YAML_READER.load(source)
    check_tags(document)
    return document


def validate(document, schema):
    validator = BlueprintValidator(schema, format_checker=FormatChecker())
    for error in validator.iter_errors(document):
        # oneOf messages can contain the whole document, including runtime placeholders.
        while error.context and not any(
            isinstance(key, int) for key in error.absolute_path
        ):
            error = error.context[0]
        keys = list(error.absolute_path)
        path = "/".join(map(str, keys)) or "document"
        node = document
        for key in keys:
            try:
                node = node[key]
            except (KeyError, IndexError, TypeError):
                break
        line = getattr(getattr(node, "lc", None), "line", None)
        location = f" line {line + 1}" if line is not None else ""
        raise ValueError(f"{path}{location}: violates schema keyword {error.validator}")


def assemble(value):
    if isinstance(value, dict):
        if set(value) == {"__raw"}:
            return YAML_READER.load(value["__raw"])
        return CommentedMap((key, assemble(item)) for key, item in value.items())
    if isinstance(value, list):
        result = CommentedSeq()
        for item in value:
            if isinstance(item, dict) and set(item) == {"__file"}:
                result.extend(load(item["__file"])["entries"])
            else:
                result.append(assemble(item))
        return result
    if isinstance(value, str) and "\n" in value:
        return LiteralScalarString(value)
    return value


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--schema", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("document", type=Path)
    args = parser.parse_args()
    try:
        document = assemble(json.loads(args.document.read_text()))
        check_tags(document)
        if args.schema:
            validate(document, json.loads(args.schema.read_text()))
        with args.output.open("w") as output:
            YAML_READER.dump(document, output)
    except (ValueError, YAMLError) as error:
        if isinstance(error, YAMLError):
            mark = getattr(error, "problem_mark", None)
            location = f" at line {mark.line + 1}" if mark else ""
            print(f"{args.document}: invalid YAML{location}", file=sys.stderr)
        else:
            print(f"{args.document}: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
