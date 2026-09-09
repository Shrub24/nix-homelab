# Temporary import-tree exclusion boundary (dendritic stage 1, design DS-1).
#
# These directories under modules/ still contain plain NixOS leaves that would
# fail evaluation if discovered as flake-parts modules. Host assembly under
# hosts/ (i.e. modules/hosts) is excluded too: host registry records import
# those leaves explicitly (DS-3). Remove entries as each directory is converted
# to aspect contributors.
#
# Stage 2 removed `core` and `profiles` after every leaf under those
# directories became a foundation-aspect contributor or was relocated/deleted
# (dendritic-stage-2-foundation-aspects FND-6).
#
# Contract: tests enumerate this list; entries must exist as directories.
[
  "applications"
  "hosts"
  "providers"
  "services"
  "shared"
  "storage"
]
