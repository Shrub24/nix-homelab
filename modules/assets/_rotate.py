"""Replace the published background with a randomly chosen candidate from the bucket.

The wallpaper URL never changes; only the object behind it does, so a rotation needs no
rebuild and no consumer edit.
"""

import json
import os
import random
import sys
import urllib.error
import urllib.request
from pathlib import Path

import boto3

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


def zone_id(token, name):
    request = urllib.request.Request(
        f"https://api.cloudflare.com/client/v4/zones?name={name}",
        headers={"Authorization": f"Bearer {token}"},
    )
    try:
        payload = json.load(urllib.request.urlopen(request, timeout=20))
    except (urllib.error.URLError, TimeoutError) as error:
        print(f"purge: zone lookup failed: {error}", file=sys.stderr)
        return None
    return payload["result"][0]["id"] if payload.get("result") else None


def purge(spec):
    """Drop the cached copy of the replaced object; a failure leaves the old image visible
    until the browser lifetime expires, which is why it does not fail the rotation."""
    token = os.environ.get("CF_PURGE_TOKEN")
    if not token:
        print("purge: no Cloudflare credential configured, relying on cache lifetime")
        return
    zone = zone_id(token, spec["zoneName"])
    if zone is None:
        print(f"purge: no zone named {spec['zoneName']}", file=sys.stderr)
        return
    request = urllib.request.Request(
        f"https://api.cloudflare.com/client/v4/zones/{zone}/purge_cache",
        data=json.dumps({"files": [spec["url"]]}).encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        urllib.request.urlopen(request, timeout=20)
        print(f"purge: {spec['url']}")
    except (urllib.error.URLError, TimeoutError) as error:
        print(f"purge failed: {error}", file=sys.stderr)


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
    purge(spec)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
