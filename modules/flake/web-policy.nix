top: {
  flake.modules.nixos.web-policy =
    {
      lib,
      config,
      ...
    }:
    let
      policyLib = import ../../lib/policy.nix { inherit lib; };
      webServicesPolicy = import ../../policy/web-services.nix;

      # Every host-backed reference in the web data must name a declared
      # canonical host ID, and every host-backed origin FQDN must equal the
      # record's derived tailscale.fqdn. Externally managed names (public
      # domains, 127.0.0.1 loopback) stay literal and are never classified as
      # host-backed. Unknown references fail closed at flake evaluation.
      tailnetSuffix = (import ../../policy/globals.nix).tailnet.suffix;
      canonicalHosts = top.config.nixos.hosts;
      canonicalFqdns = lib.mapAttrsToList (_: host: host.tailscale.fqdn) canonicalHosts;
      policyHosts = webServicesPolicy.hosts or { };

      unknownHostKeys = lib.filter (name: !(canonicalHosts ? ${name})) (builtins.attrNames policyHosts);

      allOrigins = lib.concatMap (
        hostName:
        let
          services = policyHosts.${hostName}.services or { };
        in
        lib.mapAttrsToList (_: svc: svc.origin.host or null) services
      ) (builtins.attrNames policyHosts);

      hostBackedOrigins = lib.filter (h: h != null && lib.hasSuffix ".${tailnetSuffix}" h) allOrigins;
      unknownOrigins = lib.filter (h: !(builtins.elem h canonicalFqdns)) hostBackedOrigins;

      checkedPolicy =
        lib.throwIf (unknownHostKeys != [ ])
          (lib.concatMapStringsSep "; " (
            name: "web-policy: unknown host reference '${name}' is not a declared canonical host ID"
          ) unknownHostKeys)
          (
            lib.throwIf (unknownOrigins != [ ]) (lib.concatMapStringsSep "; " (
              fqdn: "web-policy: origin FQDN '${fqdn}' does not match any declared canonical host identity"
            ) unknownOrigins) webServicesPolicy
          );

      currentHostName = config.networking.hostName or null;
      resolvedHosts = lib.mapAttrs (hostName: _host: {
        primaryDomain = policyLib.resolvePrimaryDomain checkedPolicy hostName;
        services = policyLib.resolveHostServices checkedPolicy hostName;
        cloudflare.hosts = policyLib.resolveCloudflareHosts checkedPolicy hostName;
      }) (checkedPolicy.hosts or { });

      catalog = policyLib.serviceCatalog checkedPolicy;
    in
    {
      options.repo.web = {
        hosts = lib.mkOption {
          type = lib.types.attrs;
          readOnly = true;
          description = "Resolved web-services policy for all hosts.";
        };

        catalog = lib.mkOption {
          type = lib.types.attrs;
          readOnly = true;
          description = "Canonical cross-host service catalog keyed by stable service ID.";
        };

        currentHost = lib.mkOption {
          type = lib.types.attrs;
          readOnly = true;
          description = "Resolved web-services policy for the current host.";
        };
      };

      config.repo.web = {
        hosts = resolvedHosts;
        inherit catalog;
        currentHost =
          if currentHostName != null && builtins.hasAttr currentHostName resolvedHosts then
            resolvedHosts.${currentHostName}
          else
            { };
      };
    };
}
