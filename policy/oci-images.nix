# Canonical OCI image refs (registry/repo:tag@sha256:digest).
# Service modules import these; Renovate keeps the full ref current.
{
  tagr = "ghcr.io/suitux/tagr:1.19.0@sha256:234079c268277e6299f7ca679da51e04f8b7686c15a3369f3013bc78aa6aa383";

  trek = "docker.io/mauriceboe/trek:latest@sha256:9ae862e870f0ebdbc724125a78b5a1cfd447c5e6965536acbc818bbdab083ede";

  doclingServe = "quay.io/docling-project/docling-serve:v1.40.0@sha256:c4a68d2872170bb06f91a6a9523fc89a2c9ff74c05c69022f8a1e5d23c822c92";

  paperlessGpt = "ghcr.io/icereed/paperless-gpt:latest@sha256:d668941a829552cc0eddbc7c22506b3480dfbf61bd0d6eae881ad9fcfe2de70c";

  karakeepWeb = "ghcr.io/karakeep-app/karakeep:0.35.0@sha256:6f7d32ef296ddf1fc7c67ff56b8a201b7006a6a47b92b202afee1338841b353d";

  karakeepChrome = "ghcr.io/karakeep-app/karakeep-chrome:156.0.8078.47-r1@sha256:4ad61127638dd27bfe685222787c5780dd1d083d23a7658c39af657775814c44";

  karakeepMeilisearch = "docker.io/getmeili/meilisearch:v1.58.0@sha256:cee0d2e31191594ff8e1651eb144aabd95b389a0bc3532327ecfb9ed91dffe7e";

  audiomuse = "ghcr.io/neptunehub/audiomuse-ai:3.7.5@sha256:096e68339f02de3dd0da6b5cade2e8e660093a448f70e84f650c782bfd307b4e";

  redis7Alpine = "docker.io/library/redis:8-alpine@sha256:5af80107c1eeecb484a2269b80a26d12bfa6521787da4663bd9f19f60a163483";

  guacd = "docker.io/guacamole/guacd:1.6.0@sha256:8974eaa9ba32f713daf311e7cc8cd7e4cdfba1edea39eed75524e78ef4b08f4f";

  termix = "ghcr.io/lukegus/termix:release-2.1.0@sha256:52e45c1ea3fb85be5b3ade5ff42eed0946fe81131cbd834f6960e00797f17f86";

  omniroute = "ghcr.io/shrub24/omniroute:sha-sha-25965d5@sha256:12d7cf563a5de174f13c32fded4e58c35f841f2a94d97b7af024323a82c78674";

  # Docker Hub directly: the langfuse.com proxy makes its own anonymous pulls and is
  # routinely rate-limited, which fails the unit rather than the pull.
  langfuse = "docker.io/langfuse/langfuse:4.88.0@sha256:272161cfd9e46934c693fbcd9ef160b1b7499a38bc4f836fac78cfa77eb46ccc";

  langfuseWorker = "docker.io/langfuse/langfuse-worker:4.88.0@sha256:952869378c3fbb322be31d3aeec85034125ff02e3ab26fbb30b3c38d4b25a944";

  docsMcpServer = "ghcr.io/arabold/docs-mcp-server:3.5.0@sha256:290580d5954755277f137a6bc4e064086d74c6d9c351f9b22fabe7c6d9ce39fa";

  hindsight = "ghcr.io/vectorize-io/hindsight:1.3.0-slim@sha256:d311bdee313f4be08d7f33ab7070ace35ebdec27985a6678acfc6ad186515b44";

  tududi = "docker.io/chrisvel/tududi:1.15.1@sha256:2b15d6b8ce51c61253cc9b588fa19abce6ce939565ff9683ffd56a1ab251b015";

  # GeoPulse ships the backend as a GraalVM native binary and the UI as nginx plus the built
  # SPA; both are multi-arch indexes, and `-native` targets armv8-a, which is Ampere A1.
  geopulseBackend = "docker.io/tess1o/geopulse-backend:2.4.0-native@sha256:019858a83b1662b179cb150dea3d7d267906b42d4e4ddefa19d99b97c91c7f72";

  geopulseUi = "docker.io/tess1o/geopulse-ui:2.4.0@sha256:d66d8cdb0dec3a6b4afd5b574eb51695b35938e0c8263f66c04d4c208c97f04b";

  # Multi-arch manifest index, including the OCI host's aarch64-linux platform.
  homarr = "ghcr.io/homarr-labs/homarr:v2.14.0@sha256:742940b00ed13e8649ddfd81532ad8f4140ad413ed0591f464ff6e4f7ff3c276";

  # Home Assistant's own image: the container is the installation method upstream supports (ADR-0012),
  # and the multi-arch index keeps the pin valid on either architecture.
  homeAssistant = "ghcr.io/home-assistant/home-assistant:2026.11.3@sha256:24e541ddae5818bf8eb27898b9ba00d0c344a655aa5097e9e9bd4b19356be847";

  # Temporary fork pin for system testing: a single arm64 manifest, which is what oci-melb-1
  # runs, with no multi-arch index. Revert to elie222/inbox-zero.
  inboxZero = "ghcr.io/shrub24/inbox-zero:systemone-test@sha256:ffffa35d230a922f1d7562d5d38c4cea11be158e17cd8b947ccabbcad453bbbf";

  # The frontend image serves the application; the API is a separate image.
  sparkyFitness = "docker.io/codewithcj/sparkyfitness:v1.12.1@sha256:c4e0769cece9ee70439b86cc457bed14d543edebab7502cd0c5d67174eb11f57";

  # Fork pin: upstream strips the issuer's trailing slash (`oidcEnvConfig.ts`), which Authentik's
  # issuer can never match (upstream #2772). Revert to codewithcj/sparkyfitness_server on its fix.
  sparkyFitnessServer = "ghcr.io/shrub24/sparkyfitness-backend:oidc-fix@sha256:2d2d650cf582f60eccc983bc94e38a399d6891a19cc629bdfe729e9ec1721c2b";

  # Latitude ships one release tag across all six images, so they move together; the digests
  # are multi-arch index digests, valid on both architectures.
  latitude = {
    web = "docker.io/latitudedata/web:0.3.127@sha256:4b27db303751bd468d33ee6a7d382f68f59373681dc06b9c250727f5a8895a0e";
    api = "docker.io/latitudedata/api:0.3.126@sha256:3acef21701f4101bc1ba8021b750d099489c156dbb5e0b0313b080a6def74e79";
    ingest = "docker.io/latitudedata/ingest:0.3.127@sha256:ceced5842d51d1f8376b0eb937a5e7083219ba5fc8ca59a69e1d98e6718817db";
    workers = "docker.io/latitudedata/workers:0.3.127@sha256:340f209835a4fc50bfc69b57c8976866848f00a755d701a896a0d6b5ec96a10d";
    workflows = "docker.io/latitudedata/workflows:0.3.127@sha256:0f4d819237c517386c76736da178c235aa509936fe98542384e883e1f48a0bca";
    migrations = "docker.io/latitudedata/migrations:0.3.127@sha256:d685759a27840f770b47cb38f11dc395c72dbe13c504041d516fefb036a35bdb";
  };

  latitudeTemporal = "docker.io/temporalio/auto-setup:1.29.7@sha256:f14912b699cf73015ad5c4fc18d522d4b014db90e794039214dfb7c022c2644f";
}
