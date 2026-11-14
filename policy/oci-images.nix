# Canonical OCI image refs (registry/repo:tag@sha256:digest).
# Service modules import these; Renovate keeps the full ref current.
{
  tagr = "ghcr.io/suitux/tagr:1.17.1@sha256:2a5dd2b84dfcb7830b8644b6fb8779379b99678e6b4b69d44152df242658d7af";

  trek = "docker.io/mauriceboe/trek:latest@sha256:3746d03d47e1c8e996dffd31135dfecc8955dbdabde2d13dbd1acac49fa8dad3";

  doclingServe = "quay.io/docling-project/docling-serve:v1.38.2@sha256:8a5fbc993da9dec17c53880e2445834591ad26800ef698ca64096bef29671808";

  paperlessGpt = "ghcr.io/icereed/paperless-gpt:latest@sha256:d668941a829552cc0eddbc7c22506b3480dfbf61bd0d6eae881ad9fcfe2de70c";

  karakeepWeb = "ghcr.io/karakeep-app/karakeep:0.34.1@sha256:69ae5315c618b7c14c1af3e34c6e211acdb231793af424ecd1cab0b70691d987";

  karakeepChrome = "ghcr.io/karakeep-app/karakeep-chrome:156.0.8078.47-r1@sha256:4ad61127638dd27bfe685222787c5780dd1d083d23a7658c39af657775814c44";

  karakeepMeilisearch = "docker.io/getmeili/meilisearch:v1.56.2@sha256:9600db22be3fcbf3d506176d3a73dd70a65c5719d9aa1d2837355b75afb8f4fb";

  audiomuse = "ghcr.io/neptunehub/audiomuse-ai:3.7.1@sha256:5bdf6c6c15073ddb85eaa2d6662439c176e35c7f5c00c0a3e59c3b119d800f30";

  redis7Alpine = "docker.io/library/redis:8-alpine@sha256:7958cfbb9d152f87dadfbc89f1b0b15938f0b81ff8982feb327476f4911935c3";

  guacd = "docker.io/guacamole/guacd:1.6.0@sha256:8974eaa9ba32f713daf311e7cc8cd7e4cdfba1edea39eed75524e78ef4b08f4f";

  termix = "ghcr.io/lukegus/termix:release-2.1.0@sha256:52e45c1ea3fb85be5b3ade5ff42eed0946fe81131cbd834f6960e00797f17f86";

  omniroute = "ghcr.io/shrub24/omniroute:sha-sha-25965d5@sha256:12d7cf563a5de174f13c32fded4e58c35f841f2a94d97b7af024323a82c78674";

  # Docker Hub directly: the langfuse.com proxy makes its own anonymous pulls and is
  # routinely rate-limited, which fails the unit rather than the pull.
  langfuse = "docker.io/langfuse/langfuse:4.80.0@sha256:0814758db3db8e923f733be3884e7d7a9e3afd60568d874a610d78aae47476c5";

  langfuseWorker = "docker.io/langfuse/langfuse-worker:4.80.0@sha256:da9f618dd784219aa6508ab6941c4a89c4ef6fb429fb1734c4163df3baa8f1ca";

  docsMcpServer = "ghcr.io/arabold/docs-mcp-server:3.4.1@sha256:3176256f0716fae6052b3350795e9117bff36ef3acbe9ef5f46b2b47033f4f41";

  hindsight = "ghcr.io/vectorize-io/hindsight:1.2.1-slim@sha256:5ad59a5e8ea1a7424376ad0f0fa149cf42f30e36a944b71b6e40cc23230dd04a";

  tududi = "docker.io/chrisvel/tududi:1.15.1@sha256:2b15d6b8ce51c61253cc9b588fa19abce6ce939565ff9683ffd56a1ab251b015";

  # GeoPulse ships the backend as a GraalVM native binary and the UI as nginx plus the built
  # SPA; both are multi-arch indexes, and `-native` targets armv8-a, which is Ampere A1.
  geopulseBackend = "docker.io/tess1o/geopulse-backend:2.3.0-native@sha256:17ac22bb3c13152bf8d10cce6fb070f56a864a7a8fa4eae240bddd59ff667637";

  geopulseUi = "docker.io/tess1o/geopulse-ui:2.3.0@sha256:c278843426c8a65ac9988e169b479ec0de5f5a2ebc88ab404ba8558c506e5e13";

  # Multi-arch manifest index, including the OCI host's aarch64-linux platform.
  homarr = "ghcr.io/homarr-labs/homarr:v2.13.1@sha256:7b3ab85bad2656be6c940b9d26117254edb6d998aeb5b66dfdc795f2e737802a";

  # Home Assistant's own image: the container is the installation method upstream supports (ADR-0012),
  # and the multi-arch index keeps the pin valid on either architecture.
  homeAssistant = "ghcr.io/home-assistant/home-assistant:2026.11.1@sha256:6785d1eca68747a524c156faae1b139ed415c07357386ae6fe17291986e59e82";

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
