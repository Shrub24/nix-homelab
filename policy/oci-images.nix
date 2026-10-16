# Canonical OCI image refs (registry/repo:tag@sha256:digest).
# Service modules import these; Renovate keeps the full ref current.
{
  tagr = "ghcr.io/suitux/tagr:1.14.0@sha256:1a3eccec237e08c30b6a35a5084c3974082509c1a74a6b3459489c2429a2a414";

  trek = "docker.io/mauriceboe/trek:latest@sha256:90da7246206646ca76ad0b46780d582612d6523376a7dd369d7eca39c5d939b0";

  doclingServe = "quay.io/docling-project/docling-serve:v1.37.0@sha256:f11cd52d4cc9251e76f7c29e929a61d24588d7c1333133edb6ca5d55b9b40899";

  paperlessGpt = "ghcr.io/icereed/paperless-gpt:latest@sha256:d668941a829552cc0eddbc7c22506b3480dfbf61bd0d6eae881ad9fcfe2de70c";

  karakeepWeb = "ghcr.io/karakeep-app/karakeep:0.33.2@sha256:b069e4307dec06ea06d16989c6861c30a1ff208568be44ed5fb5d422cd3e950c";

  karakeepChrome = "ghcr.io/karakeep-app/karakeep-chrome:151.0.7922.47-r1@sha256:5b19bbb160e9ff60681a3abd97e1c4ec9f64212301410de658c3900ab7ef31e7";

  karakeepMeilisearch = "getmeili/meilisearch:v1.55.0@sha256:ff546679970126f8822e15d1b6a06bfbff1f2ce2e43f810cfb5258012f92de5c";

  audiomuse = "ghcr.io/neptunehub/audiomuse-ai:3.6.4@sha256:811f1f0bd0de97a1b4ab6601898297010da18fc957312b1ed3bb62990683630c";

  redis7Alpine = "docker.io/library/redis:7-alpine@sha256:858f009f9709ce576febc734aa78b8f6d624b82571f9ddb6bda4377c833b3499";

  guacd = "docker.io/guacamole/guacd:1.6.0@sha256:8974eaa9ba32f713daf311e7cc8cd7e4cdfba1edea39eed75524e78ef4b08f4f";

  termix = "ghcr.io/lukegus/termix:release-2.1.0@sha256:52e45c1ea3fb85be5b3ade5ff42eed0946fe81131cbd834f6960e00797f17f86";

  omniroute = "ghcr.io/shrub24/omniroute:sha-sha-25965d5@sha256:12d7cf563a5de174f13c32fded4e58c35f841f2a94d97b7af024323a82c78674";

  langfuse = "docker.langfuse.com/langfuse/langfuse:4.63.0@sha256:67f48d12a190e4ad585249c75ae1ce172b449de3dbbe7486b8179cd28e21408e";

  langfuseWorker = "docker.langfuse.com/langfuse/langfuse-worker:4.63.0@sha256:ca32a8fb2a214c7b5f42dd9c540c8072e41db659cb621f317911ce695ad6bca2";

  docsMcpServer = "ghcr.io/arabold/docs-mcp-server:3.2.1@sha256:f7423b05d1ce2cced618b1cd3d8734aff88f675d6a05ba198d4667970afd5757";

  hindsight = "ghcr.io/vectorize-io/hindsight:0.10.3-slim@sha256:c0bd6122a1d0d62dc5094ce43150780a28a96ec70109b44c688210231a5ac33a";

  # Latitude ships one release tag across all six application images, so the
  # versions move together; digests are the multi-arch index digests, which is
  # what keeps the pins valid on both aarch64 and x86_64 hosts.
  latitude = {
    web = "docker.io/latitudedata/web:0.3.124@sha256:b63ab7fb323732efea294d2fdffd14a91242e471478fae550578c786ef4a39ed";
    api = "docker.io/latitudedata/api:0.3.124@sha256:9ad756af5d43c8ac1f72ee6d7a1f3cfad0949d912bb1e677b4c5d8ce65c403ae";
    ingest = "docker.io/latitudedata/ingest:0.3.124@sha256:35915bd49b686a50fc6ecf2bcc2b0b775df22a9a3091b77cc6fb1e170f058cb5";
    workers = "docker.io/latitudedata/workers:0.3.124@sha256:13ed197736b42d42e6cc3c772d0368f706146f5db14437f4c23249032d30f4d8";
    workflows = "docker.io/latitudedata/workflows:0.3.124@sha256:c3130fc36dafd0fe4585d858143d6627ef56cfb6233b08aac4c31cd43a43dae9";
    migrations = "docker.io/latitudedata/migrations:0.3.124@sha256:8751f8a7a078eb2351c35db3eab9e70a0752ddccb33c2dfec1063b1e9a0b4988";
  };

  latitudeTemporal = "docker.io/temporalio/auto-setup:1.29.7@sha256:f14912b699cf73015ad5c4fc18d522d4b014db90e794039214dfb7c022c2644f";
}
