"""Insert a credential-backed qBittorrent password into the generated INI."""

import base64
import hashlib
import os
from pathlib import Path
import secrets
import sys

config = Path(sys.argv[1])
password = (Path(os.environ["CREDENTIALS_DIRECTORY"]) / "webui-password").read_bytes()
password = password.removesuffix(b"\n")
if not password:
    raise ValueError("qBittorrent WebUI password must not be empty")

salt = secrets.token_bytes(16)
digest = hashlib.pbkdf2_hmac("sha512", password, salt, 100_000, dklen=64)
encoded = ":".join(base64.b64encode(value).decode("ascii") for value in (salt, digest))
content = config.read_text()
placeholder = "@SOPS_WEBUI_PASSWORD@"
if content.count(placeholder) != 1:
    raise ValueError("qBittorrent config must contain exactly one password placeholder")
config.write_text(content.replace(placeholder, f"@ByteArray({encoded})"))
