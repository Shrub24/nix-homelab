# Temporary import-tree exclusion boundary (dendritic stage 1, design DS-1).
#
# These directories under modules/ still contain plain NixOS leaves that would
# fail evaluation if discovered as flake-parts modules. Host assembly under
# hosts/ (i.e. modules/hosts) is excluded too: host registry records import
# those leaves explicitly (DS-2/DS-3). Remove entries as each directory is
# converted to aspect contributors.
#
# Stage 2 removed `core` and `profiles` after every leaf under those
# directories became a foundation-aspect contributor or was relocated/deleted
# (dendritic-stage-2-foundation-aspects FND-6). Stage 5 removed `shared` and
# `storage` (dendritic-stage-5-shared-source-contributors S5-6). Stage 7
# removed `applications` and `providers` after every implementation leaf moved
# beside its discovered concern owner (dendritic-stage-7-placement-aspects
# S7-8); both directories are deleted, not renamed into replacement entries.
#
# `hosts` stays excluded until Stage 8 converts hosts into discovered
# contributors. `services` remains the explicit incremental-conversion backlog:
# its leaves are reachable only through the aspect that imports them.
#
# Contract: tests enumerate this list; entries must exist as directories.
[
  "hosts"
  "services"
]
