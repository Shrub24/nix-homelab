# Canonical OCI image refs (registry/repo:tag@sha256:digest).
# Service modules import these; Renovate keeps the full ref current.
{
  bifrost = "docker.io/maximhq/bifrost:v1.5.0-prerelease8@sha256:6080255cffdba8fa2abbc14e9b1f463f840dfc4ae5c4a7d47a7ca138b38cdb2c";

  tagr = "ghcr.io/suitux/tagr:1.10.1@sha256:4a0859ae255200b22a24956a779439a306f175a1b2bc681ecd5e24807ed1b329";

  trek = "docker.io/mauriceboe/trek:latest@sha256:9a54f8e6247c07158c31eff2eb7b34489cb8e0ed1ba356af9bc77418b55813d4";

  doclingServe = "quay.io/docling-project/docling-serve:v1.34.0@sha256:09fc953cbe973b0a3a3db437479949a7290728ca00b2db93d56a53d01e6f7bd0";

  paperlessGpt = "ghcr.io/icereed/paperless-gpt:latest@sha256:413af73ff5415e1f61327ccb1c63cb14e84e86b761969be6eaaee61b4f39bef4";

  karakeepWeb = "ghcr.io/karakeep-app/karakeep:0.33.2@sha256:b069e4307dec06ea06d16989c6861c30a1ff208568be44ed5fb5d422cd3e950c";

  karakeepChrome = "ghcr.io/karakeep-app/karakeep-chrome:151.0.7922.47-r1@sha256:5b19bbb160e9ff60681a3abd97e1c4ec9f64212301410de658c3900ab7ef31e7";

  karakeepMeilisearch = "getmeili/meilisearch:v1.53.2@sha256:c94e58ca09662dd6e65e8f1b0fd145767be3da7d5422a863a27b8d2b68e090c9";

  audiomuse = "ghcr.io/neptunehub/audiomuse-ai:3.6.1@sha256:a8ab621ed68061154de8a21efa897dfcc9db3d3545421cdb882010c489274fc3";

  redis7Alpine = "docker.io/library/redis:7-alpine@sha256:520775a41a63e77e06c73e35d2fd9cc15921a609516818796b4ecbb813078bc7";

  guacd = "docker.io/guacamole/guacd:1.6.0@sha256:8974eaa9ba32f713daf311e7cc8cd7e4cdfba1edea39eed75524e78ef4b08f4f";

  termix = "ghcr.io/lukegus/termix:release-2.1.0@sha256:52e45c1ea3fb85be5b3ade5ff42eed0946fe81131cbd834f6960e00797f17f86";

  quantum = "ghcr.io/gtsteffaniak/filebrowser:stable@sha256:7c5d7ac8ffda31294d278063cf9d2e04303b39e6dce1f4c691342240ca7703b8";

  phoenix = "docker.io/arizephoenix/phoenix:latest@sha256:d6e85f37e983732bd54a8c8fe9dee2488bb75fcc41ce572120c40f55cc303380";

  omniroute = "ghcr.io/shrub24/omniroute:edge@sha256:765a1194ee95fceb567c9a87a49331289cea24c532b715b7f5c2da6ee2e23eb4";
}
