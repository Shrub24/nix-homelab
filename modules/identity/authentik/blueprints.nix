# Delivers the generated blueprint beside the provider's own, which supplies the default
# flows, stages and scope mappings the generated entries reference.
{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.authentik-blueprint-tools =
        pkgs.runCommand "check-authentik-blueprint-tools"
          { nativeBuildInputs = [ (import ./_blueprint/tools.nix { inherit pkgs; }).python ]; }
          ''
            python ${self}/tests/test-authentik-blueprints.py
            touch "$out"
          '';
    };

  flake.modules.nixos.authentik-identity =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      identityPolicy = import ../../../policy/identity.nix;
      blueprintDocument = import ./_blueprint/document.nix;
      enabledClients = lib.filterAttrs (_name: client: client.enable or true) identityPolicy.clients;

      providerRoute = config.repo.web.catalog.${identityPolicy.providers.authentik.route};
      blueprint = pkgs.writeText "homelab-identity.json" (
        builtins.toJSON (blueprintDocument {
          inherit lib;
          inherit (identityPolicy) groups users links;
          inherit (identityPolicy.providers.authentik)
            groupParents
            superuserGroups
            appRoles
            brand
            enrollment
            ;
          providerDomain = providerRoute.publicHost;
          clients = enabledClients;
          routeFor = name: config.repo.web.catalog.${(enabledClients // identityPolicy.links).${name}.route};
        })
      );
    in
    {
      imports = [ ./_blueprint/gate.nix ];
      sops.templates."authentik.env".restartUnits = [ "authentik-blueprint-validate.service" ];
      services.notify.events."authentik-blueprint-validate".failure = { };
      services.authentik.settings.blueprints_dir =
        pkgs.runCommandLocal "authentik-blueprints"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              (import ./_blueprint/tools.nix { inherit pkgs; }).tool
            ];
          }
          ''
            mkdir -p $out
            cp -r ${config.services.authentik.authentikComponents.staticWorkdirDeps}/blueprints/. $out/
            authentik-blueprint-tools --schema $out/schema.json \
              --output $out/homelab-identity.yaml ${blueprint}
          '';
    };
}
