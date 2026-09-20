# Import-tree exclusion boundary (dendritic stage 1, design DS-1).
#
# These directories under modules/ still contain plain NixOS leaves that would
# fail evaluation if discovered as flake-parts modules. Remove entries as each
# directory is converted to aspect contributors.
#
# Stage 2 removed `core` and `profiles` after every leaf under those
# directories became a foundation-aspect contributor or was relocated/deleted
# (dendritic-stage-2-foundation-aspects FND-6). Stage 5 removed `shared` and
# `storage` (dendritic-stage-5-shared-source-contributors S5-6). Stage 7
# removed `applications` and `providers` after every implementation leaf moved
# beside its discovered concern owner (dendritic-stage-7-placement-aspects
# S7-8); both directories are deleted, not renamed into replacement entries.
#
# Stage 8 (dendritic-stage-8-host-identity-contracts task 2.3) removed `hosts`:
# every host is now a discovered contributor (modules/hosts/<host>/default.nix)
# declaring its own typed nixos.hosts record, with hardware facts and private
# NixOS fragments under underscore paths.
#
# The post-Stage-8 services-tree conversion removed `services`: every leaf
# became a discovered aspect file, a sibling contributor of its owner aspect,
# or an underscore-private helper beside that owner, and the PostgreSQL
# mechanism became the aspect pair `modules/database/postgres.nix` + `postgres/_consumer.nix` (sibling pair).
# The list is now empty; the file stays as the documented, inspectable
# boundary — re-add an entry only when a genuinely transitional plain-module
# directory appears.
#
# Contract: tests enumerate this list; entries must exist as directories.
[ ]
