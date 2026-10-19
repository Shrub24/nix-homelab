{
  lib,
  buildNpmPackage,
  nodejs_22,
  src,
  version,
}:
buildNpmPackage {
  pname = "geopulse-frontend";
  inherit version;
  # The frontend is a subdirectory of the upstream repository. Node 20 is no
  # longer packaged in this nixpkgs; Vite 4 builds on Node 22.
  src = "${src}/frontend";
  nodejs = nodejs_22;
  npmDepsHash = "sha256-Gc2qCgjIhNicIMqP4RGyz1gsWYZDN6nczcVsprCg+eY=";
  dontNpmInstall = true;

  installPhase = ''
    runHook preInstall
    cp -r dist $out
    install -Dm644 ${src}/LICENSE $out/share/licenses/geopulse/LICENSE
    runHook postInstall
  '';

  meta = {
    description = "GeoPulse frontend (Vite build)";
    license = lib.licenses.bsl11;
    platforms = lib.platforms.linux;
  };
}
