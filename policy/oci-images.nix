# Canonical OCI image refs (registry/repo:tag@sha256:digest).
# Service modules import these; Renovate keeps the full ref current.
{
  bifrost = "docker.io/maximhq/bifrost:v1.5.0-prerelease8@sha256:6080255cffdba8fa2abbc14e9b1f463f840dfc4ae5c4a7d47a7ca138b38cdb2c";

  tagr = "ghcr.io/suitux/tagr:1.12.0@sha256:ad760b3557919aa09d778d5b02325f4dd7c5515127ae433d9e4677206897187a";

  trek = "docker.io/mauriceboe/trek:latest@sha256:90da7246206646ca76ad0b46780d582612d6523376a7dd369d7eca39c5d939b0";

  doclingServe = "quay.io/docling-project/docling-serve:v1.36.0@sha256:b43692644de598836a48b8b5bf8ba37bda02fb0f7b84abafe26f2a3aecd0a601";

  paperlessGpt = "ghcr.io/icereed/paperless-gpt:latest@sha256:4127ea223e0f496c1075a3a05661df4847140974c3c3ce89a4ba991be50320cb";

  karakeepWeb = "ghcr.io/karakeep-app/karakeep:0.33.2@sha256:b069e4307dec06ea06d16989c6861c30a1ff208568be44ed5fb5d422cd3e950c";

  karakeepChrome = "ghcr.io/karakeep-app/karakeep-chrome:151.0.7922.47-r1@sha256:5b19bbb160e9ff60681a3abd97e1c4ec9f64212301410de658c3900ab7ef31e7";

  karakeepMeilisearch = "getmeili/meilisearch:v1.54.3@sha256:e68913ab7d6f5b159529e472cfd362ce3c741fafd3c127961b2142abbe41b3c9";

  audiomuse = "ghcr.io/neptunehub/audiomuse-ai:3.6.3@sha256:301b2d5c280f43c6e79823337455b6b7d575d7b8040a6f150266804350c51eab";

  redis7Alpine = "docker.io/library/redis:7-alpine@sha256:858f009f9709ce576febc734aa78b8f6d624b82571f9ddb6bda4377c833b3499";

  guacd = "docker.io/guacamole/guacd:1.6.0@sha256:8974eaa9ba32f713daf311e7cc8cd7e4cdfba1edea39eed75524e78ef4b08f4f";

  termix = "ghcr.io/lukegus/termix:release-2.1.0@sha256:52e45c1ea3fb85be5b3ade5ff42eed0946fe81131cbd834f6960e00797f17f86";

  phoenix = "docker.io/arizephoenix/phoenix:latest@sha256:904bdea6dbd16b4347be06003b2199e4aed41a21745bfba97f88f0498ffdb3d4";

  omniroute = "ghcr.io/shrub24/omniroute:edge@sha256:2b8dd145271ca7290f0143527c95f6fb54cc016ca218679d583e7c7d8bffa913";
}
