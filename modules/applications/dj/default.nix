{
  lib,
  config,
  ...
}:
{
  imports = [
    ./engine-dj.nix
  ];

  options.applications.dj.enable = lib.mkEnableOption "DJ application composition (Windows VM workloads)";
}
