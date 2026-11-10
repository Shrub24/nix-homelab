{
  config,
  inputs,
  ...
}:
let
  policy = import ../../policy/nixbot.nix;
  profile = inputs.nix-fleet.lib.buildProfile;
  builders = profile.resolveBuildProfile config.fleet "ci";
in
{
  flake.modules.nixos.nixbot =
    {
      config,
      lib,
      options,
      pkgs,
      ...
    }:
    let
      cfg = config.services.nixbot;
      secrets = import ../../lib/secrets.nix { inherit lib; };
      route = config.repo.web.catalog.nixbot;
      localPostgres =
        if lib.hasAttrByPath [ "services" "postgres" "localEndpoint" ] options then
          config.services.postgres.localEndpoint
        else
          null;
      remoteBuilders = builtins.filter (b: b.name != config.networking.hostName) builders;
      builderSpecs = map (b: b // { sshKeyPath = runtimePath "builder_key"; }) remoteBuilders;
      runtimePath = name: "/run/secrets/nixbot.${name}";
      secretMap = lib.mapAttrs (_: spec: spec // { restartUnits = [ "nixbot.service" ]; }) {
        nixbot_github_app_key = {
          key = "github/app_key";
          path = runtimePath "github_app_key";
        };
        nixbot_webhook_secret = {
          key = "github/webhook_secret";
          path = runtimePath "webhook_secret";
        };
        nixbot_oauth_secret = {
          key = "github/oauth_secret";
          path = runtimePath "oauth_secret";
        };
        nixbot_builder_key = {
          key = "builder/private_key";
          path = runtimePath "builder_key";
        };
        nixbot_cache_token = {
          key = "cache/token";
          path = runtimePath "cache_token";
        };
      };
    in
    {
      imports = [
        inputs.nixbot.nixosModules.nixbot
        ../database/postgres/_consumer.nix
        ../backups/state-backups/_consumer.nix
      ];

      options.services.nixbot.secretFiles.host = secrets.mkSecretFileOption "nixbot-service";

      config = {
        services.nixbot.enable = true;
        # The cluster is a cross-aspect dependency: without it the connection string
        # silently targets port 5432 rather than failing.
        assertions = [
          {
            assertion = localPostgres != null;
            message = "services.nixbot: select postgres and declare this host's cluster.";
          }
        ];

        services.nixbot = {
          secretFiles.host = lib.mkDefault ../../secrets/services/nixbot.yaml;
          domain = route.publicHost;
          port = route.upstreamPort;
          useHTTPS = true;
          nginx.enable = false;
          admins = policy.github.admins;
          github = {
            enable = true;
            appId = policy.github.appId;
            oauthId = policy.github.oauthId;
            appSecretKeyFile = runtimePath "github_app_key";
            webhookSecretFile = runtimePath "webhook_secret";
            oauthSecretFile = runtimePath "oauth_secret";
            repoAllowlist = builtins.attrNames (import ../../policy/ci-repositories.nix);
          };
          oidc.enable = false;
          proxyAuthHeader = null;
          allowUnauthenticatedControl = false;
          prApproval = {
            enable = true;
            trustedAssociations = [
              "OWNER"
              "MEMBER"
              "COLLABORATOR"
            ];
          };
          buildSystems = [
            "x86_64-linux"
            "aarch64-linux"
          ];
          evalSystems = cfg.buildSystems;
          evalWorkerCount = 2;
          evalMaxMemorySize = 3072;
          buildConcurrency = 2;
          database = {
            createLocally = false;
            url = "postgresql://nixbot@/nixbot?host=/run/postgresql&port=${
              toString (if localPostgres == null then 5432 else localPostgres.port)
            }";
          };
          niks3 = {
            enable = true;
            package = inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.default;
            serverUrl = config.repo.web.catalog."niks3-write".endpoint.url;
            authTokenFile = runtimePath "cache_token";
          };
        };

        # A bare systemd port listens on every interface, not just loopback.
        systemd.sockets.nixbot.socketConfig.ListenStream = lib.mkForce "127.0.0.1:${toString cfg.port}";
        systemd.services.nixbot = {
          environment.NIX_CONFIG = "allow-import-from-derivation = false";
          requires = [
            "postgresql-setup.service"
            "postgresql-provision.service"
          ];
          after = [
            "postgresql-setup.service"
            "postgresql-provision.service"
          ];
        };
        services.postgres.consumers.nixbot = {
          database = "nixbot";
          auth = "peer";
        };
        services.state-backups.services.nixbot = {
          mode = "live";
          paths = [ "/var/lib/nixbot" ];
        };
        services.notify.events.nixbot = { };

        nix.distributedBuilds = true;
        nix.buildMachines = profile.buildMachines builderSpecs;
        programs.ssh.knownHosts = profile.knownHosts remoteBuilders;
        programs.ssh.extraConfig = profile.sshConfig remoteBuilders;
        sops.secrets = secrets.mkSecretsFromMap cfg.secretFiles.host secretMap;
      };
    };
}
