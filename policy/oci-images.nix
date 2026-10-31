# Canonical OCI image refs (registry/repo:tag@sha256:digest).
# Service modules import these; Renovate keeps the full ref current.
{
  tagr = "ghcr.io/suitux/tagr:1.16.2@sha256:271024bef2e81d865ba2d7b609a48fc643909f04f70917dab033cd6ba1a95fbb";

  trek = "docker.io/mauriceboe/trek:latest@sha256:da1d1c6b041f037fd8ac6a25a712759d29f6da991b533cdbce6d2bd1fd22daad";

  doclingServe = "quay.io/docling-project/docling-serve:v1.38.2@sha256:8a5fbc993da9dec17c53880e2445834591ad26800ef698ca64096bef29671808";

  paperlessGpt = "ghcr.io/icereed/paperless-gpt:latest@sha256:d668941a829552cc0eddbc7c22506b3480dfbf61bd0d6eae881ad9fcfe2de70c";

  karakeepWeb = "ghcr.io/karakeep-app/karakeep:0.34.1@sha256:69ae5315c618b7c14c1af3e34c6e211acdb231793af424ecd1cab0b70691d987";

  karakeepChrome = "ghcr.io/karakeep-app/karakeep-chrome:156.0.8078.47-r1@sha256:4ad61127638dd27bfe685222787c5780dd1d083d23a7658c39af657775814c44";

  karakeepMeilisearch = "docker.io/getmeili/meilisearch:v1.56.0@sha256:1f578fa865f8251894b3bf38d6668d6209a3f451f8f65ab953e129d4c1db5ef4";

  audiomuse = "ghcr.io/neptunehub/audiomuse-ai:3.7.0@sha256:38ac3c2cdb1a82e89c1bd405e5865e2efe5ad924a53b8373f5989f964a7de110";

  redis7Alpine = "docker.io/library/redis:8-alpine@sha256:21090af93f8324db2f0f0f4f38a7c60369d47d917e000c3423d89d2ae2883537";

  guacd = "docker.io/guacamole/guacd:1.6.0@sha256:8974eaa9ba32f713daf311e7cc8cd7e4cdfba1edea39eed75524e78ef4b08f4f";

  termix = "ghcr.io/lukegus/termix:release-2.1.0@sha256:52e45c1ea3fb85be5b3ade5ff42eed0946fe81131cbd834f6960e00797f17f86";

  omniroute = "ghcr.io/shrub24/omniroute:sha-sha-25965d5@sha256:12d7cf563a5de174f13c32fded4e58c35f841f2a94d97b7af024323a82c78674";

  # Docker Hub directly: the langfuse.com proxy makes its own anonymous pulls and is
  # routinely rate-limited, which fails the unit rather than the pull.
  langfuse = "docker.io/langfuse/langfuse:4.72.0@sha256:c311fd9db4b69f6514fdcb1b86a2a105d5a4ed51fbf0ded033ff2722459c804a";

  langfuseWorker = "docker.io/langfuse/langfuse-worker:4.72.0@sha256:aa1724b989a00f1e4ca9930709202489c73deaaf2f1116bbd3d71c77edb8fedb";

  docsMcpServer = "ghcr.io/arabold/docs-mcp-server:3.4.1@sha256:3176256f0716fae6052b3350795e9117bff36ef3acbe9ef5f46b2b47033f4f41";

  hindsight = "ghcr.io/vectorize-io/hindsight:1.1.0-slim@sha256:fbc37d194bce007b6cce2fd9f66cd7f8c050bd18b80e662090a92835d9cb191d";

  tududi = "docker.io/chrisvel/tududi:1.14.0@sha256:d20476b5b5c5327e3bd40c8396f4913eefde768a330e694a39d0d1c331fcc545";

  # Multi-arch manifest index, including the OCI host's aarch64-linux platform.
  homarr = "ghcr.io/homarr-labs/homarr:v2.10.1@sha256:2844201f11ce28b98183728dea2261de2b4fd8ed5480a4eef0b7977cc1a08dc0";

  # Home Assistant's own image: the container is the installation method upstream supports (ADR-0012),
  # and the multi-arch index keeps the pin valid on either architecture.
  homeAssistant = "ghcr.io/home-assistant/home-assistant:2026.10.4@sha256:23f4dfbb69ce76315dbc4de7915504f1c2dcecd7ca2648113a493a385972e133";

  # Multi-arch index digest: the arm64 manifest is selected on oci-melb-1.
  inboxZero = "ghcr.io/elie222/inbox-zero:2.30.0@sha256:e9970c499a79b8a15bbab21363d1b87ea247c75b2721f036c7cee0e2c78d1fcc";

  # Latitude ships one release tag across all six images, so they move together; the digests
  # are multi-arch index digests, valid on both architectures.
  latitude = {
    web = "docker.io/latitudedata/web:0.3.125@sha256:5917fb065458481d244a927c98a696fcc7ae4a14c96ec2a41dbb9504a5c782a3";
    api = "docker.io/latitudedata/api:0.3.125@sha256:f021eb2db4e2dbcfd1aca01153e42715a8f0fbf5fec1f8d1a3857294141eed09";
    ingest = "docker.io/latitudedata/ingest:0.3.125@sha256:c265e58f44633b975e27dceba433f3249e07f58b75a101655ce9f615ba30e7ec";
    workers = "docker.io/latitudedata/workers:0.3.125@sha256:996ec10f2f1f392cc147456650a087744a2f72cee559cfc8fdc85922fe9bc070";
    workflows = "docker.io/latitudedata/workflows:0.3.125@sha256:eca297afb310df77468aa6ca99f03ac3e9fcba8eb086372ae37ee1ea7edb6a7e";
    migrations = "docker.io/latitudedata/migrations:0.3.125@sha256:6adfde4d6c6084c2c317e32062b1adef8452acb5360434b315755ff4d31fff88";
  };

  latitudeTemporal = "docker.io/temporalio/auto-setup:1.29.7@sha256:f14912b699cf73015ad5c4fc18d522d4b014db90e794039214dfb7c022c2644f";
}
