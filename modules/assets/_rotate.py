"""Replace the published background with a randomly chosen candidate from the bucket.

The wallpaper URL never changes; only the object behind it does, so a rotation needs no
rebuild and no consumer edit.
"""

import json
import os
import random
import sys
from pathlib import Path

import boto3

import _purge

IMAGE_SUFFIXES = ("png", "jpg", "jpeg", "webp")
CONTENT_TYPES = {
    "png": "image/png",
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "webp": "image/webp",
}


def candidates(client, bucket, prefix):
    listing = client.list_objects_v2(Bucket=bucket, Prefix=prefix)
    return sorted(
        entry["Key"]
        for entry in listing.get("Contents", [])
        if entry["Key"].rsplit(".", 1)[-1].lower() in IMAGE_SUFFIXES
    )


def main(spec_path):
    spec = json.loads(Path(spec_path).read_text())
    client = boto3.client("s3", endpoint_url=spec["endpoint"], region_name="auto")

    keys = candidates(client, spec["bucket"], spec["prefix"])
    if not keys:
        print(f"no candidates under {spec['prefix']}", file=sys.stderr)
        return 1

    key = random.choice(keys)
    content_type = CONTENT_TYPES[key.rsplit(".", 1)[-1].lower()]
    client.copy_object(
        Bucket=spec["bucket"],
        Key=spec["key"],
        CopySource={"Bucket": spec["bucket"], "Key": key},
        MetadataDirective="REPLACE",
        ContentType=content_type,
        CacheControl=spec["cacheControl"],
    )
    print(f"background: {key} -> {spec['key']} ({content_type})")
    # A failed purge leaves the previous image up until the next rotation, so it is not fatal.
    _purge.purge([spec["url"]], spec["zoneName"], os.environ.get("CF_PURGE_TOKEN"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
