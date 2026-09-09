# Temporary import-tree exclusion boundary (dendritic stage 1, design DS-1).
#
# These directories under modules/ still contain plain NixOS leaves that would
# fail evaluation if discovered as flake-parts modules. Host assembly under
# hosts/ (i.e. modules/hosts) is excluded too: host registry records import
# those leaves explicitly (DS-3). Remove entries as each directory is converted
# to aspect contributors.
#
# Contract: tests enumerate this list; entries must exist as directories.
[
  "applications"
  "core"
  "hosts"
  "profiles"
  "providers"
  "services"
  "shared"
  "storage"
]
