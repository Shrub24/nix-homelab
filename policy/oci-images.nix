# Canonical OCI image refs (registry/repo:tag@sha256:digest).
# Service modules import these; Renovate keeps the full ref current.
{
  bifrost = "docker.io/maximhq/bifrost:v1.5.0-prerelease8@sha256:6080255cffdba8fa2abbc14e9b1f463f840dfc4ae5c4a7d47a7ca138b38cdb2c";

  tagr = "ghcr.io/suitux/tagr:sha-4ce3078@sha256:4dede3f8220e874fbfefecc0806f0ac427505de3de1d8f08922a117b70dccbd7";

  trek = "docker.io/mauriceboe/trek:latest@sha256:9a54f8e6247c07158c31eff2eb7b34489cb8e0ed1ba356af9bc77418b55813d4";

  doclingServe = "quay.io/docling-project/docling-serve:v1.32.0@sha256:5d1a649d48b5715e23ec4906bb0624632b1971a1d975a4bc57d0f723114c7c6e";

  paperlessGpt = "ghcr.io/icereed/paperless-gpt:latest@sha256:855d9df5bacb2bed60bd520f1ffe0d118695aef9f77d37466ae85823001f547d";

  karakeepWeb = "ghcr.io/karakeep-app/karakeep:release@sha256:b069e4307dec06ea06d16989c6861c30a1ff208568be44ed5fb5d422cd3e950c";

  karakeepChrome = "gcr.io/zenika-hub/alpine-chrome:124@sha256:1a0046448e0bb6c275c88f86e01faf0de62b02ec8572901256ada0a8c08be23f";

  karakeepMeilisearch = "getmeili/meilisearch:v1.53.1@sha256:8d6643d86d71fad6ad3cba92cde7ccfce9e4d6c384bda67598eb553571c32431";

  audiomuse = "ghcr.io/neptunehub/audiomuse-ai:latest@sha256:726d30981a601cb4556c6caece162ac15df247a7e7f09e36b64e8afd2f8f0b60";

  redis7Alpine = "docker.io/library/redis:7-alpine@sha256:ff02b58f971e7d7d156a1267e283fcbbeee91773b6aa36c49dac28ecfe28eadf";

  guacd = "docker.io/guacamole/guacd:1.6.0@sha256:8974eaa9ba32f713daf311e7cc8cd7e4cdfba1edea39eed75524e78ef4b08f4f";

  termix = "ghcr.io/lukegus/termix:release-2.1.0@sha256:52e45c1ea3fb85be5b3ade5ff42eed0946fe81131cbd834f6960e00797f17f86";

  quantum = "ghcr.io/gtsteffaniak/filebrowser:stable@sha256:7c5d7ac8ffda31294d278063cf9d2e04303b39e6dce1f4c691342240ca7703b8";

  phoenix = "docker.io/arizephoenix/phoenix:latest@sha256:b899655ed60ba69fcbbe470963b673b2635ee5e7ede6ea7085eeef2645348647";
}
