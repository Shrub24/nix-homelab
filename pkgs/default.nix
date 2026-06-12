{ callPackage }:
{
  notification-daemon = callPackage ./notification-daemon { };
  notify = callPackage ./notify { };
  nix-path-filter = callPackage ./nix-path-filter { };
}
