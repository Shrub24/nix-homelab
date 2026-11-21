# Canonical OCI image refs (registry/repo:tag@sha256:digest).
# Service modules import these; Renovate keeps the full ref current.
{
  tagr = "ghcr.io/suitux/tagr:1.17.1@sha256:2a5dd2b84dfcb7830b8644b6fb8779379b99678e6b4b69d44152df242658d7af";

  trek = "docker.io/mauriceboe/trek:latest@sha256:3746d03d47e1c8e996dffd31135dfecc8955dbdabde2d13dbd1acac49fa8dad3";

  doclingServe = "quay.io/docling-project/docling-serve:v1.38.2@sha256:8a5fbc993da9dec17c53880e2445834591ad26800ef698ca64096bef29671808";

  paperlessGpt = "ghcr.io/icereed/paperless-gpt:latest@sha256:d668941a829552cc0eddbc7c22506b3480dfbf61bd0d6eae881ad9fcfe2de70c";

  karakeepWeb = "ghcr.io/karakeep-app/karakeep:0.35.0@sha256:6f7d32ef296ddf1fc7c67ff56b8a201b7006a6a47b92b202afee1338841b353d";

  karakeepChrome = "ghcr.io/karakeep-app/karakeep-chrome:156.0.8078.47-r1@sha256:4ad61127638dd27bfe685222787c5780dd1d083d23a7658c39af657775814c44";

  karakeepMeilisearch = "docker.io/getmeili/meilisearch:v1.57.0@sha256:91bf09897482c17205c8faeca8daa8d57999fb9de20d862763cdfa92ba4ec790";

  audiomuse = "ghcr.io/neptunehub/audiomuse-ai:3.7.3@sha256:1713eb30cc0d53c17566d6367ddf4c8c35f8503d21c84c820e89b06c1d2e5cf3";

  redis7Alpine = "docker.io/library/redis:8-alpine@sha256:7958cfbb9d152f87dadfbc89f1b0b15938f0b81ff8982feb327476f4911935c3";

  guacd = "docker.io/guacamole/guacd:1.6.0@sha256:8974eaa9ba32f713daf311e7cc8cd7e4cdfba1edea39eed75524e78ef4b08f4f";

  termix = "ghcr.io/lukegus/termix:release-2.1.0@sha256:52e45c1ea3fb85be5b3ade5ff42eed0946fe81131cbd834f6960e00797f17f86";

  omniroute = "ghcr.io/shrub24/omniroute:sha-sha-25965d5@sha256:12d7cf563a5de174f13c32fded4e58c35f841f2a94d97b7af024323a82c78674";

  # Docker Hub directly: the langfuse.com proxy makes its own anonymous pulls and is
  # routinely rate-limited, which fails the unit rather than the pull.
  langfuse = "docker.io/langfuse/langfuse:4.83.0@sha256:a91445265d1f5a13d666ef2f1491a437255fb9e5b7a76525d5543e4a4dc030f3";

  langfuseWorker = "docker.io/langfuse/langfuse-worker:4.83.0@sha256:a6eac4bb99df27dd01a090e63d1a54660ba14044ae5e4c1ef1c883cec5d68ee4";

  docsMcpServer = "ghcr.io/arabold/docs-mcp-server:3.4.1@sha256:3176256f0716fae6052b3350795e9117bff36ef3acbe9ef5f46b2b47033f4f41";

  hindsight = "ghcr.io/vectorize-io/hindsight:1.2.3-slim@sha256:411820087fd3a34fa71ecbc9ca049d1f38cec0426148c801b886c07d580703d5";

  tududi = "docker.io/chrisvel/tududi:1.15.1@sha256:2b15d6b8ce51c61253cc9b588fa19abce6ce939565ff9683ffd56a1ab251b015";

  # GeoPulse ships the backend as a GraalVM native binary and the UI as nginx plus the built
  # SPA; both are multi-arch indexes, and `-native` targets armv8-a, which is Ampere A1.
  geopulseBackend = "docker.io/tess1o/geopulse-backend:2.4.0-native@sha256:019858a83b1662b179cb150dea3d7d267906b42d4e4ddefa19d99b97c91c7f72";

  geopulseUi = "docker.io/tess1o/geopulse-ui:2.4.0@sha256:d66d8cdb0dec3a6b4afd5b574eb51695b35938e0c8263f66c04d4c208c97f04b";

  # Multi-arch manifest index, including the OCI host's aarch64-linux platform.
  homarr = "ghcr.io/homarr-labs/homarr:v2.14.0@sha256:742940b00ed13e8649ddfd81532ad8f4140ad413ed0591f464ff6e4f7ff3c276";

  # Home Assistant's own image: the container is the installation method upstream supports (ADR-0012),
  # and the multi-arch index keeps the pin valid on either architecture.
  homeAssistant = "ghcr.io/home-assistant/home-assistant:2026.11.2@sha256:493a07e8f6530fc640223f4a0a5248f20a61ca2f718bb1d31efbf08a2c5ea28f";

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
    web = "docker.io/latitudedata/web:0.3.126@sha256:e664b19c12f7dfdf1678311b4d9d6e046432d53b607302a3787cb4edcb044838";
    api = "docker.io/latitudedata/api:0.3.126@sha256:3acef21701f4101bc1ba8021b750d099489c156dbb5e0b0313b080a6def74e79";
    ingest = "docker.io/latitudedata/ingest:0.3.126@sha256:f74a2d8033e38ac5173d2d0e27c044ca3e801a9caaaf845944fc65946ca20dd3";
    workers = "docker.io/latitudedata/workers:0.3.126@sha256:6d960588b8ae794131857f555bb0c9ab8c3aa53988f76378f5fdcab21ebdd340";
    workflows = "docker.io/latitudedata/workflows:0.3.126@sha256:0988222b4ed1c09839e56a7f22b43648872fc2092abbc83091a46206f03f183f";
    migrations = "docker.io/latitudedata/migrations:0.3.126@sha256:8a971a9985e817834818d668ae6d54000dd0e62fbb9c21a402d0833dcdcf0438";
  };

  latitudeTemporal = "docker.io/temporalio/auto-setup:1.29.7@sha256:f14912b699cf73015ad5c4fc18d522d4b014db90e794039214dfb7c022c2644f";
}
