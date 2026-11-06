"""Drop Cloudflare's cached copies of replaced assets.

The zone holds these objects at the edge for a year, so a replacement stays invisible until its
URL is purged. Callers decide whether a failed purge is fatal.
"""

import json
import sys
import urllib.error
import urllib.request

API = "https://api.cloudflare.com/client/v4"


def call(token, path, body=None):
    request = urllib.request.Request(
        f"{API}/{path}",
        data=None if body is None else json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="GET" if body is None else "POST",
    )
    return json.load(urllib.request.urlopen(request, timeout=20))


def purge(urls, zone_name, token):
    """Purge every URL in one request; True when the edge accepted it."""
    if not token:
        print("purge: no Cloudflare credential configured", file=sys.stderr)
        return False
    try:
        zones = call(token, f"zones?name={zone_name}").get("result")
        if not zones:
            print(f"purge: no zone named {zone_name}", file=sys.stderr)
            return False
        call(token, f"zones/{zones[0]['id']}/purge_cache", {"files": urls})
    except (urllib.error.URLError, TimeoutError) as error:
        print(f"purge failed: {error}", file=sys.stderr)
        return False
    print(f"purge: {', '.join(urls)}", flush=True)
    return True
