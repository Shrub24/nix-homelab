# Canonical OCI image refs (registry/repo:tag@sha256:digest).
# Service modules import these; Renovate keeps the full ref current.
{
  tagr = "ghcr.io/suitux/tagr:1.16.2@sha256:271024bef2e81d865ba2d7b609a48fc643909f04f70917dab033cd6ba1a95fbb";

  trek = "docker.io/mauriceboe/trek:latest@sha256:da1d1c6b041f037fd8ac6a25a712759d29f6da991b533cdbce6d2bd1fd22daad";

  doclingServe = "quay.io/docling-project/docling-serve:v1.38.2@sha256:8a5fbc993da9dec17c53880e2445834591ad26800ef698ca64096bef29671808";

  paperlessGpt = "ghcr.io/icereed/paperless-gpt:latest@sha256:d668941a829552cc0eddbc7c22506b3480dfbf61bd0d6eae881ad9fcfe2de70c";

  karakeepWeb = "ghcr.io/karakeep-app/karakeep:0.34.1@sha256:69ae5315c618b7c14c1af3e34c6e211acdb231793af424ecd1cab0b70691d987";

  karakeepChrome = "ghcr.io/karakeep-app/karakeep-chrome:156.0.8078.47-r1@sha256:4ad61127638dd27bfe685222787c5780dd1d083d23a7658c39af657775814c44";

  karakeepMeilisearch = "docker.io/getmeili/meilisearch:v1.56.1@sha256:b7ba431bf6f9b26cc86132798f3640964147a699cf23f026b74c6c05dbb1d60d";

  audiomuse = "ghcr.io/neptunehub/audiomuse-ai:3.7.1@sha256:5bdf6c6c15073ddb85eaa2d6662439c176e35c7f5c00c0a3e59c3b119d800f30";

  redis7Alpine = "docker.io/library/redis:8-alpine@sha256:71885d8cc6e42f2bc0aa2eb853bfc4be200b5108a46ac50e117ae1df0531fb80";

  guacd = "docker.io/guacamole/guacd:1.6.0@sha256:8974eaa9ba32f713daf311e7cc8cd7e4cdfba1edea39eed75524e78ef4b08f4f";

  termix = "ghcr.io/lukegus/termix:release-2.1.0@sha256:52e45c1ea3fb85be5b3ade5ff42eed0946fe81131cbd834f6960e00797f17f86";

  omniroute = "ghcr.io/shrub24/omniroute:sha-sha-25965d5@sha256:12d7cf563a5de174f13c32fded4e58c35f841f2a94d97b7af024323a82c78674";

  # Docker Hub directly: the langfuse.com proxy makes its own anonymous pulls and is
  # routinely rate-limited, which fails the unit rather than the pull.
  langfuse = "docker.io/langfuse/langfuse:4.76.0@sha256:59abb54faacf45b63d09f4076d45683dae26a6661974d497836543d350b16575";

  langfuseWorker = "docker.io/langfuse/langfuse-worker:4.76.0@sha256:27e8b49d619a013bca38ed9b0853456e19f5667a23e8e26e3a10d4e28485f49c";

  docsMcpServer = "ghcr.io/arabold/docs-mcp-server:3.4.1@sha256:3176256f0716fae6052b3350795e9117bff36ef3acbe9ef5f46b2b47033f4f41";

  hindsight = "ghcr.io/vectorize-io/hindsight:1.2.0-slim@sha256:c7d494c309fde53d07e79158be08d7a61f3f309b23cc417c7e4b0b8fc8adc77a";

  tududi = "docker.io/chrisvel/tududi:1.15.1@sha256:2b15d6b8ce51c61253cc9b588fa19abce6ce939565ff9683ffd56a1ab251b015";

  # GeoPulse ships the backend as a GraalVM native binary and the UI as nginx plus the built
  # SPA; both are multi-arch indexes, and `-native` targets armv8-a, which is Ampere A1.
  geopulseBackend = "docker.io/tess1o/geopulse-backend:2.2.1-native@sha256:07fc812057c8e2520fe801d463afa3bfe437fd720f09466257632d28106f6142";

  geopulseUi = "docker.io/tess1o/geopulse-ui:2.2.1@sha256:77701867e2613576d7fd9bc49eaa2a7c1b72fad59d6d8f9c3bd4b192c161b29a";

  # Multi-arch manifest index, including the OCI host's aarch64-linux platform.
  homarr = "ghcr.io/homarr-labs/homarr:v2.12.0@sha256:44c480afe9df57ce9de44cb664aec53199ea19926ebdd4e590c7b2c2c0a5ef79";

  # Home Assistant's own image: the container is the installation method upstream supports (ADR-0012),
  # and the multi-arch index keeps the pin valid on either architecture.
  homeAssistant = "ghcr.io/home-assistant/home-assistant:2026.11.0@sha256:c6c1ca9931036bf3a2c4cc088d8db25dfea3b33935a5ecc83c40349462e2f69e";

  # Multi-arch index digest: the arm64 manifest is selected on oci-melb-1.
  inboxZero = "ghcr.io/elie222/inbox-zero:82004cd@sha256:182ca110030c6505e74d67d996deb46f4a5424f57263b222745cc26bd5571a97";

  # The frontend image serves the application; the API is a separate image.
  sparkyFitness = "docker.io/codewithcj/sparkyfitness:v1.11.0@sha256:5eb77135ccd8e58492ee9bd19b8714ea4a73a99623b863a9287ccecb0557cd17";

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
