# Canonical OCI image refs (registry/repo:tag@sha256:digest).
# Service modules import these; Renovate keeps the full ref current.
{
  bifrost = "docker.io/maximhq/bifrost:v1.5.0-prerelease8@sha256:6080255cffdba8fa2abbc14e9b1f463f840dfc4ae5c4a7d47a7ca138b38cdb2c";

  tagr = "ghcr.io/suitux/tagr:1.10.1@sha256:4a0859ae255200b22a24956a779439a306f175a1b2bc681ecd5e24807ed1b329";

  trek = "docker.io/mauriceboe/trek:latest@sha256:90da7246206646ca76ad0b46780d582612d6523376a7dd369d7eca39c5d939b0";

  doclingServe = "quay.io/docling-project/docling-serve:v1.35.0@sha256:b579dcdeadebc7748a09032564561009921a20d8819013c534cd48bdb9f1bb0d";

  paperlessGpt = "ghcr.io/icereed/paperless-gpt:latest@sha256:413af73ff5415e1f61327ccb1c63cb14e84e86b761969be6eaaee61b4f39bef4";

  karakeepWeb = "ghcr.io/karakeep-app/karakeep:0.33.2@sha256:b069e4307dec06ea06d16989c6861c30a1ff208568be44ed5fb5d422cd3e950c";

  karakeepChrome = "ghcr.io/karakeep-app/karakeep-chrome:151.0.7922.47-r1@sha256:5b19bbb160e9ff60681a3abd97e1c4ec9f64212301410de658c3900ab7ef31e7";

  karakeepMeilisearch = "getmeili/meilisearch:v1.54.0@sha256:0bf32debcbfa8ba4e418679025f4935884972171513c92f0584689ff994a61df";

  audiomuse = "ghcr.io/neptunehub/audiomuse-ai:3.6.3@sha256:301b2d5c280f43c6e79823337455b6b7d575d7b8040a6f150266804350c51eab";

  redis7Alpine = "docker.io/library/redis:7-alpine@sha256:858f009f9709ce576febc734aa78b8f6d624b82571f9ddb6bda4377c833b3499";

  guacd = "docker.io/guacamole/guacd:1.6.0@sha256:8974eaa9ba32f713daf311e7cc8cd7e4cdfba1edea39eed75524e78ef4b08f4f";

  termix = "ghcr.io/lukegus/termix:release-2.1.0@sha256:52e45c1ea3fb85be5b3ade5ff42eed0946fe81131cbd834f6960e00797f17f86";

  phoenix = "docker.io/arizephoenix/phoenix:latest@sha256:06951dafc44952bb378ab1c628432952f578cab893ad2ec2695d7461d589b57d";

  omniroute = "ghcr.io/shrub24/omniroute:edge@sha256:f458ed033c96fa2536d55ce6a1072bf15f832bc02fdfaafa0c88271fa082d28c";
}
