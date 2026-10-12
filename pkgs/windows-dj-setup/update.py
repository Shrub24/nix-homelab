#!/usr/bin/env python3
"""Refresh windows-dj-setup's two coupled upstream pins.

WinFsp and Mesa dist-win move in one derivation, so the batch dispatches here
through nix-update's update-script path rather than its standard release
discovery. The script is run from the repository root and writes only
pkgs/windows-dj-setup/; a recorded target per upstream is honoured through
WINDOWS_DJ_SETUP_UPDATE_VERSION and WINDOWS_DJ_SETUP_MESA_VERSION.
"""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.request import Request, urlopen

FILE = Path("pkgs/windows-dj-setup/default.nix")

# WinFsp tags are `v2.1`; the stable release version is in the MSI asset name.
WINFSP_ASSET = re.compile(r"winfsp-([0-9]+\.[0-9]+\.[0-9]+)\.msi")
MESA_ASSET = re.compile(r"mesa3d-([0-9]+\.[0-9]+\.[0-9]+)-release-msvc\.7z")

WINFSP_RELEASES = "https://api.github.com/repos/winfsp/winfsp/releases?per_page=30"
MESA_RELEASES = (
    "https://api.github.com/repos/pal1000/mesa-dist-win/releases?per_page=30"
)


def fetch(url):
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "windows-dj-setup-update",
    }
    if token := os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"
    with urlopen(Request(url, headers=headers), timeout=60) as response:
        return json.load(response)


def select(releases, asset, target=None):
    """Newest stable (version, download url) for one upstream."""
    candidates = []
    for release in releases:
        if release.get("prerelease") or release.get("draft"):
            continue
        for entry in release.get("assets", []):
            match = asset.fullmatch(entry["name"])
            if match is None:
                continue
            version = match[1]
            if target is not None and version != target:
                continue
            candidates.append(
                (
                    tuple(int(part) for part in version.split(".")),
                    version,
                    entry["browser_download_url"],
                )
            )
    if not candidates:
        wanted = f" for target {target}" if target else ""
        raise ValueError(f"no stable release matching {asset.pattern}{wanted}")
    _, version, url = max(candidates)
    return version, url


def prefetch(url):
    """SRI sha256 for a fetched file, the form the pinned fetchurl calls use."""
    digest = subprocess.run(
        ["nix-prefetch-url", url], check=True, capture_output=True, text=True
    ).stdout.strip()
    return subprocess.run(
        ["nix", "hash", "convert", "--hash-algo", "sha256", "--to", "sri", digest],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def replace_one(text, pattern, replacement):
    result, count = re.subn(pattern, lambda _: replacement, text, flags=re.MULTILINE)
    if count != 1:
        raise ValueError(f"expected one pin matching {pattern!r}, found {count}")
    return result


def replace_source(text, attr, url, digest):
    pattern = re.compile(
        rf'({attr} = fetchurl \{{\n    url = ")[^"]+(";\n    hash = ")[^"]+(";)'
    )
    result, count = pattern.subn(
        lambda match: f"{match[1]}{url}{match[2]}{digest}{match[3]}", text
    )
    if count != 1:
        raise ValueError(f"expected one {attr} pin, found {count}")
    return result


def main():
    winfsp_version, winfsp_url = select(
        fetch(WINFSP_RELEASES),
        WINFSP_ASSET,
        os.environ.get("WINDOWS_DJ_SETUP_UPDATE_VERSION"),
    )
    if "--check" in sys.argv[1:]:
        # The check reports the version carrier only; nothing is fetched or written.
        print(winfsp_version, flush=True)
        return

    mesa_version, mesa_url = select(
        fetch(MESA_RELEASES),
        MESA_ASSET,
        os.environ.get("WINDOWS_DJ_SETUP_MESA_VERSION"),
    )
    print(
        f"windows-dj-setup-update: winfsp {winfsp_version}, mesa {mesa_version}",
        flush=True,
    )

    text = FILE.read_text()
    text = replace_one(
        text, r'^  version = "[^"]+";', f'  version = "{winfsp_version}";'
    )
    text = replace_source(text, "winfspSrc", winfsp_url, prefetch(winfsp_url))
    text = replace_source(text, "mesaSrc", mesa_url, prefetch(mesa_url))
    FILE.write_text(text)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"windows-dj-setup-update: {error}", file=sys.stderr)
        sys.exit(1)
