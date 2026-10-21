{
  lib,
  buildNpmPackage,
  nodejs_24,
  src,
  version,
}:
buildNpmPackage {
  pname = "geopulse-frontend";
  inherit version;
  # The frontend is a subdirectory of the upstream repository. 2.0 declares
  # `engines.node >= 24.15` and builds on Vite 8, so the toolchain follows it.
  src = "${src}/frontend";
  nodejs = nodejs_24;
  npmDepsHash = "sha256-PUq6t3cNKUxihbNYmC/KxnX0PCuvsK2LgXsa2pocLAI=";
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
