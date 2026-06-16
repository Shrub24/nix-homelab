# Canonical OCI image refs (registry/repo:tag@sha256:digest).
# Service modules import these; Renovate keeps the full ref current.
{
  bifrost = "docker.io/maximhq/bifrost:v1.5.0-prerelease8@sha256:6080255cffdba8fa2abbc14e9b1f463f840dfc4ae5c4a7d47a7ca138b38cdb2c";

  soulsync = "docker.io/boulderbadgedad/soulsync:2.3@sha256:b66edfd3991f1c21e4c28a8bbe71acc998cc156c78e36eb86dd1375667ccd5c7";

  tagr = "ghcr.io/shrub24/tagr:latest@sha256:4b1844cc648e7ab83a14208fa15d68fd49d79f43c7403f87fe3139fed114c243";

  trek = "docker.io/mauriceboe/trek:latest@sha256:fdd4bbc3b38c50744fd506d26766560633e902a4782f89f9756b9231d94b918a";

  doclingServe = "quay.io/docling-project/docling-serve:v1.24.0@sha256:045e7a14c32b3a5cc78c6fd0deac15fde196ec62d1325a553f98221a57480174";

  paperlessGpt = "ghcr.io/icereed/paperless-gpt:latest@sha256:c0ce6186028911101a2cfe68353f14a9dbb2653596f3f1cff94de4b6db3114ff";

  karakeepWeb = "ghcr.io/karakeep-app/karakeep:release@sha256:64d6a9bbf2d37b5c808cf06b5d87f1f1c7846fdd3844724145a9741aeb06fd31";

  karakeepChrome = "gcr.io/zenika-hub/alpine-chrome:124@sha256:1a0046448e0bb6c275c88f86e01faf0de62b02ec8572901256ada0a8c08be23f";

  karakeepMeilisearch = "getmeili/meilisearch:v1.47.0@sha256:4931c0afd68b12d3db4a608268c6785bba26d3f3b43a228eff62ec38d5a47d8d";

  guacd = "docker.io/guacamole/guacd:1.6.0@sha256:8974eaa9ba32f713daf311e7cc8cd7e4cdfba1edea39eed75524e78ef4b08f4f";

  termix = "ghcr.io/lukegus/termix:release-2.1.0@sha256:52e45c1ea3fb85be5b3ade5ff42eed0946fe81131cbd834f6960e00797f17f86";

  quantum = "ghcr.io/gtsteffaniak/filebrowser:stable@sha256:eb3733681db8757412632c61a99ad656f0d94ed6781bb2ea114b4d70babab78c";
}
