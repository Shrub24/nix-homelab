#!/usr/bin/env python3
"""Refresh GeoPulse's coupled release pin and its two dependency hashes.

The backend and the frontend build from one upstream revision, so the batch
dispatches here through nix-update's update-script path instead of its standard
release discovery. The script runs from the repository root and writes only
`pkgs/geopulse/`. A recorded target is honoured through
`GEOPULSE_UPDATE_VERSION=<X.Y.Z>`; `--check` prints the newest stable release.
"""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.request import Request, urlopen

SOURCE = Path("pkgs/geopulse/source.nix")
PATCH = Path("pkgs/geopulse/patches/pkce.patch")
# Each derived output owns one dependency hash, which nix-update regenerates
# from the pinned revision: maven for the backend, npm for the frontend.
DERIVED_PACKAGES = ("geopulse-backend", "geopulse-frontend")

STABLE = re.compile(r"v(\d+\.\d+\.\d+)$")
RELEASES = "https://api.github.com/repos/tess1o/geopulse/releases?per_page=30"
ARCHIVE = "https://github.com/tess1o/geopulse/archive/{rev}.tar.gz"
COMMIT = "https://api.github.com/repos/tess1o/geopulse/commits/{tag}"


def fetch(url):
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "geopulse-update",
    }
    if token := os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"
    with urlopen(Request(url, headers=headers), timeout=60) as response:
        return json.load(response)


def newest_release():
    """Newest stable `X.Y.Z` release of the repository."""
    stables = []
    for release in fetch(RELEASES):
        if release.get("prerelease") or release.get("draft"):
            continue
        if match := STABLE.fullmatch(release["tag_name"]):
            version = match[1]
            stables.append((tuple(int(part) for part in version.split(".")), version))
    if not stables:
        raise ValueError("no stable vX.Y.Z release found")
    return max(stables)[1]


def tag_for(version):
    """The repository tag for a version, refusing anything but a stable one."""
    if STABLE.fullmatch(f"v{version}") is None:
        raise ValueError(f"{version} is not a stable X.Y.Z version")
    return f"v{version}"


def rev_for(tag):
    """The revision a tag points at."""
    return fetch(COMMIT.format(tag=tag))["sha"]


def capture(text, pattern):
    match = re.search(pattern, text, flags=re.MULTILINE)
    if match is None:
        raise ValueError(f"no pin matching {pattern!r} in {SOURCE}")
    return match[1]


def replace_one(text, pattern, replacement):
    result, count = re.subn(pattern, lambda _: replacement, text, flags=re.MULTILINE)
    if count != 1:
        raise ValueError(
            f"expected one pin matching {pattern!r} in {SOURCE}, found {count}"
        )
    return result


def prefetch(rev):
    """The hash the pin needs, and the unpacked revision to check the patch against."""
    prefetched = json.loads(
        subprocess.run(
            [
                "nix",
                "store",
                "prefetch-file",
                "--unpack",
                "--json",
                ARCHIVE.format(rev=rev),
            ],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    )
    return prefetched["hash"], Path(prefetched["storePath"])


def checked(argv, what, cwd=None):
    """Run a command whose failure must be visible, not a traceback."""
    result = subprocess.run(argv, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        for stream in (result.stdout, result.stderr):
            if stream.strip():
                print(stream.strip(), file=sys.stderr)
        raise ValueError(f"{what} failed")
    return result


def assert_patch_applies(tree, rev):
    """The PKCE patch is version-coupled, so a new pin has to still accept it.

    A revision the patch cannot apply to must fail here, in the candidate,
    rather than in a build. `nix store prefetch-file --unpack` leaves the
    unpacked revision in the store, where a dry run reports without writing.
    """
    checked(
        ["patch", "-p1", "--dry-run", "--force", "-i", str(PATCH.resolve())],
        f"{PATCH} no longer applies to {rev[:12]}",
        cwd=tree,
    )


def assert_source_hash():
    """Fail loudly when the prefetched hash is not the one the pin needs."""
    checked(
        ["nix", "build", "--no-link", ".#geopulse-backend.src"], "source hash check"
    )


def main():
    if "--check" in sys.argv[1:]:
        print(newest_release(), flush=True)
        return

    target = os.environ.get("GEOPULSE_UPDATE_VERSION") or newest_release()
    rev = rev_for(tag_for(target))

    text = SOURCE.read_text()
    version = capture(text, r'^  version = "([^"]+)";')
    pinned = capture(text, r'^    rev = "([^"]+)";')
    if (version, pinned) == (target, rev):
        print(f"geopulse-update: already at {target} ({rev[:12]})", flush=True)
        return

    if pinned == rev:
        # The tag names the revision already pinned: only the label changes.
        hash_value, tree = capture(text, r'^    hash = "([^"]+)";'), None
    else:
        hash_value, tree = prefetch(rev)

    text = replace_one(text, r'^  version = "[^"]+";', f'  version = "{target}";')
    text = replace_one(text, r'^    rev = "[^"]+";', f'    rev = "{rev}";')
    text = replace_one(text, r'^    hash = "[^"]+";', f'    hash = "{hash_value}";')
    SOURCE.write_text(text)
    print(f"geopulse-update: {version} -> {target} ({rev[:12]})", flush=True)

    # `.#` reads the Git index, so every edit has to reach it before anything
    # evaluates the flake: a stale index makes nix-update prefetch the previous
    # revision's dependencies and write back the hash it already had.
    checked(["git", "add", "-A"], "staging the edited pin")

    if tree is not None:
        assert_patch_applies(tree, rev)
        assert_source_hash()

    for name in DERIVED_PACKAGES:
        print(f"geopulse-update: regenerating the {name} dependency hash", flush=True)
        checked(
            ["nix-update", "--flake", "--version=skip", "--no-src", name],
            f"updating {name}",
        )
        checked(["git", "add", "-A"], "staging the regenerated hash")

    print(
        f"geopulse-update: source.nix at {target}, dependency hashes regenerated",
        flush=True,
    )


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        print(f"geopulse-update: {error}", file=sys.stderr)
        sys.exit(1)
