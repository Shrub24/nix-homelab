# The repository's nixbot effects, from nix-fleet's shared module: main-push
# retention and the scheduled update transaction.
{ config, inputs, ... }:
let
  home-forge = config.flake.nixosConfigurations.home-forge.config;
  system = config.nixos.hosts.home-forge.system;
  policy = import ../../policy/nixbot.nix;
in
{
  imports = [ inputs.nix-fleet.flakeModules.nixbotEffects ];

  nixbotEffects = {
    inherit system;
    nixPackage = home-forge.nix.package;
    cacheRetain = {
      enable = true;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      cacheUrl = config.flake.nixosConfigurations.oci-melb-1.config.services.niks3-cache.cacheUrl;
      writeEndpoint = home-forge.repo.web.catalog."niks3-write".endpoint.url;
      niks3Package = config.flake.packages.${system}.niks3;
    };
    packageUpdates = {
      enable = true;
      when = {
        minute = 43;
        hour = [ 4 ];
        dayOfWeek = [ "Mon" ];
      };
      autoMerge = policy.updateAutoMerge;
    };
  };
}
