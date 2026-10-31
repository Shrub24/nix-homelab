# Tasks

## 1. Source policy

- [x] 1.1 Add `policy/assets.nix` for the existing bucket, public address and source choices; vendor Actual and Homarr SVGs plus consumed vector branding with upstream attribution. Verify each source parses as SVG and policy evaluates without network access.

## 2. Publication mechanism

- [x] 2.1 Add declaration-only registration and the `assets-publisher` aspect with generated per-object units, existing common-secret wiring, explicit refresh helper and a runtime publisher. Add focused checks for changed/unchanged publication, content-type correction, invalid/failed reads and storage errors preserving old content, and registration isolation. Document the mechanism and operator refresh/removal commands. Verify focused publisher checks and a standalone module evaluation.

## 3. Production integration

- [x] 3.1 Register Actual, Homarr and Karakeep with their runtime owners, register vector brand assets on the identity host, select publishers explicitly, and switch only managed Authentik icons to R2 URLs. Verify the three host configurations evaluate and the blueprint builds; verify registration removal does not select a publisher implicitly. Update the outstanding-work tracker and relevant architecture placement documentation.

- [x] 3.2 Extend the approved pilot to the remaining application tiles: Beszel, BookOrbit, GeoPulse, Grafana, Langfuse, Memos, Paperless, Termix and tududi. Verify real local image sources or reviewed vendored SVGs with attribution, service-owned registration and per-host publication. Check supported native favicon customisation without patches or proxy overrides, and document any operator-only settings. Verify host evaluations, blueprint rendering and focused publisher checks; update the source inventory.

## 4. Integration acceptance

- [ ] 4.1 Run formatting, focused asset and identity checks and the repository gates on the final tree. Verify a clean bounded review and exit 0 from the gates; do not claim live publication from these checks.
- [ ] 4.2 Pilot approved by the operator; after the expanded rollout is deployed, verify unauthenticated asset responses, explicit content types, a second publication doing no writes, preserved objects after a failed source, and dashboard appearance. Record the actual live acceptance; implementation alone does not complete this task.

## Workflow follow-up

- Archive only after live acceptance. Object withdrawal and manual wallpaper uploads remain operator actions; no automatic pruning or infrastructure adoption is part of this change.
