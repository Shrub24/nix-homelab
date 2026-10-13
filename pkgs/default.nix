{ callPackage }:
let
  geopulseRelease = callPackage ./geopulse/source.nix { };
  geopulseBackend = callPackage ./geopulse/backend.nix {
    inherit (geopulseRelease) src version;
  };
  geopulseFrontend = callPackage ./geopulse/frontend.nix {
    inherit (geopulseRelease) src version;
  };
in
{
  windows-dj-setup = callPackage ./windows-dj-setup { };
  geopulse = callPackage ./geopulse {
    inherit geopulseRelease geopulseBackend geopulseFrontend;
  };
  geopulse-backend = geopulseBackend;
  geopulse-frontend = geopulseFrontend;
}
