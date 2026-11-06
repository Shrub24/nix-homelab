# Authentik renders its HTML shell per request, so no manifest can be linked from the dashboard:
# this install page is the entry, and the manifest's start_url opens the dashboard.
{
  lib,
  config,
  pkgs,
  options,
  ...
}:
let
  icon = ../../../assets/icon.svg;

  # The mark carries its own margins, so the maskable variant is centred on the brand background
  # rather than cropped: an adaptive icon may cut anything outside its 80% safe area.
  icons = pkgs.runCommand "shrublab-pwa-icons" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
    mkdir -p $out
    rsvg-convert -w 192 -h 192 ${icon} -o $out/icon-192.png
    rsvg-convert -w 512 -h 512 ${icon} -o $out/icon-512.png
    rsvg-convert -w 180 -h 180 ${icon} -o $out/apple-touch-icon.png
    mark="$(base64 -w0 ${icon})"
    cat > maskable.svg <<EOF
    <svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
      <rect width="512" height="512" fill="#0b0d10"/>
      <image href="data:image/svg+xml;base64,$mark" x="51" y="51" width="410" height="410"
             preserveAspectRatio="xMidYMid meet"/>
    </svg>
    EOF
    rsvg-convert -w 512 -h 512 maskable.svg -o $out/icon-maskable-512.png
  '';

  # .json rather than .webmanifest: Caddy infers the content type from the extension, and a
  # manifest served as octet-stream is not installed.
  manifest = pkgs.writeText "manifest.json" (
    builtins.toJSON {
      name = "Shrublab";
      short_name = "Shrublab";
      description = "Sign in to Shrublab services.";
      start_url = "/if/user/";
      scope = "/";
      display = "standalone";
      background_color = "#0b0d10";
      theme_color = "#0b0d10";
      icons = [
        {
          src = "/pwa/icon-192.png";
          sizes = "192x192";
          type = "image/png";
        }
        {
          src = "/pwa/icon-512.png";
          sizes = "512x512";
          type = "image/png";
        }
        {
          src = "/pwa/icon-maskable-512.png";
          sizes = "512x512";
          type = "image/png";
          purpose = "maskable";
        }
      ];
    }
  );

  installPage = pkgs.writeText "pwa-install.html" ''
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Shrublab</title>
        <link rel="manifest" href="/pwa/manifest.json">
        <link rel="apple-touch-icon" href="/pwa/apple-touch-icon.png">
        <meta name="theme-color" content="#0b0d10">
        <meta name="apple-mobile-web-app-capable" content="yes">
        <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
        <meta name="apple-mobile-web-app-title" content="Shrublab">
        <style>
          :root { color-scheme: dark; }
          body {
            margin: 0; min-height: 100vh; display: grid; place-items: center;
            background: #0b0d10; color: #eef2ee;
            font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
          }
          main { text-align: center; padding: 2rem; max-width: 22rem; }
          img { width: 8rem; height: 8rem; }
          h1 { font-size: 1.5rem; font-weight: 600; margin: 1.25rem 0 0.5rem; }
          p { margin: 0 0 1.75rem; line-height: 1.5; opacity: 0.72; font-size: 0.95rem; }
          a {
            display: inline-block; padding: 0.85rem 1.6rem; border-radius: 1rem;
            background: rgb(255 255 255 / 10%); color: inherit;
            text-decoration: none; font-weight: 600;
          }
          a:hover, a:focus { background: rgb(255 255 255 / 16%); }
        </style>
      </head>
      <body>
        <main>
          <img src="/pwa/icon-512.png" alt="">
          <h1>Shrublab</h1>
          <p>
            Add this page to your home screen from your browser menu, then open the app to sign in.
          </p>
          <a href="/if/user/">Open the dashboard</a>
        </main>
      </body>
    </html>
  '';

  ingressSelected = lib.hasAttrByPath [ "services" "ingress" "role" ] options;
  routePublished = ingressSelected && config.services.ingress.routes ? "authentik-admin";
in
{
  imports = [ ../../web/_ingress-static.nix ];

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !ingressSelected || routePublished;
          message = "authentik: the sign-in PWA mounts on the published `authentik-admin` route; the edge publishes no such route.";
        }
      ];
    }
    (lib.mkIf routePublished {
      services.ingress.staticPages."authentik-admin" = {
        "/pwa" = installPage;
        "/pwa/manifest.json" = manifest;
        "/pwa/icon-192.png" = "${icons}/icon-192.png";
        "/pwa/icon-512.png" = "${icons}/icon-512.png";
        "/pwa/icon-maskable-512.png" = "${icons}/icon-maskable-512.png";
        "/pwa/apple-touch-icon.png" = "${icons}/apple-touch-icon.png";
      };
    })
  ];
}
