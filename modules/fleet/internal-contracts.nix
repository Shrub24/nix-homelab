# Internal transport contracts (Stage 8 task 4.1, HIC-4). Two services are
# consumed across host boundaries: the shared PostgreSQL substrate and the
# private Niks3 write API. Cross-host consumers resolve them through this
# typed contract instead of restating a provider host name, and a provider
# rename, a lost capability, or a moved port fails loudly with a named
# `internal-contracts:` error.
#
# Two surfaces come out of this file:
#   * `flake.internalContracts` — the validated, resolved projection (provider
#     ID, port, and resolved private endpoints `host`/`fqdn`/`url`). Forcing it
#     runs every check below.
#   * `flake.modules.nixos.internal-contracts` — the per-host typed surface
#     consumers read (`config.repo.internal.*`). It carries the pure resolution
#     only, so selecting this aspect on the provider host itself cannot recurse
#     into the provider's own evaluation.
#
# Resolution derives from identity, never from literals: the FQDN is the
# provider record's derived `tailscale.fqdn` (HIC-1), which itself derives from
# the single tailnet suffix authority (`policy/globals.nix`, task 3.2).
#
# Named fail-closed checks:
#   1. unknown provider — the named host is not a declared canonical host ID;
#   2. provider/aspect mismatch — the provider's materialized configuration
#      does not enable the capability the contract requires (a real evaluated
#      check: `attrByPath` returns the documented default `false`, so a dropped
#      aspect fails as a missing capability rather than a missing attribute);
#   3. declared port drift — the contract's port disagrees with the port the
#      provider host actually listens on.
# Checks 2 and 3 evaluate the provider host's materialized configuration, so
# they are forced by `flake.internalContracts` (flake outputs and checks), not
# by host evaluation.
top@{ lib, ... }:
let
  suffix = (import ../../policy/globals.nix).tailnet.suffix;
  hosts = top.config.nixos.hosts;

  # The fleet's internal transport topology: one declaration per contract.
  # `capabilityPath` is the enable option the provider host must have true;
  # `listen` is the provider option holding the actual port, with `kind`
  # selecting the parse ("port" for an integer option, "address" for a
  # `<host>:<port>` listen address).
  declarations = {
    postgres = {
      provider = "oci-melb-1";
      port = 5432;
      scheme = "postgresql";
      capabilityPath = [
        "services"
        "postgres-shared"
        "enable"
      ];
      listen = {
        path = [
          "services"
          "postgresql"
          "settings"
          "port"
        ];
        kind = "port";
      };
    };

    niks3Write = {
      provider = "oci-melb-1";
      port = 5751;
      scheme = "http";
      capabilityPath = [
        "services"
        "niks3-cache"
        "enable"
      ];
      listen = {
        path = [
          "services"
          "niks3"
          "httpAddr"
        ];
        kind = "address";
      };
    };
  };

  declarationNames = builtins.attrNames declarations;

  # Pure resolution: provider record data plus the suffix authority. Safe to
  # force from any host evaluation (no cross-host configuration is evaluated).
  pureResolution = lib.mapAttrs (
    _: decl:
    let
      record = hosts.${decl.provider} or null;
      fqdn = if record == null then null else record.tailscale.fqdn;
    in
    {
      inherit (decl) provider port scheme;
      host = if record == null then null else record.tailscale.hostname;
      inherit fqdn;
      url = "${decl.scheme}://${fqdn}:${toString decl.port}";
    }
  ) declarations;

  unknownProviderErrors = lib.filter (error: error != "") (
    map (
      name:
      let
        decl = declarations.${name};
      in
      if hosts ? ${decl.provider} then
        ""
      else
        "internal-contracts: contract '${name}' names unknown provider '${decl.provider}', which is not a declared canonical host ID"
    ) declarationNames
  );

  # Guarded so an unknown provider yields the named error below instead of a
  # raw missing-attribute failure while the capability check is being built.
  providerConfigOf =
    name:
    let
      record = hosts.${declarations.${name}.provider} or null;
    in
    if record == null then null else record.configuration.config;

  readListenPort =
    decl: cfg:
    let
      raw = lib.attrByPath decl.listen.path null cfg;
    in
    if raw == null then
      null
    else if decl.listen.kind == "address" then
      lib.toInt (lib.last (lib.splitString ":" raw))
    else
      lib.toInt (toString raw);

  capabilityErrors = lib.concatMap (
    name:
    let
      decl = declarations.${name};
      cfg = providerConfigOf name;
    in
    if cfg == null then
      [ ]
    else
      let
        enabled = lib.attrByPath decl.capabilityPath false cfg;
        actualPort = readListenPort decl cfg;
      in
      lib.optionals (!enabled) [
        "internal-contracts: provider host '${decl.provider}' does not enable '${lib.concatStringsSep "." decl.capabilityPath}' required by contract '${name}'; the provider host must select the aspect that enables it"
      ]
      ++ lib.optionals (actualPort != null && actualPort != decl.port) [
        "internal-contracts: provider host '${decl.provider}' listens on port ${toString actualPort} but contract '${name}' declares ${toString decl.port}"
      ]
  ) declarationNames;

  # Fail closed twice: the pure resolution is usable by host evaluation and the
  # validated projection additionally proves provider capability and port.
  # Unknown providers dominate, so the capability check is only forced once
  # every provider is a declared canonical host.
  resolution = lib.throwIf (
    unknownProviderErrors != [ ]
  ) (lib.concatStringsSep "; " unknownProviderErrors) pureResolution;

  validatedContracts =
    lib.throwIf (unknownProviderErrors != [ ]) (lib.concatStringsSep "; " unknownProviderErrors)
      (lib.throwIf (capabilityErrors != [ ]) (lib.concatStringsSep "; " capabilityErrors) resolution);
in
{
  flake.internalContracts = validatedContracts;

  flake.modules.nixos.internal-contracts =
    {
      config,
      lib,
      ...
    }:
    let
      contractOption =
        extra:
        lib.mkOption (
          {
            readOnly = true;
          }
          // extra
        );
      endpointOptions = {
        scheme = contractOption {
          type = lib.types.str;
          description = "URL scheme of the resolved private endpoint.";
        };
        provider = contractOption {
          type = lib.types.str;
          description = "Canonical host ID of the contract provider.";
        };
        port = contractOption {
          type = lib.types.port;
          description = "TCP port the provider listens on for this contract.";
        };
        host = contractOption {
          type = lib.types.str;
          description = "Short Tailscale hostname of the provider host.";
        };
        fqdn = contractOption {
          type = lib.types.str;
          description = "Tailscale FQDN derived from the provider's canonical host record.";
        };
        url = contractOption {
          type = lib.types.str;
          description = "Resolved private endpoint URL for this contract.";
        };
      };
    in
    {
      options.repo.internal = {
        postgres = lib.mkOption {
          type = lib.types.submodule { options = endpointOptions; };
          readOnly = true;
          description = "Resolved shared-PostgreSQL transport contract (HIC-4).";
        };
        niks3Write = lib.mkOption {
          type = lib.types.submodule { options = endpointOptions; };
          readOnly = true;
          description = "Resolved Niks3 write-API transport contract (HIC-4).";
        };
      };

      # Explicit `config` attrset: this module also declares options, and a
      # module that uses `config.<path>` may not also use implicit top-level
      # options (the module system rejects the mix).
      config = {
        repo.internal = resolution;

        # Suffix agreement is part of the contract: a record whose FQDN leaves
        # the single tailnet suffix authority would otherwise resolve a private
        # endpoint outside the fleet's tailnet.
        assertions = [
          {
            assertion = lib.all (contract: lib.hasSuffix ".${suffix}" contract.fqdn || contract.fqdn == null) (
              lib.attrValues resolution
            );
            message = "internal-contracts: resolved provider FQDN must sit under the '${suffix}' tailnet suffix from policy/globals.nix";
          }
        ];
      };
    };
}
