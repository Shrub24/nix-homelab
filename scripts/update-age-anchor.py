#!/usr/bin/env python3
"""Replace exactly one ``&<alias>`` age recipient anchor in a SOPS policy file.

Fail closed: the anchor must exist exactly once, the supplied recipient must be
a well-formed age1 recipient, and the file must actually change. Nothing is
written on any validation failure. The caller (`.just/host-age.just` from-key)
owns the operator-facing guarantee that the recipient derives from a
console-verified host key.
"""

import os
import re
import sys
import tempfile

_RECIPIENT = re.compile(r"age1[0-9a-z]{58}")


def main() -> int:
    if len(sys.argv) != 4:
        print(f"usage: {sys.argv[0]} <path> <alias> <recipient>", file=sys.stderr)
        return 2
    path, alias, recipient = sys.argv[1:4]

    if not _RECIPIENT.fullmatch(recipient):
        print(
            f"update-age-anchor: not a well-formed age recipient: {recipient}",
            file=sys.stderr,
        )
        return 1

    with open(path, encoding="utf-8") as f:
        text = f.read()

    pattern = re.compile(
        rf"^(\s*-\s*&{re.escape(alias)}\s+){_RECIPIENT.pattern}(?=\s*$)",
        re.MULTILINE,
    )
    matches = pattern.findall(text)
    if len(matches) != 1:
        print(
            f"update-age-anchor: expected exactly one &{alias} anchor, found {len(matches)}",
            file=sys.stderr,
        )
        return 1
    new = pattern.sub(rf"\g<1>{recipient}", text)
    if new == text:
        print(
            f"update-age-anchor: &{alias} already has recipient {recipient}",
            file=sys.stderr,
        )
        return 1

    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(path)))
    try:
        os.chmod(tmp, os.stat(path).st_mode & 0o7777)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(new)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise
    return 0


if __name__ == "__main__":
    sys.exit(main())
