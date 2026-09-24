# Canonical OCI image refs (registry/repo:tag@sha256:digest).
# Service modules import these; Renovate keeps the full ref current.
{
  tagr = "ghcr.io/suitux/tagr:1.9.0@sha256:668d19ca5c403813e4052b5257dff19563035ffe508832c9cf62b034362f57d9";

  trek = "docker.io/mauriceboe/trek:latest@sha256:e1611b225e4401a7bd03b9cd6763ff5ba3c18c9f93bc972a8c2b0de4353275db";

  doclingServe = "quay.io/docling-project/docling-serve:v1.26.0@sha256:56189f190892cc03a4a5c10ba9e56c421ac2524554aa2d36f0f4bb6564132524";

  paperlessGpt = "ghcr.io/icereed/paperless-gpt:latest@sha256:c0ce6186028911101a2cfe68353f14a9dbb2653596f3f1cff94de4b6db3114ff";

  karakeepWeb = "ghcr.io/karakeep-app/karakeep:0.33.2@sha256:b069e4307dec06ea06d16989c6861c30a1ff208568be44ed5fb5d422cd3e950c";

  karakeepChrome = "ghcr.io/karakeep-app/karakeep-chrome:151.0.7922.47-r1@sha256:5b19bbb160e9ff60681a3abd97e1c4ec9f64212301410de658c3900ab7ef31e7";

  karakeepMeilisearch = "getmeili/meilisearch:v1.49.0@sha256:bdc7d7e7939911c40d88d6bcd01f9c72c81f7293135916d48bce241569f721bd";

  audiomuse = "ghcr.io/neptunehub/audiomuse-ai:3.5.2@sha256:726d30981a601cb4556c6caece162ac15df247a7e7f09e36b64e8afd2f8f0b60";

  redis7Alpine = "docker.io/library/redis:7-alpine@sha256:6ab0b6e7381779332f97b8ca76193e45b0756f38d4c0dcda72dbb3c32061ab99";

  guacd = "docker.io/guacamole/guacd:1.6.0@sha256:8974eaa9ba32f713daf311e7cc8cd7e4cdfba1edea39eed75524e78ef4b08f4f";

  termix = "ghcr.io/lukegus/termix:release-2.1.0@sha256:52e45c1ea3fb85be5b3ade5ff42eed0946fe81131cbd834f6960e00797f17f86";

  omniroute = "ghcr.io/shrub24/omniroute:sha-sha-25965d5@sha256:12d7cf563a5de174f13c32fded4e58c35f841f2a94d97b7af024323a82c78674";

  langfuse = "docker.langfuse.com/langfuse/langfuse:4.43.0@sha256:d6165b4ef72027c128c6132a4d87a4643945f6ba01f9cb5d6e4af7e5e3bf5316";

  langfuseWorker = "docker.langfuse.com/langfuse/langfuse-worker:4.43.0@sha256:59be62f49978b656b27656cba7314097c6e9ca8d63ed6ef6f66394f6aaeede1b";

  docsMcpServer = "ghcr.io/arabold/docs-mcp-server:3.1.0@sha256:5bf22439746680e064db7cd1979fc192f9733f312ab9ce1c98ea0e7aa453a1f7";

  hindsight = "ghcr.io/vectorize-io/hindsight:0.10.0-slim@sha256:f6ce417777a2034a71e25df0093b28092f689a4f991eca4e2954c8b6aec2fad1";

  # Latitude ships one release tag across all six application images, so the
  # versions move together; digests are the multi-arch index digests, which is
  # what keeps the pins valid on both aarch64 and x86_64 hosts.
  latitude = {
    web = "docker.io/latitudedata/web:0.3.118@sha256:4c2ff898d14ba693f5f17e88bf2f02bfa6c1aa94b30deb88d36f888cb0c050b3";
    api = "docker.io/latitudedata/api:0.3.118@sha256:ae7a7cc4f788962eaa03c040f62f63f38ed33b8f31e781804923b8302d72035a";
    ingest = "docker.io/latitudedata/ingest:0.3.118@sha256:f35134928d7fbf412306125220bf8d27190c47b2d7cbd1ad432688dcfd7107a4";
    workers = "docker.io/latitudedata/workers:0.3.118@sha256:2ddbe608fe026777f380032737f19f936e81695a4386153a264db2a1d6ed5db9";
    workflows = "docker.io/latitudedata/workflows:0.3.118@sha256:8075a750955653acc08c984c556ebead7d787b66bebdac65b0e8e348ec28d4ca";
    migrations = "docker.io/latitudedata/migrations:0.3.118@sha256:b7729edfb4649df1cd9b6ae4b8505f7ec92abe253cced776426c2a0cb4b959ea";
  };

  latitudeTemporal = "docker.io/temporalio/auto-setup:1.27.2@sha256:b44cbfeb43dbeae42db113b44fb8414c3452f05643b3d6b1592f955277d73526";
}
