# docs-mcp-server deployment modalities

Status: decided and implemented in `modules/knowledge/docs-mcp.nix` +
`modules/knowledge/_docs-mcp/default.nix`. Recorded here because the choice was between a pure-Nix
build and a container, and the reasons are not visible from the module alone.

## Options considered

| Option | Verdict |
| --- | --- |
| nvfetcher + `buildNpmPackage` from the GitHub source | Rejected for now. The repo does carry `package-lock.json`, so it is technically reachable, but the build needs Node ≥ 22 plus a native toolchain (`better-sqlite3`, `tree-sitter`), and the upstream image build explicitly prunes ~190 MB of musl-linked native packages that npm installs unconditionally. That is a new, permanently-maintained packaging surface for a service the fleet only consumes. |
| `bunx @arabold/docs-mcp-server@<version>` at runtime | Rejected. This is what the workstation's dotfiles service does (`modules/agents/docs-mcp.nix`), but it resolves the package on every start, so the running version is not the locked one and a first start needs npm reachability. Reproducibility is exactly what moving to the homelab is meant to buy. |
| Digest-pinned OCI image | Chosen. Upstream publishes `ghcr.io/arabold/docs-mcp-server` from its release workflow; the container is self-describing (store `/data`, config `/config`, uid 1000) and matches the modality the fleet already uses for karakeep, phoenix, and bifrost. |
| nixpkgs package or NixOS module | Does not exist; nixpkgs carries no `docs-mcp-server` package. |

## Consequences of the container choice

- The store and config are bind mounts under `/srv/data/docs-mcp`, owned by uid/gid 1000 as the image
  requires, so state stays on the fleet's data root and out of the container layer.
- Protocol detection has to be overridden: upstream falls back to stdio whenever stdin is not a TTY,
  which is always the case under podman, so the module sets the HTTP protocol explicitly.
- The database records the embedding model name and dimension it was built with, and the server
  refuses to start when they differ (`EmbeddingModelChangedError`). A migrated database therefore has
  to be renamed in the same step that points the service at the fleet's embedding alias — both names
  front OpenRouter `qwen/qwen3-embedding-8b` at 4096 dimensions, so the vectors stay comparable.
- SQLite cannot be copied coherently while the service writes, so the backup contract exports the
  store with `sqlite3 .backup` and lets restic capture the export, rather than capturing live files.
