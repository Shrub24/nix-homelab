# Canonical OCI image refs (registry/repo:tag@sha256:digest).
# Service modules import these; Renovate keeps the full ref current.
{
  bifrost = "docker.io/maximhq/bifrost:v1.5.0-prerelease8@sha256:6080255cffdba8fa2abbc14e9b1f463f840dfc4ae5c4a7d47a7ca138b38cdb2c";

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

  quantum = "ghcr.io/gtsteffaniak/filebrowser:stable@sha256:2cd949cd06c058576773c5b8400c854478a64c4f364b1e2bea275819847f099b";

  phoenix = "docker.io/arizephoenix/phoenix:latest@sha256:7eee4177732e6cba269f83071b869c5e37a86b47ba2ba8c6bef246273bee501d";

  omniroute = "ghcr.io/shrub24/omniroute:edge@sha256:a7c2cc4bb3852f2c67fdd5e7f2fb1b80042ee2d84b295648eaa67cb0ef8e53a9";
}
