# nixbot's placement contract: the cross-aspect wiring the operator cannot verify
# by reading the module, and the trust the cache and the builders depend on.
{
  config,
  lib,
  pkgs,
}:
let
  fixture = { lib, ... }: {
    services.nixbot = {
      secretFiles.host = ./fixtures/nixbot-secret.yaml;
      github.appId = lib.mkOverride 90 123;
      github.oauthId = lib.mkOverride 90 "fixture-client";
      admins = lib.mkOverride 90 [ "github:fixture-admin" ];
    };
  };
  system = config.flake.nixosConfigurations.home-forge.extendModules { modules = [ fixture ]; };
  c = system.config;
  daemon = c.systemd.services.nixbot;
  builderKeys = map (b: b.sshKey) c.nix.buildMachines;
  checks = {
    database =
      c.services.postgres.consumers ? nixbot
      && builtins.elem "postgresql-provision.service" daemon.requires;
    backup = c.services.state-backups.services ? nixbot;
    failureNotification = c.services.notify.events ? nixbot;
    streaming = builtins.elem "niks3-auth-token:${c.sops.secrets.nixbot_cache_token.path}" daemon.serviceConfig.LoadCredential;
    # The architectures the fleet can actually build for, from the inventory.
    architectures = builtins.any (b: lib.hasInfix "aarch64-linux" b.system) c.nix.buildMachines;
    # Every builder trusts the coordinator key through the secret's own path, so
    # the binding cannot drift from the file sops actually renders.
    keyIsolation =
      builderKeys != [ ] && builtins.all (k: k == c.sops.secrets.nixbot_builder_key.path) builderKeys;
    publishedRoute =
      config.flake.nixosConfigurations.oci-melb-1.config.services.ingress.routes ? nixbot;
  };
  failures = builtins.attrNames (lib.filterAttrs (_: ok: !ok) checks);
in
assert lib.assertMsg (
  failures == [ ]
) "nixbot contract failed: ${lib.concatStringsSep ", " failures}";
pkgs.runCommandLocal "nixbot-contract" { } "touch $out"
