# Builder-access aspect. nix-fleet owns the SSH trust mechanism (known-hosts
# entries and the client tuning block); this contributor names the fleet's
# remote builder, so hosts select the aspect and the endpoint arrives with it.
{ inputs, ... }:
{
  flake.modules.nixos.builder-access = {
    imports = [ inputs.nix-fleet.modules.nixos.builder-access ];

    services.builder-access.hosts.nixbuild = {
      hostNames = [ "eu.nixbuild.net" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM";
    };
  };
}
