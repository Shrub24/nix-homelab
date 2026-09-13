# Canonical OCI image refs (registry/repo:tag@sha256:digest).
# Service modules import these; Renovate keeps the full ref current.
{
  bifrost = "docker.io/maximhq/bifrost:v1.5.0-prerelease8@sha256:6080255cffdba8fa2abbc14e9b1f463f840dfc4ae5c4a7d47a7ca138b38cdb2c";

  tagr = "ghcr.io/suitux/tagr:1.10.0@sha256:759266bac7ccdb1e51ae9949e38cc876ab3294a0fdd7659a6278c65e35804409";

  trek = "docker.io/mauriceboe/trek:latest@sha256:9a54f8e6247c07158c31eff2eb7b34489cb8e0ed1ba356af9bc77418b55813d4";

  doclingServe = "quay.io/docling-project/docling-serve:v1.32.0@sha256:5d1a649d48b5715e23ec4906bb0624632b1971a1d975a4bc57d0f723114c7c6e";

  paperlessGpt = "ghcr.io/icereed/paperless-gpt:latest@sha256:855d9df5bacb2bed60bd520f1ffe0d118695aef9f77d37466ae85823001f547d";

  karakeepWeb = "ghcr.io/karakeep-app/karakeep:0.33.2@sha256:b069e4307dec06ea06d16989c6861c30a1ff208568be44ed5fb5d422cd3e950c";

  karakeepChrome = "ghcr.io/karakeep-app/karakeep-chrome:151.0.7922.47-r1@sha256:5b19bbb160e9ff60681a3abd97e1c4ec9f64212301410de658c3900ab7ef31e7";

  karakeepMeilisearch = "getmeili/meilisearch:v1.53.2@sha256:c94e58ca09662dd6e65e8f1b0fd145767be3da7d5422a863a27b8d2b68e090c9";

  audiomuse = "ghcr.io/neptunehub/audiomuse-ai:3.6.0@sha256:58d7517724a9ea3eb63fb6c2df76e0f223d2e6092cd60714d4e0bad8d4418ca4";

  redis7Alpine = "docker.io/library/redis:7-alpine@sha256:ff02b58f971e7d7d156a1267e283fcbbeee91773b6aa36c49dac28ecfe28eadf";

  guacd = "docker.io/guacamole/guacd:1.6.0@sha256:8974eaa9ba32f713daf311e7cc8cd7e4cdfba1edea39eed75524e78ef4b08f4f";

  termix = "ghcr.io/lukegus/termix:release-2.1.0@sha256:52e45c1ea3fb85be5b3ade5ff42eed0946fe81131cbd834f6960e00797f17f86";

  quantum = "ghcr.io/gtsteffaniak/filebrowser:stable@sha256:7c5d7ac8ffda31294d278063cf9d2e04303b39e6dce1f4c691342240ca7703b8";

  phoenix = "docker.io/arizephoenix/phoenix:latest@sha256:3cb7c12d920ac61ab589cb510ef1df3bbdc90200b882a2a1b1b5d9f983badeb8";

  omniroute = "ghcr.io/shrub24/omniroute:edge@sha256:4a504ceccfa59522dadc42ed017970184b14556a61aee4338aebb0e0d1a1ae04";
}
