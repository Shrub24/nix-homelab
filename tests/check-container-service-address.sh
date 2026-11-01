#!/usr/bin/env bash
# Containers reaching a native service on their own host.
#
# A container cannot dial the host's loopback, and `host.containers.internal`
# resolves to whichever bridge gateway the container's own network happens to
# have — and traffic on that path arrives on the host input chain where nothing
# admits it. The fleet therefore publishes a stable service address
# (`policy/globals.nix` `serviceNetwork`) and each container names it. Two things
# follow, and neither is visible to any Nix check:
#
#   - a bridged container that names the service address needs the `--add-host`
#     entry that resolves it, because Podman's internal DNS does not know the
#     name. Without it the container starts cleanly and fails to connect at
#     runtime;
# A host-networked container shares the host's namespace, so the name already
# resolves and the entry is neither needed nor asserted.
#
# Deliberately not asserted: that no container dials `host.containers.internal`.
# Whether that works depends on what the target binds — it fails against a
# loopback-plus-service-address listener and succeeds against one bound to
# 0.0.0.0 — so the assertion belongs with the target, not in a fleet-wide rule.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "check-container-service-address: $*" >&2
  exit 1
}

report="$(
  nix eval --json --no-write-lock-file --impure --expr '
    let
      flake = builtins.getFlake (toString ./.);
      network = (import ./policy/globals.nix).serviceNetwork;
      containersOf = cfg: let
        containers = cfg.virtualisation.oci-containers.containers;
        renderedByPath = builtins.listToAttrs (map (name: {
          name = cfg.sops.templates.${name}.path;
          value = cfg.sops.templates.${name}.content;
        }) (builtins.attrNames cfg.sops.templates));
        # The variables in a bound environment file are in the container, so the
        # file content is part of what it can dial with.
        textOf = ctr:
          builtins.concatStringsSep " " (
            builtins.attrValues (ctr.environment or { })
            ++ map (path: renderedByPath.${path} or "") (ctr.environmentFiles or [ ])
          );
      in
      builtins.mapAttrs (name: ctr: {
        inherit name;
        options = ctr.extraOptions or [ ];
        text = textOf ctr;
      }) containers;
      hosts = builtins.filter
        (host: flake.nixosConfigurations.${host}.config.virtualisation.oci-containers.containers != { })
        (builtins.attrNames flake.nixosConfigurations);
    in {
      inherit (network) hostName address;
      containers = builtins.listToAttrs (map (host: {
        name = host;
        value = containersOf flake.nixosConfigurations.${host}.config;
      }) hosts);
    }'
)" || fail "the container inventory does not evaluate"

printf '%s' "$report" | python3 -c '
import json, sys

got = json.load(sys.stdin)
name, address = got["hostName"], got["address"]
hosts = got["containers"]
errs = []
bridged = 0

for host in sorted(hosts):
    for container_name in sorted(hosts[host]):
        container = hosts[host][container_name]
        options, text = container["options"], container["text"]
        label = host + "/" + container_name
        if name not in text:
            continue
        # A host-networked container shares the hosts namespace, where the name
        # already resolves; only a bridged dial needs the entry.
        if any(o == "--network=host" or o.startswith("--network=host,") for o in options):
            continue
        bridged += 1
        entries = [o for o in options if o.startswith("--add-host=" + name + ":")]
        if not entries:
            errs.append(
                label + " names " + name + " but carries no --add-host=" + name + ":<address>;"
                " podman internal DNS does not resolve it, so the dial fails at runtime"
            )
        elif ("--add-host=" + name + ":" + address) not in entries:
            errs.append(label + " resolves " + name + " to something other than the service address " + address)

if not hosts:
    errs.append("no host runs containers; this check inspected nothing")
if not bridged:
    errs.append("no bridged container dials the service address; this check inspected nothing")
if errs:
    print("\n".join("  " + e for e in errs), file=sys.stderr)
    sys.exit(1)
print("check-container-service-address: PASS (" + str(bridged) + " bridged container(s) dial "
      + name + " across " + str(len(hosts)) + " host(s))")
' || fail "service-address coupling violated"
