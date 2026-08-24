{
  lib,
  config,
  ...
}:
let
  policyLib = import ../../lib/policy.nix { inherit lib; };
  webServicesPolicy = import ../../policy/web-services.nix;
  currentHostName = config.networking.hostName or null;
  resolvedHosts = lib.mapAttrs (hostName: _host: {
    primaryDomain = policyLib.resolvePrimaryDomain webServicesPolicy hostName;
    services = policyLib.resolveHostServices webServicesPolicy hostName;
    cloudflare.hosts = policyLib.resolveCloudflareHosts webServicesPolicy hostName;
  }) (webServicesPolicy.hosts or { });

  catalog = policyLib.serviceCatalog webServicesPolicy;
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
    catalog = catalog;
    currentHost =
      if currentHostName != null && builtins.hasAttr currentHostName resolvedHosts then
        resolvedHosts.${currentHostName}
      else
        { };
  };
}
