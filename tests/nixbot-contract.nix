# nixbot's placement contract: the service wiring the operator cannot verify by
# reading the module, and the policy the fleet depends on.
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
  failedAssertions = builtins.filter (a: !a.assertion) c.assertions;
  daemon = c.systemd.services.nixbot;
  listenHost = lib.head (lib.splitString ":" c.systemd.sockets.nixbot.socketConfig.ListenStream);
  builderKeys = map (b: b.sshKey) c.nix.buildMachines;
  checks = {
    loopback = listenHost == "127.0.0.1" || listenHost == "::1" || listenHost == "localhost";
    authenticated =
      !c.services.nixbot.allowUnauthenticatedControl && c.services.nixbot.proxyAuthHeader == null;
    admission =
      c.services.nixbot.github.userAllowlist == null
      && c.services.nixbot.github.repoAllowlist == [ "Shrub24/nix-homelab" ]
      && c.services.nixbot.prApproval.enable;
    evaluation = daemon.environment.NIX_CONFIG == "allow-import-from-derivation = false";
    noEffects =
      c.services.nixbot.effects.perRepoSecretFiles == { } && c.services.nixbot.effects.mountables == { };
    database =
      c.services.postgres.consumers ? nixbot
      && builtins.elem "postgresql-provision.service" daemon.after
      && builtins.elem "postgresql-provision.service" daemon.requires;
    backup =
      c.services.state-backups.services ? nixbot && daemon.serviceConfig.StateDirectoryMode == "0700";
    failureNotification = c.services.notify.events ? nixbot;
    streaming = builtins.elem "niks3-auth-token:${c.sops.secrets.nixbot_cache_token.path}" daemon.serviceConfig.LoadCredential;
    architectures =
      c.services.nixbot.buildSystems == [
        "x86_64-linux"
        "aarch64-linux"
      ]
      && builtins.any (b: lib.hasInfix "aarch64-linux" b.system) c.nix.buildMachines;
    # Every builder trusts the coordinator key through the secret's own path, so
    # the binding cannot drift from the file sops actually renders.
    keyIsolation =
      builderKeys != [ ]
      && builtins.all (k: k == c.sops.secrets.nixbot_builder_key.path) builderKeys
      && c.sops.secrets.nixbot_builder_key.owner == "root";
    publishedRoute =
      config.flake.nixosConfigurations.oci-melb-1.config.services.ingress.routes ? nixbot;
    route = !c.repo.web.catalog.nixbot.access.requireCloudflareAccess;
    unrelatedHost = !(config.flake.nixosConfigurations.la-admin-1.config.services ? nixbot);
  };
  failures = builtins.attrNames (lib.filterAttrs (_: ok: !ok) checks);
in
assert lib.assertMsg (failedAssertions == [ ]) (
  lib.concatMapStringsSep "\n" (a: a.message) failedAssertions
);
assert lib.assertMsg (
  failures == [ ]
) "nixbot contract failed: ${lib.concatStringsSep ", " failures}";
pkgs.runCommandLocal "nixbot-contract" { } "touch $out"
