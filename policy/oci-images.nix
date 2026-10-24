# Canonical OCI image refs (registry/repo:tag@sha256:digest).
# Service modules import these; Renovate keeps the full ref current.
{
  tagr = "ghcr.io/suitux/tagr:1.16.1@sha256:d2419831a215e3c1fae9aba9b04463394b2ba7b558deeec936218338e9186087";

  trek = "docker.io/mauriceboe/trek:latest@sha256:be0817b4ff576c57ce98d6a167b41f0638c1990dbeb0b8e7e7dcb39aba1c8812";

  doclingServe = "quay.io/docling-project/docling-serve:v1.38.1@sha256:c632ab38b69a923c33b4d0c7dea4b8d3b8128bd19b94f710c3ee7db89dde8d34";

  paperlessGpt = "ghcr.io/icereed/paperless-gpt:latest@sha256:d668941a829552cc0eddbc7c22506b3480dfbf61bd0d6eae881ad9fcfe2de70c";

  karakeepWeb = "ghcr.io/karakeep-app/karakeep:0.34.1@sha256:69ae5315c618b7c14c1af3e34c6e211acdb231793af424ecd1cab0b70691d987";

  karakeepChrome = "ghcr.io/karakeep-app/karakeep-chrome:156.0.8078.47-r1@sha256:4ad61127638dd27bfe685222787c5780dd1d083d23a7658c39af657775814c44";

  karakeepMeilisearch = "getmeili/meilisearch:v1.55.0@sha256:ff546679970126f8822e15d1b6a06bfbff1f2ce2e43f810cfb5258012f92de5c";

  audiomuse = "ghcr.io/neptunehub/audiomuse-ai:3.6.4@sha256:811f1f0bd0de97a1b4ab6601898297010da18fc957312b1ed3bb62990683630c";

  redis7Alpine = "docker.io/library/redis:8-alpine@sha256:0bf6577d7774e592b29d093e3ac9390eb91e13d72c21e506afce736de5e0eeb0";

  guacd = "docker.io/guacamole/guacd:1.6.0@sha256:8974eaa9ba32f713daf311e7cc8cd7e4cdfba1edea39eed75524e78ef4b08f4f";

  termix = "ghcr.io/lukegus/termix:release-2.1.0@sha256:52e45c1ea3fb85be5b3ade5ff42eed0946fe81131cbd834f6960e00797f17f86";

  omniroute = "ghcr.io/shrub24/omniroute:sha-sha-25965d5@sha256:12d7cf563a5de174f13c32fded4e58c35f841f2a94d97b7af024323a82c78674";

  langfuse = "docker.langfuse.com/langfuse/langfuse:4.43.0@sha256:d6165b4ef72027c128c6132a4d87a4643945f6ba01f9cb5d6e4af7e5e3bf5316";

  langfuseWorker = "docker.langfuse.com/langfuse/langfuse-worker:4.43.0@sha256:59be62f49978b656b27656cba7314097c6e9ca8d63ed6ef6f66394f6aaeede1b";

  docsMcpServer = "ghcr.io/arabold/docs-mcp-server:3.4.0@sha256:9e54b534cc2f34610a03d4d2e40b18a10fc71365a8e3148fe4a48dcb6eb0089b";

  hindsight = "ghcr.io/vectorize-io/hindsight:1.1.0-slim@sha256:fbc37d194bce007b6cce2fd9f66cd7f8c050bd18b80e662090a92835d9cb191d";

  tududi = "docker.io/chrisvel/tududi:1.9.7@sha256:bd1191e04b1c4b32fb8fa68199bd6982520f89eed9445cc91f886fbbebd2086c";

  # Multi-arch manifest index, including the OCI host's aarch64-linux platform.
  homarr = "ghcr.io/homarr-labs/homarr:v2.9.0@sha256:9e866425f4e2bcd03b662f7a7a04b6c180f1de95a3812868fd0a306df026e08c";

  # Home Assistant's own image: the container is the installation method upstream supports (ADR-0012),
  # and the multi-arch index keeps the pin valid on either architecture.
  homeAssistant = "ghcr.io/home-assistant/home-assistant:2026.10.4@sha256:23f4dfbb69ce76315dbc4de7915504f1c2dcecd7ca2648113a493a385972e133";

  # Multi-arch index digest: the arm64 manifest is selected on oci-melb-1.
  inboxZero = "ghcr.io/elie222/inbox-zero:2.30.0@sha256:e9970c499a79b8a15bbab21363d1b87ea247c75b2721f036c7cee0e2c78d1fcc";

  # Latitude ships one release tag across all six images, so they move together; the digests
  # are multi-arch index digests, valid on both architectures.
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
