let
  globals = import ./globals.nix;

  # `file`, when present, is the tracked source uploaded to the URL's key.
  own = name: file: {
    url = "${globals.assets.baseUrl}/${name}";
    inherit file;
  };
in
{
  inherit (globals.s3) endpoint;
  inherit (globals) domain;
  zoneName = globals.domain;
  bucket = "shrublab-assets";
  publicUrl = globals.assets.baseUrl;

  brand = {
    icon = own "icon.svg" ../assets/icon.svg;
    logo = own "logo-horizontal.svg" ../assets/logo-horizontal.svg;
    logoStacked = own "logo-stacked.svg" ../assets/logo-stacked.svg;
    # No tracked source: a timer replaces the object behind this fixed URL.
    wallpaper.url = "${globals.assets.baseUrl}/background.png";
  };

  # Dashboard icons are commit-pinned upstream files: the dashboard is not gated by the
  # application or by Cloudflare Access, and no third-party artwork is redistributed.
  icons = {
    actual.url = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons@83f32e08257b66fbd971ac8d7645f5b38d52e85d/svg/actual-budget.svg";
    beszel.url = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons@83f32e08257b66fbd971ac8d7645f5b38d52e85d/svg/beszel.svg";
    bookorbit.url = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons@83f32e08257b66fbd971ac8d7645f5b38d52e85d/webp/bookorbit.webp";
    geopulse.url = "https://cdn.jsdelivr.net/gh/selfhst/icons@02dd039d62a8e7132f4828e69162fca30bd43bb5/svg/geopulse-light.svg";
    grafana.url = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons@83f32e08257b66fbd971ac8d7645f5b38d52e85d/svg/grafana.svg";
    homarr.url = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons@83f32e08257b66fbd971ac8d7645f5b38d52e85d/svg/homarr.svg";
    inbox-zero.url = "https://raw.githubusercontent.com/elie222/inbox-zero/48a2b49cee7f89980b47ebeade2f6cc0758eefde/docs/favicon.png";
    karakeep.url = "https://cdn.jsdelivr.net/gh/selfhst/icons@02dd039d62a8e7132f4828e69162fca30bd43bb5/svg/karakeep.svg";
    langfuse.url = "https://raw.githubusercontent.com/langfuse/langfuse/fc3680f9b1472fc10b33dc4e7d99d18c076a1faa/web/public/icon.svg";
    memos.url = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons@83f32e08257b66fbd971ac8d7645f5b38d52e85d/svg/memos.svg";
    paperless.url = "https://cdn.jsdelivr.net/gh/selfhst/icons@02dd039d62a8e7132f4828e69162fca30bd43bb5/svg/paperless-ngx.svg";
    tududi.url = "https://cdn.jsdelivr.net/gh/selfhst/icons@02dd039d62a8e7132f4828e69162fca30bd43bb5/svg/tududi-light.svg";
  };
}
