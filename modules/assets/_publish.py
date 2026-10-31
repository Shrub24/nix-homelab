import hashlib
import json
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from botocore.exceptions import ClientError

MAX_BYTES = 4 * 1024 * 1024
CACHE_CONTROL = "public, max-age=300"


def image_type(data):
    if data.startswith(b"\x89PNG\r\n\x1a\n") and len(data) >= 24:
        return "image/png"
    if data.startswith(b"\xff\xd8\xff") and data.endswith(b"\xff\xd9"):
        return "image/jpeg"
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return "image/gif"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    if data[:4] == b"\x00\x00\x01\x00" and len(data) >= 22:
        count = struct.unpack_from("<H", data, 4)[0]
        if count and len(data) >= 6 + 16 * count:
            return "image/vnd.microsoft.icon"
    try:
        root = ET.fromstring(data)
    except ET.ParseError:
        root = None
    if root is not None and root.tag == "{http://www.w3.org/2000/svg}svg":
        return "image/svg+xml"
    raise ValueError("source did not contain a supported image")


def read_source(spec):
    with Path(spec["file"]).open("rb") as source:
        data = source.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ValueError("source exceeds the 4 MiB image limit")
    return data


def publish(spec, storage):
    data = read_source(spec)
    content_type = image_type(data)
    digest = hashlib.sha256(data).hexdigest()
    try:
        current = storage.head_object(Bucket=spec["bucket"], Key=spec["key"])
    except ClientError as error:
        if error.response["Error"]["Code"] not in ("404", "NoSuchKey", "NotFound"):
            raise
        current = {}
    if (
        current.get("Metadata", {}).get("sha256") == digest
        and current.get("ContentType") == content_type
        and current.get("CacheControl") == CACHE_CONTROL
    ):
        print(f"{spec['key']}: unchanged", flush=True)
        return False
    storage.put_object(
        Bucket=spec["bucket"],
        Key=spec["key"],
        Body=data,
        ContentType=content_type,
        CacheControl=CACHE_CONTROL,
        Metadata={"sha256": digest},
    )
    print(f"{spec['key']}: published {len(data)} bytes ({content_type})", flush=True)
    return True


def publish_all(spec, storage):
    failures = []
    for object in spec["objects"]:
        try:
            publish({**object, "bucket": spec["bucket"]}, storage)
        except Exception as error:  # one bad object must not block the others
            print(f"{object['key']}: {error}", file=sys.stderr)
            failures.append(object["key"])
    return 1 if failures else 0


def main():
    import boto3
    from botocore.config import Config

    spec = json.loads(Path(sys.argv[1]).read_text())
    storage = boto3.client(
        "s3",
        endpoint_url=spec["endpoint"],
        region_name="auto",
        config=Config(
            connect_timeout=5,
            read_timeout=10,
            retries={"max_attempts": 2},
            request_checksum_calculation="when_required",
            response_checksum_validation="when_required",
        ),
    )
    sys.exit(publish_all(spec, storage))


if __name__ == "__main__":
    main()
