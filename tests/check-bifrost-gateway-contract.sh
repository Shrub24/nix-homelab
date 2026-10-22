#!/usr/bin/env bash
set -euo pipefail

# Bifrost gateway contract (openspec change voyage-embedding-compatibility,
# tasks 2.2/3.3; design VE-1..VE-4).
#
# The gateway runs natively from nix-fleet's dynamically linked build, because
# request filters load as native Go plugins and Go's plugin loader needs the
# binary's package hashes to match the plugin's — the upstream image is static
# and no published variant is dynamic (maximhq/bifrost#2586). nix-fleet owns the
# mechanism (runtime package, service account, application directory, startup
# configuration installation, unit lifecycle, failure notification); this
# repository owns the policy layered on it.
#
# This check is evaluation-only on purpose: it pins the interface this
# repository owns (which binary the unit runs, what the rendered configuration
# contains, what recreates the process, and how it is reached) plus the fleet
# assumptions we now depend on. The artifact itself is proven where it is built,
# on the architecture that runs it.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "check-bifrost-gateway-contract: $*" >&2
  exit 1
}

HOST="${1:-oci-melb-1}"

json="$(
  nix eval --json --no-write-lock-file --apply 'c: let
    envByPath = builtins.listToAttrs (map (n: {
      name = c.sops.templates.${n}.path;
      value = c.sops.templates.${n}.content;
    }) (builtins.attrNames c.sops.templates));
  in {
    renderedConfig = c.services.bifrost.renderedConfig;
    renderedConfigFile = c.services.bifrost.renderedConfigFile;
    runtimePackageName = c.services.bifrost.package.name;
    dataDir = c.services.bifrost.dataDir;
    execStart = c.systemd.services.bifrost.serviceConfig.ExecStart;
    preStart = c.systemd.services.bifrost.preStart;
    serviceUser = c.systemd.services.bifrost.serviceConfig.User;
    readWritePaths = c.systemd.services.bifrost.serviceConfig.ReadWritePaths or [ ];
    restartTriggers = c.systemd.services.bifrost.restartTriggers or [ ];
    secretsFile = toString c.services.bifrost.secretFiles.host;
    pluginPackage = c.repo.packages.bifrost-voyage-plugin;
    containerAbsent = !(c.virtualisation.oci-containers.containers ? bifrost);
    containerBaseUrl = c.services.bifrost.endpoint.containerBaseUrl;
    gatewayPort = c.services.bifrost.port;
    localEndpoint = c.services.bifrost.localEndpoint;
    # The co-located AI consumers, read as they are wired: Latitude renders its
    # gateway dial into its environment file, Hindsight passes the value in the
    # container environment itself.
    latitudeEnv = c.sops.templates."latitude.environment".content or "";
    hindsightLlmBaseUrl = ((c.virtualisation.oci-containers.containers or { }).hindsight or { }).environment.HINDSIGHT_API_LLM_BASE_URL or "";
    docsMcpOpenAiBase = ((c.virtualisation.oci-containers.containers or { }).docs-mcp or { }).environment.OPENAI_API_BASE or "";
    firewallExtra = c.networking.firewall.extraCommands;
    containerEnv = builtins.mapAttrs (_: ctr: {
      options = ctr.extraOptions or [ ];
      text = builtins.concatStringsSep " " (
        (builtins.attrValues (ctr.environment or { }))
        ++ (map (p: envByPath.${p} or "") (ctr.environmentFiles or [ ]))
      );
    }) c.virtualisation.oci-containers.containers;
    notifyRegistered = (c.services.notify.events.bifrost.failure or null) != null;
  }' "path:.#nixosConfigurations.${HOST}.config"
)" || fail "${HOST}: bifrost probe does not evaluate"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf '%s' "$json" >"$tmp"

python3 - "$HOST" "$tmp" <<'PYEOF' || fail "${HOST}: observable gateway contract violated"
import json, os, re, sys

host, path = sys.argv[1], sys.argv[2]
got = json.load(open(path))
errs = []

rendered = got["renderedConfig"]
# Governance routing and dashboard authentication require a persistent store;
# config.json remains the startup authority even when that store is enabled.
store = rendered.get("config_store", {})
if store.get("enabled") is not True:
    errs.append("config_store must be enabled for governance and dashboard authentication")
if store.get("type") != "sqlite" or store.get("config", {}).get("path") != f"{got['dataDir']}/config.db":
    errs.append(f"config_store must use the application directory's SQLite database: {store!r}")
if rendered.get("source_of_truth") != "config.json":
    errs.append("source_of_truth must remain config.json")
rendered_file = got["renderedConfigFile"]
if not rendered_file.endswith("bifrost-config.json"):
    errs.append(f"renderedConfigFile {rendered_file!r} is not the rendered config document")

# VE-1: the normalizer is registered exactly once, as a native plugin, and the
# registration is what the runtime loads rather than a restated document. Only
# `services.bifrost.plugins` may own the plugins member.
plugins = [p for p in rendered.get("plugins", []) if p.get("name") == "voyage-normalizer"]
if len(plugins) != 1:
    errs.append(f"voyage-normalizer must appear exactly once in the rendered config, found {len(plugins)}")
else:
    entry = plugins[0]
    want_suffix = got["pluginPackage"].rstrip("/") + "/lib/bifrost/voyage.so"
    if entry.get("path") != want_suffix:
        errs.append(f"plugin path {entry.get('path')!r}, want {want_suffix!r}")
    if entry.get("placement") != "post_builtin":
        errs.append(f"plugin placement {entry.get('placement')!r}, want 'post_builtin'")
    if entry.get("enabled") is not True:
        errs.append(f"plugin entry must be enabled, got {entry.get('enabled')!r}")

# The plugins member has exactly one owner, and the rendered list is what the
# runtime loads in order: the built-in exporter first, then the normalizer.
plugin_names = [p.get("name") for p in rendered.get("plugins", [])]
if plugin_names != ["otel", "voyage-normalizer"]:
    errs.append(f"registered plugins are {plugin_names!r}, want ['otel', 'voyage-normalizer']")

otel = [p for p in rendered.get("plugins", []) if p.get("name") == "otel"]
if not otel:
    errs.append("the otel plugin registration must survive the composition")
elif not otel[0].get("config", {}).get("disable_content_logging"):
    errs.append("the otel plugin must keep content logging disabled")

# VE-2: the Voyage upstream stays a custom provider — it is not a Bifrost
# standard provider — and its endpoint is untouched.
voyage = rendered.get("providers", {}).get("voyage", {})
if voyage.get("custom_provider_config", {}).get("request_path_overrides", {}).get(
    "embedding"
) != "https://api.voyageai.com/v1/embeddings":
    errs.append(f"voyage embedding upstream changed: {voyage!r}")
if voyage.get("network_config", {}).get("base_url") != "https://api.voyageai.com/v1":
    errs.append(f"voyage base_url changed: {voyage.get('network_config')!r}")

# Standard providers must not carry a custom_provider_config: v2.2.5 rejects it
# ("cannot be created on standard providers") and its built-in base URLs already
# match ours, so the entry would only be a warning with no effect.
for name in ("deepseek", "opencode-go"):
    if "custom_provider_config" in rendered.get("providers", {}).get(name, {}):
        errs.append(f"{name} is a standard provider and must not carry custom_provider_config")

rules = {r.get("id"): r for r in rendered.get("governance", {}).get("routing_rules", [])}
embedding = rules.get("embedding", {})
targets = embedding.get("targets", [])
if embedding.get("cel_expression") != "model == 'shrublab-embedding'":
    errs.append(f"the embedding routing rule changed: {embedding!r}")
elif [(t.get("provider"), t.get("model")) for t in targets] != [("voyage", "voyage-4")]:
    errs.append(f"the embedding rule must target voyage/voyage-4, got {targets!r}")

# VE-4: a same-provider fallback cannot survive an account-level failure. The
# gateway hands every error class to the chain — including opencode's quota
# refusal, which arrives as a 400 rather than a 429 — so a chain that never
# leaves the provider that failed just re-fails and surfaces the error. The
# embedding rule is exempt: only Voyage serves it, and a different embedding
# provider would silently change the vector space of an existing index.
for rid, rule in rules.items():
    if rid == "embedding":
        continue
    target_providers = {t.get("provider") for t in rule.get("targets", [])}
    fallback_providers = set()
    for fallback in rule.get("fallbacks") or []:
        if isinstance(fallback, str):
            fallback_providers.add(fallback.split("/", 1)[0])
        elif isinstance(fallback, dict):
            fallback_providers.add(fallback.get("provider"))
    if not fallback_providers - target_providers:
        errs.append(
            f"rule {rid!r} falls back only within {sorted(target_providers)} "
            f"(chain {sorted(fallback_providers)}): a provider-wide failure would not be recovered"
        )

# VE-3: the runtime is nix-fleet's binary driven by flags, not a container, and
# the fleet module is what installs the startup configuration.
exec_start = got["execStart"]
if "/bin/bifrost-http" not in exec_start:
    errs.append(f"unit does not run bifrost-http: {exec_start!r}")
if "podman" in exec_start:
    errs.append(f"unit still starts a container: {exec_start!r}")
for flag in ("-app-dir ", "-host ", "-port "):
    if flag not in exec_start:
        errs.append(f"unit is missing {flag!r} in {exec_start!r}")
if not got["containerAbsent"]:
    errs.append("a bifrost oci-containers entry must not exist alongside the native unit")
if got["serviceUser"] != "bifrost":
    errs.append(f"service account {got['serviceUser']!r}, want a dedicated unprivileged account")
if not got["runtimePackageName"].startswith("bifrost-"):
    errs.append(f"runtime package name {got['runtimePackageName']!r} is not the fleet gateway build")

# `dataDir` is the application directory itself. The fleet module writes the
# startup configuration into it and confines writes to it, so both halves are
# observable from the runtime definition rather than from our own options.
app_dir = re.search(r"-app-dir (\S+)", exec_start)
if app_dir is None:
    errs.append(f"unit has no -app-dir in {exec_start!r}")
else:
    if app_dir.group(1) != got["dataDir"]:
        errs.append(f"-app-dir {app_dir.group(1)!r} is not dataDir {got['dataDir']!r}")
    if f"{got['dataDir']}/config.json" not in got["preStart"]:
        errs.append(f"startup configuration is not installed into dataDir: {got['preStart']!r}")
if got["readWritePaths"] != [got["dataDir"]]:
    errs.append(
        f"ReadWritePaths {got['readWritePaths']!r} must be exactly the application directory"
    )

# What recreates the process on a change. The rendered configuration half is the
# fleet module's (the document is content-addressed, so a settings or plugin edit
# moves it); the credential half is ours, because the rendered environment file
# sits at a stable path and systemd cannot see its content change ('s blind
# spot, in a native unit).
if rendered_file not in got["restartTriggers"]:
    errs.append(f"the rendered configuration is not a restart trigger: {got['restartTriggers']!r}")
if got["secretsFile"] not in got["restartTriggers"]:
    errs.append(
        f"the secret file {got['secretsFile']!r} is not a restart trigger, so a credential "
        f"rotation would not reach the process: {got['restartTriggers']!r}"
    )

# The gateway is a native service, so a container reaches it through the host's
# service address — `host.containers.internal` names a bridge gateway the
# container may not share, and traffic on that path arrives on the host input
# chain where nothing admits it. The service address has to be admitted by the
# service itself, for podman's bridge supernet only.
gateway_port = re.search(r"-port (\d+)", exec_start).group(1)
container_url = got["containerBaseUrl"]
match = re.match(r"http://([^:/]+):(\d+)/v1$", container_url)
if "host.containers.internal" in container_url:
    errs.append(f"containerBaseUrl {container_url!r} uses a bridge gateway instead of the service address")
if not match:
    errs.append(f"containerBaseUrl {container_url!r} is not a service-address URL")
elif match.group(2) != gateway_port:
    errs.append(f"containerBaseUrl port {match.group(2)!r} is not the gateway port {gateway_port}")
firewall = got["firewallExtra"]
port_pattern = re.compile(r"--dports\s+(?:\d+,)*" + gateway_port + r"(?:,|\s|$)")
rule_line = next((l for l in firewall.splitlines() if port_pattern.search(l)), None)
if rule_line is None:
    errs.append(f"nothing admits a container to the gateway port {gateway_port}")
elif "-s " not in rule_line or "-d " not in rule_line:
    errs.append(f"the gateway ingress rule is not source- and destination-scoped: {rule_line!r}")

# The other half of the same invariant: a container whose environment names the
# service address needs the entry that resolves it, or it dials a name its own
# resolver has never heard of. Containers that share one environment file are all
# covered, because the variables in it are in each of their environments. Host
# network containers are exempt: they share the host's namespace, where the name
# already resolves.
if match:
    service_name = match.group(1)
    for name, container in got["containerEnv"].items():
        options = container["options"]
        if "--network=host" in options or any(o.startswith("--network=host") for o in options):
            continue
        if service_name not in container["text"]:
            continue
        if not any(o.startswith(f"--add-host={service_name}:") for o in options):
            errs.append(
                f"container {name!r} dials {service_name!r} without --add-host={service_name}:<address>"
            )

# Host-local consumption (nix-fleet's `localEndpoint` contract): the aspect
# publishes the listener as a loopback endpoint, and a consumer running on the
# same host must dial that rather than the canonical cross-fleet route, which
# names the provider host — the catalog alone would send a co-located consumer
# across the tailnet for a socket on this machine. Latitude's containers share
# the host network namespace and Hindsight's container is host-networked, so
# loopback is reachable from both. The port is the canonical one the listener
# binds, so a placement change cannot silently move one side only.
local = got["localEndpoint"]
want_local = f"http://127.0.0.1:{gateway_port}"
if local.get("host") != "127.0.0.1" or str(local.get("port")) != gateway_port or local.get("url") != want_local:
    errs.append(
        f"localEndpoint {local!r} must be this host's loopback listener on the canonical port {gateway_port}"
    )
want_local_v1 = f"{want_local}/v1"
latitude_env = got["latitudeEnv"]
if latitude_env and f"LAT_CUSTOM_AI_BASE_URL={want_local_v1}" not in latitude_env:
    errs.append(
        f"Latitude does not dial the co-located gateway: its environment file has no "
        f"LAT_CUSTOM_AI_BASE_URL={want_local_v1}"
    )
hindsight_url = got["hindsightLlmBaseUrl"]
if hindsight_url and hindsight_url != want_local_v1:
    errs.append(
        f"Hindsight LLM base URL {hindsight_url!r} is not the co-located gateway {want_local_v1!r}"
    )
docs_mcp_base = got["docsMcpOpenAiBase"]
if docs_mcp_base and docs_mcp_base != want_local_v1:
    errs.append(
        f"the docs-mcp embeddings endpoint {docs_mcp_base!r} is not the co-located gateway {want_local_v1!r}"
    )

if not got["notifyRegistered"]:
    errs.append("the gateway must register a failure notification")

if errs:
    print("\n".join(f"  {e}" for e in errs), file=sys.stderr)
    sys.exit(1)
PYEOF

echo "check-bifrost-gateway-contract: PASS (${HOST})"
