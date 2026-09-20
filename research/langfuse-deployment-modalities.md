# Langfuse self-hosting on the homelab — deployment modalities

Status: research brief, no decision taken. Target host: `home-forge` (x86_64, 32 GB RAM,
NVMe root + `/srv/storage`), replacing the current Arize Phoenix container.

## Recommendation

Deploy Langfuse as a **hybrid declarative stack**: native nixpkgs services for the infrastructure
roles (PostgreSQL from the fleet substrate, ClickHouse, Redis) plus **digest-pinned containers for the
two Langfuse application roles** (web, worker). Point blob storage at the fleet's existing Cloudflare
R2 endpoint instead of running MinIO, and expose the web role tailnet-only.

Rationale in one line: the application has no nixpkgs package and moves fast, while every
infrastructure role it needs *is* packaged natively with declarative configuration — so the hybrid
buys reproducibility where drift is expensive (databases) and follows upstream's tested images where
packaging would be a project of its own (the Next.js web app and the ingestion worker).

## What self-hosting actually requires (evidence)

Upstream `docker-compose.yml` on `main` (v4 line) runs exactly six services:

| Category | Service in upstream compose | Image |
| --- | --- | --- |
| App | `langfuse-web` | `docker.langfuse.com/langfuse/langfuse:4` |
| App | `langfuse-worker` | `docker.langfuse.com/langfuse/langfuse-worker:4` |
| Infra | `clickhouse` | `docker.io/clickhouse/clickhouse-server:25.12` |
| Infra | `redis` | `docker.io/redis:7` |
| Infra | `postgres` | `docker.io/postgres:${POSTGRES_VERSION:-17}` |
| Infra | `minio` | `cgr.dev/chainguard/minio` |

- **ClickHouse is mandatory and irreplaceable**: "Langfuse cannot be self-hosted without using
  ClickHouse as the main storage solution for traces, observations, and scores. All self-hosted
  deployments must include a ClickHouse instance." No alternative OLAP backend exists.
- **S3-compatible blob storage is required** in three roles: `LANGFUSE_S3_EVENT_UPLOAD_*`,
  `LANGFUSE_S3_MEDIA_UPLOAD_*`, `LANGFUSE_S3_BATCH_EXPORT_*`.
- **v4 minimum infrastructure versions**: ClickHouse ≥ 25.12 (26.4 recommended), PostgreSQL ≥ 15
  (16 recommended), Redis ≥ 7.0 (7.2 recommended). v4 changed the ClickHouse *data model*
  (`events_full` / `events_core`) but **not** the component list.
- **Documented sizing**: "We recommend that you use at least 4 cores and 16 GiB of memory, e.g. a
  t3.xlarge on AWS … As observability data tends to be large in volume, choose a sufficient amount of
  storage, e.g. 100GiB." On a 32 GB host shared with omniroute, hindsight, and the music stack this is
  the dominant new consumer, not a footnote.
- Upstream was acquired by ClickHouse in January 2026; the core stays MIT-licensed and self-hostable.
- Network posture upstream recommends: only `langfuse-web` and `minio` reachable from outside.

## Option matrix

| # | Modality | What it means here | Trade-offs |
| --- | --- | --- | --- |
| **A** | **Hybrid declarative (recommended)** | Native `services.clickhouse`, `services.redis`, Postgres from the fleet substrate; containers for `langfuse-web` + `langfuse-worker`; R2 (or `services.minio`) for blobs | Declarative config for every stateful role; two pinned app images to track; ClickHouse config is XML-in-Nix but nixpkgs gives typed `serverConfig`/`usersConfig`; upstream pins 25.12 while nixpkgs ships 26.8 LTS — we would run ahead of upstream's tested pin |
| B | Pure compose translation | All six services as `virtualisation.oci-containers` with digest pins, mirroring upstream one-to-one | Closest to upstream's tested combination and upgrade path; but brings a second PostgreSQL and a MinIO into a fleet that already runs Postgres natively and has R2 — two extra stateful components whose backup stories are container-shaped instead of the repo's export-first contracts |
| C | All-native | Package Langfuse itself and run web/worker as systemd units | Best declarative story in theory; in practice a Next.js monorepo with Prisma + ClickHouse migrations, released frequently — a permanent packaging burden and a guaranteed lag behind security fixes. No nixpkgs package or module exists (only the Python SDK), and the community NixOS modules that do exist are unmaintained experiments (`htelsiz/langfuse-nix` ★0, last push 2026-04, v3-era; `l4b4r4b4b4/nix-ai` ★0) |
| D | Langfuse Cloud | Managed instance, no local components | Cheapest in effort and removes 4 stateful services; but trace content leaves the tailnet, and the homelab's stated posture is private-first. Listed as the baseline, not the plan |

**Why not MinIO (in options A or B):** the fleet already has an S3-compatible endpoint
(`policy/globals.nix` `s3.endpoint`, Cloudflare R2) with credentials and a restic precedent, so blob
storage can be off-host and durable instead of a fourth stateful service. Langfuse speaks S3 with
`…_FORCE_PATH_STYLE=true` and `…_REGION=auto`. Keeping MinIO as the local alternative is fine —
`services.minio` exists in nixpkgs with `dataDir`, `region`, `accessKey`, `secretKey` — but it adds
state, an admin console to expose, and a second backup path for bytes that R2 already stores.

## Per-component plan (option A)

| Component | Modality | Source | Version | State | Backup | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| PostgreSQL | native, fleet substrate consumer | `services.postgresql` via `postgres-shared` | 17 (≥ 16 recommended) | authoritative metadata: projects, users, prompts, datasets, scores config | export-first logical dump (existing contract) | New `langfuse` consumer + role; verify whether Langfuse needs extra Postgres extensions and register them with the substrate's per-consumer extension contract |
| ClickHouse | native | nixpkgs `services.clickhouse` (`clickhouse` 26.8.2.7-lts) | ≥ 25.12 required, 26.4 recommended — nixpkgs is newer | traces, observations, scores (the bulk of the data) | `ALTER TABLE … FREEZE` + copy of the shadow partition, or accept trace data as regenerable and rely on retention TTLs | Single-node (`CLICKHOUSE_CLUSTER_ENABLED=false`); needs the grants from Langfuse's ClickHouse user-permissions list, including a few `system.*` tables in v4 |
| Redis | native | nixpkgs `services.redis` | 7.x | queue + cache only | none needed (no durable state by design) | Loopback-bound; persistence can stay off |
| Blob storage | R2 (no local component) | Cloudflare R2 via `policy/globals.nix` endpoint | — | event/media/batch-export blobs | R2's own durability | Alternative: native `services.minio` if locality is preferred |
| `langfuse-web` | container, digest-pinned | `docker.langfuse.com/langfuse/langfuse:4.x@sha256:…` | v4 line | none (config via env) | none | Serves UI, ingestion API, and the OTLP endpoint; the only role that needs tailnet reachability |
| `langfuse-worker` | container, digest-pinned | `docker.langfuse.com/langfuse/langfuse-worker:4.x@sha256:…` | v4 line | none | none | Drains the Redis queue into ClickHouse; no inbound ports |

Both application containers need loopback access to ClickHouse, Redis, and Postgres. Host networking
is the shape that keeps that access from widening anything (below).

## Networking pattern for containers on this fleet

Picking the container's network mode trades two different security axes, and which mode wins depends
on what the stack talks to:

- **Namespace isolation** (what the container can touch): a user-defined bridge wins. A host-network
  container shares the host network namespace and can reach every loopback service on the box.
- **Firewall exposure** (what the network can touch): host networking wins. Published ports bypass
  the NixOS firewall — nixpkgs says so verbatim: "Publishing a port bypasses the NixOS firewall. If
  the port is not supposed to be shared on the network, make sure to publish the port on localhost
  only." A host-network container's listeners are ordinary host sockets that the firewall filters
  (default-deny, `tailscale0` trusted → tailnet-only).

The pattern classes, updated accordingly:

| Class | When | Shape | Notes |
| --- | --- | --- | --- |
| A′ | must reach loopback-bound native services, isolation matters (Langfuse-class stacks) | user-defined bridge with a reserved subnet (e.g. 10.89.20.0/24, gateway 10.89.20.1); native services add the gateway to `listen_addresses`/bind config and the subnet enters their ACLs (the Postgres substrate's per-consumer `allowedCIDRs`, ClickHouse users, Valkey bind); web published as `127.0.0.1:H:C` and fronted by Caddy | buys namespace isolation at the cost of widening native binds and imperative ClickHouse XML |
| A | must reach loopback-bound native services, and the stack's config is imperative anyway | `extraOptions = [ "--network=host" ]`, port as an explicit module option | firewall still applies; loses namespace isolation |
| B | self-contained container set, no host service dependency | `containers.<name>.networks = [ "<stack>" ]` + oneshot network creation (`audiomuse.nix` shape); publish `127.0.0.1:H:C`, never bare `0.0.0.0` | DNS by container name; published ports bypass the firewall, so the bind address is the boundary |
| C | an external proxy or cloud security group is the boundary | bare `ports = [ "0.0.0.0:H:C" ]` | firewall bypassed on every interface — explicit exception, never a default |

Supporting facts: rootful podman (what `virtualisation.oci-containers` uses) defaults to a netavark
bridge, and the default `podman` network is "memory-only [and] does not support dns resolution because
of backwards compatibility with Docker", so name resolution needs a user-defined network;
`host.containers.internal` resolves to the container's gateway address, not host loopback, so it
cannot reach a loopback-bound native service without widening that service's bind and ACLs; there is
no Quadlet module in nixpkgs, so `oci-containers` remains the declarative path; rootless pasta/slirp
caveats do not apply.

Consequence for Langfuse: class A′ (bridge). The deciding fact is that the ClickHouse configuration
is imperative XML in either shape, so the "declarative-only" argument for class A does not exist on
this deployment — the bridge's isolation is bought with configuration that had to be written anyway.
Postgres, Valkey/Redis, and Caddy stay fully declarative in both shapes.
## Migrating off Arize Phoenix

- **There is no supported data migration.** Neither Langfuse's OTLP docs nor its self-hosting docs
  offer an importer from another tracing backend; Phoenix stores its own SQLite schema. Treat the
  change as re-instrumentation, not conversion.
- New instrumentation targets Langfuse's OTLP endpoint: `http://<host>:3000/api/public/otel`
  (signal-specific: `/api/public/otel/v1/traces`), Basic auth built from the project's public and
  secret keys, plus the header `x-langfuse-ingestion-version: 4`. OTLP/HTTP with protobuf or JSON is
  supported; **gRPC is not** — Phoenix's gRPC OTLP port (4317) has no direct equivalent.
- Practical sequence: stand Langfuse up, mint a project key pair, point the OTel exporters/Collector
  at it, then let the Phoenix database age out under its existing retention job and drop the
  container. Keeping Phoenix running read-only during the overlap costs one container and gives a
  side-by-side comparison window.
- Langfuse's ingestion is asynchronous by design (web → Redis → worker → ClickHouse), so a healthy
  ingest response does not mean the trace is queryable yet; expect a short lag in verification.

## NixOS-specific sharp edges

- **ClickHouse config surface**: nixpkgs exposes `services.clickhouse.serverConfig` (YAML 1.1 → XML)
  and `usersConfig`, so grants and profiles stay declarative; anything not modelled needs
  `extraServerConfig`/`extraUsersConfig` raw XML. State path and service user come from the module —
  check that they land under the host's data root before enabling backups.
- **Version skew vs upstream**: Langfuse tests against ClickHouse 25.12/26.4; nixpkgs unstable ships
  26.8 LTS. Running ahead is usually fine for an LTS, but it is *our* choice, not upstream's tested
  combination — pin the nixpkgs revision and treat a ClickHouse major bump as an upgrade event.
- **Redis vs Valkey**: nixpkgs has no `services.valkey` option in the indexed option set; the Redis
  module satisfies Langfuse's ≥ 7.0 requirement as-is. Not worth a wrapper.
- **MinIO, if chosen**: `services.minio` exists with `rootCredentialsFile`/`accessKey`/`secretKey`;
  note upstream's compose uses Chainguard's MinIO build rather than the upstream image, so the
  console/feature surface may differ from what the Langfuse docs assume.
- **File descriptors and memory**: ClickHouse wants a raised `LimitNOFILE` and dislikes memory
  pressure; on a shared 32 GB box the ClickHouse container/service budget is the first thing to tune
  and the first thing to OOM.
- **Digest pinning on a non-Docker-Hub registry**: images come from `docker.langfuse.com`; confirm
  Renovate can track that registry for digest bumps, otherwise the pin is manual.
- **Secrets**: the stack needs Postgres credentials, ClickHouse credentials, MinIO/R2 keys, and a
  Langfuse encryption key + NextAuth secret; that is one new `secrets/services/langfuse.yaml` scoped
  to the host, rendered into environment files by the service module.

## Open questions

- Which host actually runs this? `home-forge` has the RAM but shares it with the music stack,
  omniroute, and hindsight; the documented "4 cores / 16 GiB" recommendation assumes the box is mostly
  Langfuse's.
- Retention policy: what should ClickHouse keep by default (TTL) — and does any of it need backing up
  at all, or are traces accepted as regenerable?
- Does Phoenix stay in the fleet for anything (the OTLP gRPC port has no Langfuse equivalent), or is
  the `phoenix` aspect and its pruning timer retired outright?
- Does Langfuse need the Postgres extensions (`pg_trgm` / `uuid-ossp` class) that its own compose
  image installs? Verify against the Prisma schema during implementation and register them through
  the substrate's per-consumer extension contract rather than hand-editing the instance.

## Sources

- `https://raw.githubusercontent.com/langfuse/langfuse/main/docker-compose.yml` — component list,
  images, S3 roles (fetched 2026-09-20).
- `https://langfuse.com/self-hosting/deployment/docker-compose` — recommended 4 cores / 16 GiB /
  ~100 GiB, only web + minio need external reachability.
- `https://langfuse.com/self-hosting/deployment/infrastructure/clickhouse` — ClickHouse mandatory,
  no alternative OLAP, v4 version floor and user permissions.
- `https://langfuse.com/self-hosting/upgrade/upgrade-guides/upgrade-v3-to-v4` — v4 minimum versions,
  unchanged component list, data-model change.
- `https://langfuse.com/docs/opentelemetry/get-started` — OTLP endpoint paths, Basic auth, ingestion
  version header, no gRPC, endpoint introduced in v3.22.0.
- nixpkgs (nixos-unstable index): `clickhouse` 26.8.2.7-lts; `services.clickhouse.*`,
  `services.minio.*` modules present; no `langfuse` server package or module (only
  `python3*Packages.langfuse`, the SDK); no `services.valkey` options.
- Community modules: `htelsiz/langfuse-nix` (★0, v3-era, last push 2026-04-27),
  `l4b4r4b4b4/nix-ai` (★0) — neither is a dependency to adopt.
