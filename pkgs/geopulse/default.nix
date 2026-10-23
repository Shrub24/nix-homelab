{
  lib,
  symlinkJoin,
  writeShellApplication,
  python3,
  cacert,
  nix,
  nix-update,
  git,
  patch,
  geopulseRelease,
  geopulseBackend,
  geopulseFrontend,
}:
let
  inherit (geopulseRelease) version;

  updater = writeShellApplication {
    name = "geopulse-update";
    runtimeInputs = [
      python3
      cacert
      nix
      nix-update
      git
      patch
    ];
    text = ''
      export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
      exec python3 ${./update.py} "$@"
    '';
  };
in
# The registered owner: the batch keys a package's write set on the registered output name,
# so the release is `geopulse` and both halves stay derived from one pin.
symlinkJoin {
  pname = "geopulse";
  inherit version;
  paths = [
    geopulseBackend
    geopulseFrontend
  ];

  passthru = {
    # Cheap release check for `--check`: the newest stable upstream release,
    # compared against `version` by the batch.
    checkUpdate = writeShellApplication {
      name = "geopulse-check-update";
      runtimeInputs = [
        python3
        cacert
      ];
      text = ''
        export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
        exec python3 ${./update.py} --check
      '';
    };

    # Run by the batch through nix-update's update-script path: one updater for
    # the release pin and both dependency hashes.
    updateScript = lib.getExe updater;
  };

  meta = {
    description = "GeoPulse location-history platform, Quarkus backend and Vue frontend";
    homepage = "https://github.com/tess1o/geopulse";
    changelog = "https://github.com/tess1o/geopulse/releases/tag/v${version}";
    license = lib.licenses.bsl11;
    platforms = lib.platforms.linux;
  };
}
