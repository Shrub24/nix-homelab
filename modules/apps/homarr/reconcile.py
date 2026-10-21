#!/usr/bin/env python3
"""Sync Homarr's app bookmarks with the fleet's web policy.

An app is the annoying thing to maintain: a name, a URL and an icon that drift
every time a route is renamed or a service moves. A board is taste, so it stays
in the UI where it belongs — a person assembles one from these apps.

The desired state is compiled by Nix from `policy/web-services.nix` and passed as
a JSON document. Apps are matched by `href`:

  * missing  — created;
  * drifted  — name, icon or description patched in place;
  * unlisted — left alone. An app this script did not create is someone's own
               bookmark, and an app whose route retired may still sit on a board
               that was arranged by hand, so nothing is deleted.

Exits 0 without touching anything when the API key is absent or empty, because
"the operator has not minted a key yet" is a prepared state rather than a fault.
Any API error is a failure, so the unit reaches `failed` and the fleet's
notification path reports it.

Configuration (environment):
  HOMARR_BASE_URL      base URL of the instance, e.g. http://127.0.0.1:7575
  HOMARR_API_KEY_FILE  file holding an `ApiKey`-format key (`<id>.<token>`)
  HOMARR_DESIRED_FILE  the compiled document: {"apps": [ ... ]}
"""

import json
import os
import sys
import urllib.error
import urllib.request

TIMEOUT_SECONDS = 30


def log(message):
    print(f"homarr-apps: {message}", flush=True)


def load_key(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError as error:
        log(f"cannot read the API key ({error}); nothing to sync")
        return None


class Homarr:
    def __init__(self, base_url, api_key):
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key

    def call(self, method, path, payload=None):
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(self.base_url + path, data=body, method=method)
        request.add_header("ApiKey", self.api_key)
        request.add_header("Accept", "application/json")
        if body is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
                raw = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", "replace")[:400]
            raise RuntimeError(
                f"{method} {path} answered {error.code}: {detail}"
            ) from error
        except urllib.error.URLError as error:
            raise RuntimeError(
                f"{method} {path} is unreachable: {error.reason}"
            ) from error
        return json.loads(raw) if raw else None


def sync(homarr, desired):
    existing = {app["href"]: app for app in homarr.call("GET", "/api/apps") or []}
    created = updated = unchanged = 0
    for wanted in desired:
        current = existing.get(wanted["href"])
        if current is None:
            # Every key is sent because Homarr's schema declares them nullable but
            # not optional: an absent `pingUrl` is a validation failure, while an
            # empty string is the accepted way to say "no health check".
            homarr.call(
                "POST",
                "/api/apps",
                {
                    "name": wanted["name"],
                    "href": wanted["href"],
                    "iconUrl": wanted["iconUrl"],
                    "description": "",
                    "pingUrl": "",
                },
            )
            log(f"created app {wanted['name']}")
            created += 1
            continue
        drift = [
            field
            for field in ("name", "iconUrl")
            if current.get(field) != wanted[field]
        ]
        if not drift:
            unchanged += 1
            continue
        homarr.call(
            "PATCH",
            f"/api/apps/{current['id']}",
            {
                "id": current["id"],
                "name": wanted["name"],
                "iconUrl": wanted["iconUrl"],
                "href": wanted["href"],
                "description": "",
                "pingUrl": current.get("pingUrl") or "",
            },
        )
        log(f"updated app {wanted['name']} ({', '.join(sorted(drift))})")
        updated += 1
    log(f"{created} created, {updated} updated, {unchanged} unchanged")


def main():
    try:
        base_url = os.environ["HOMARR_BASE_URL"]
        key_file = os.environ["HOMARR_API_KEY_FILE"]
        desired_file = os.environ["HOMARR_DESIRED_FILE"]
    except KeyError as missing:
        log(f"missing required environment variable {missing}")
        return 2

    api_key = load_key(key_file)
    if not api_key:
        return 0

    with open(desired_file, encoding="utf-8") as handle:
        document = json.load(handle)

    try:
        sync(Homarr(base_url, api_key), document["apps"])
    except RuntimeError as error:
        log(str(error))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
