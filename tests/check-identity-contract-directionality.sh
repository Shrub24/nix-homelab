#!/usr/bin/env bash
set -euo pipefail

# Focused subset/dependency-direction ratchet for the directional identity
# contracts (openspec change decouple-identity-admin-capabilities, tasks
# 2.1-2.4 and 3.1-3.3). Runs only targeted evaluations; never reads or decrypts secret
# ciphertext, never touches .sops.yaml, and never builds.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "check-identity-contract-directionality: $*" >&2
  exit 1
}

ne() {
  nix eval --no-write-lock-file --raw --apply "$1" "path:.#nixosConfigurations.la-admin-1.config"
}

# 1. Full LA evaluation: Kanidm contract lives under identity ownership and
# the provider consumes the canonical web-policy URL; admin still evaluates.
json="$(ne 'c: builtins.toJSON {
  drv = c.system.build.toplevel.drvPath != "";
  kanidmEnable = c.services.identity.kanidm.enable;
  kanidmAppUrl = c.services.identity.kanidm.appUrl;
  providerUrl = c.services.identity.oidc.providerUrl;
  urlAligned = c.services.identity.oidc.providerUrl == c.services.identity.kanidm.appUrl;
  adminKanidmAbsent = !(c.services.admin ? kanidm);
  oauth2ClientSecrets = builtins.sort builtins.lessThan (builtins.filter (n: builtins.match "kanidm_oauth2.*" n != null) (builtins.attrNames c.sops.secrets));
  # Cockpit and Termix are demoted (2026-09-21): their aspects stay in the
  # tree, but nothing on la-admin-1 selects them, so their namespaces must be
  # absent from the real host configuration.
  cockpitNamespaceAbsent = !(c.services.admin ? cockpit);
  termixNamespaceAbsent = !(c.services.admin ? termix);
  gatusEnable = c.services.gatus.enable;
  gatusListenAligned = c.services.gatus.settings.web.address == "0.0.0.0" && c.services.gatus.settings.web.port == c.repo.web.catalog."gatus-admin".upstreamPort;
  beszelHubEnable = c.services.beszel.hub.enable or false;
  beszelBackupAbsent = !(c.services.state-backups.services ? beszel);
  webhookServiceEnable = c.services.webhook.enable;
}')" || fail "LA config does not evaluate"
python3 - "$json" <<'PYEOF' || fail "directional identity contract observables violated"
import json, sys
got = json.loads(sys.argv[1])
expected = {
    "drv": True,
    "kanidmEnable": True,
    "kanidmAppUrl": "https://id.shrublab.xyz",
    "providerUrl": "https://id.shrublab.xyz",
    "urlAligned": True,
    "adminKanidmAbsent": True,
    "oauth2ClientSecrets": [
        "kanidm_oauth2_beszel_basic_secret",
        "kanidm_oauth2_cloudflare-access_basic_secret",
        "kanidm_oauth2_karakeep_basic_secret",
        "kanidm_oauth2_paperless_basic_secret",
        # The Termix client stays provisioned while its aspect is deselected:
        # re-selecting the aspect must not require a policy or secret edit.
        "kanidm_oauth2_termix_basic_secret",
    ],
    "cockpitNamespaceAbsent": True,
    "termixNamespaceAbsent": True,
    "gatusEnable": True,
    "gatusListenAligned": True,
    "beszelHubEnable": True,
    "beszelBackupAbsent": False,
    "webhookServiceEnable": True,
}
errs = [f"{k}: got {got.get(k)!r} want {v!r}" for k, v in expected.items() if got.get(k) != v]
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

# 2. Provider-only subset: LA without the standalone Webhook aspect and the
# host's admin workload bindings must evaluate; the provider namespace must
# not require the admin namespace (IDB-1). The admin-hub aspect/namespace was
# deleted in task 3.3; non-vacuous absence ratchets live in section 5.
D="$(mktemp -d /tmp/identity-mut.XXXXXX)"
trap 'rm -rf "$D"' EXIT
tar -C "$ROOT" \
  --exclude=.git --exclude=.jj --exclude=./opentofu --exclude=./opentofu/* \
  --exclude=.hp-forge-esp-backup --exclude=.qmd --exclude=.direnv \
  --exclude=.cortexkit --exclude=.tmp --exclude=.pi --exclude=.firecrawl \
  --exclude=.ruff_cache \
  -cf - . | tar -C "$D" -xf -

python3 - "$D" <<'PYEOF' > /dev/null || fail "provider-only mutation script failed"
import re
import sys

d = sys.argv[1]

p = d + "/modules/hosts/la-admin-1/default.nix"
s = open(p).read()
n = s.count("aspects.vaultwarden\n")
assert n == 1, f"vaultwarden selection anchor drifted (count={n})"
assert s.count("        aspects.gatus\n") == 1, "gatus selection anchor drifted"
assert s.count("        aspects.beszel\n") == 1, "beszel selection anchor drifted"
assert s.count("        aspects.homepage\n") == 1, "homepage selection anchor drifted"
assert s.count("        aspects.webhook\n") == 1, "webhook selection anchor drifted"
s = s.replace("        aspects.vaultwarden\n", "", 1)
s = s.replace("        aspects.gatus\n", "", 1)
s = s.replace("        aspects.beszel\n", "", 1)
s = s.replace("        aspects.homepage\n", "", 1)
s = s.replace("        aspects.webhook\n", "", 1)
open(p, "w").write(s)

p = d + "/modules/hosts/la-admin-1/_nixos.nix"
s = open(p).read()
# The applications.admin block, the ./quantum.nix import, the quantum
# force-disable, and the host-local cockpit variant fragment are all gone from
# the host (task 3.3, then the 2026-09-21 demotion); only the workload secret
# bindings below remain to strip.
vaultwarden_secret = "    admin.vaultwarden.secretFiles.host = ../../../secrets/applications/admin.yaml;\n"
assert s.count(vaultwarden_secret) == 1, "vaultwarden secret binding anchor drifted"
s = s.replace(vaultwarden_secret, "", 1)
# Drop the host's direct Homepage secret source: the Homepage leaf is only
# reachable through the `homepage` aspect, so the binding must live in the
# Homepage subset mutation below (task 3.2).
homepage_secret = "    admin.homepage.secretFiles.host = ../../../secrets/applications/admin.yaml;\n"
assert s.count(homepage_secret) == 1, "homepage secret binding anchor drifted"
s = s.replace(homepage_secret, "", 1)
smtp_from_pattern = r"\n *admin\.vaultwarden\.smtpFrom = [^\n]+;"
assert len(re.findall(smtp_from_pattern, s)) == 1, "vaultwarden smtpFrom anchor drifted"
s = re.sub(smtp_from_pattern, "", s, count=1)
open(p, "w").write(s)
PYEOF

json="$(nix eval --no-write-lock-file --raw --apply 'c: builtins.toJSON {
  drv = c.system.build.toplevel.drvPath != "";
  kanidmEnable = c.services.identity.kanidm.enable;
  # `applications` itself is absent when no application stack is selected:
  # absence of the whole namespace satisfies "no admin application".
  adminNamespaceAbsent = !((c.applications or { }) ? admin);
  adminKanidm = c.services.admin.kanidm.enable or null;
  homepageLeafAbsent = !(c.services ? admin) || !(c.services.admin ? homepage);
  webhookServiceEnable = c.services.webhook.enable;
  webhookLeafAbsent = !(c.services ? admin) || !(c.services.admin ? webhook);
  oauth2SecretCount = builtins.length (builtins.filter (n: builtins.match "kanidm_oauth2.*" n != null) (builtins.attrNames c.sops.secrets));
}' "path:${D}#nixosConfigurations.la-admin-1.config")" || fail "provider-only subset (LA without admin-hub/host admin bindings) does not evaluate"
python3 - "$json" <<'PYEOF' || fail "provider-only subset observables violated"
import json, sys
got = json.loads(sys.argv[1])
expected = {
    "drv": True,
    "kanidmEnable": True,
    "adminNamespaceAbsent": True,
    "adminKanidm": None,
    "homepageLeafAbsent": True,
    "webhookServiceEnable": False,
    "webhookLeafAbsent": True,
    # Five provider-owned client secrets: beszel, cloudflare-access,
    # karakeep, paperless, termix (Quantum retired 2026-09-21).
    "oauth2SecretCount": 5,
}
errs = [f"{k}: got {got.get(k)!r} want {v!r}" for k, v in expected.items() if got.get(k) != v]
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

# 3. Client-only subset: the provider-only mutation already deselected the
# admin aspects and the host's admin bindings; additionally deselect
# identity-provider so kanidm-host-auth and web-policy are the only selected
# identity-side concerns. The client contract must still resolve the canonical
# web-policy provider URL (never an accidental null) and must not materialise
# the provider's Kanidm namespace (IDB-2)
# (decouple-identity-admin-capabilities 3.1). `system.build.toplevel` is
# deliberately not forced: this synthetic subset is scoped to option-level
# contract evaluation, and the full option merge still surfaces
# missing-option coupling; full toplevel coverage of the same wiring runs
# against the real LA config in section 1.
python3 - "$D" <<'PYEOF' > /dev/null || fail "client-only mutation script failed"
import sys

d = sys.argv[1]

p = d + "/modules/hosts/la-admin-1/default.nix"
la = open(p).read()
assert la.count("        aspects.identity-provider\n") == 1, "identity-provider selection anchor drifted"
la = la.replace("        aspects.identity-provider\n", "", 1)
s = la
open(p, "w").write(s)
PYEOF

json="$(nix eval --no-write-lock-file --raw --apply 'c: builtins.toJSON {
  kanidmNamespaceAbsent = !(c.services.identity ? kanidm);
  # `applications` itself is absent when no application stack is selected:
  # absence of the whole namespace satisfies "no admin application".
  adminNamespaceAbsent = !((c.applications or { }) ? admin);
  providerUrl = c.services.identity.oidc.providerUrl;
  webPolicyUrl = c.repo.web.catalog."kanidm-admin".publicUrl;
  urlAligned = c.services.identity.oidc.providerUrl == c.repo.web.catalog."kanidm-admin".publicUrl;
  adminNamespaceStillAbsent = !(c.services ? admin);
}' "path:${D}#nixosConfigurations.la-admin-1.config")" || fail "client-only+Termix subset (LA without identity-provider/admin-hub) does not evaluate"
python3 - "$json" <<'PYEOF' || fail "client-only subset observables violated"
import json, sys
got = json.loads(sys.argv[1])
expected = {
    "kanidmNamespaceAbsent": True,
    "adminNamespaceAbsent": True,
    "providerUrl": "https://id.shrublab.xyz",
    "webPolicyUrl": "https://id.shrublab.xyz",
    "urlAligned": True,
    "adminNamespaceStillAbsent": True,
}
errs = [f"{k}: got {got.get(k)!r} want {v!r}" for k, v in expected.items() if got.get(k) != v]
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

# 4. Negative case: Termix selected without the OIDC contract must fail
# through the named OIDC contract throw, not a raw missing-option
# namespace (feature-topology/admin-module-structure). Termix is demoted on
# the real host, so the copy re-selects the aspect and its host-scoped OIDC
# secret source first: the guard is about the aspect's dependency contract,
# not about where the capability happens to be deployed today. With the
# contract intrinsic, the only importer selected in this composition is the
# host-auth capability, so deselecting it is what removes the contract.
python3 - "$D" <<'PYEOF' > /dev/null || fail "no-OIDC-contract mutation script failed"
import sys

d = sys.argv[1]

p = d + "/modules/hosts/la-admin-1/default.nix"
la = open(p).read()
assert la.count("        aspects.kanidm-host-auth\n") == 1, "kanidm-host-auth selection anchor drifted"
la = la.replace("        aspects.kanidm-host-auth\n", "", 1)
anchor = "        aspects.push-server\n"
assert la.count(anchor) == 1, "push-server selection anchor drifted"
la = la.replace(anchor, "        aspects.termix\n" + anchor, 1)
open(p, "w").write(la)

p = d + "/modules/hosts/la-admin-1/_nixos.nix"
host = open(p).read()
# Anchor on the host's identity block: the workload secret bindings
# were already stripped by the provider-only mutation above.
anchor = "    identity.hostAuth = {"
assert host.count(anchor) == 1, "identity.hostAuth anchor drifted"
termix_binding = "    admin.termix.secretFiles.oidc = ../../../secrets/hosts/la-admin-1/oidc.yaml;\n\n"
host = host.replace(anchor, termix_binding + anchor, 1)
open(p, "w").write(host)

# The copied host also carries the capability's own consumer assignment
# (`services.identity.hostAuth`). With the capability deselected that
# write references a namespace Nix no longer declares, so the raw
# "The option services.identity does not exist" error fires before Termix's
# named contract throw. Remove the exact host block (anchor + drift
# assertion) so the negative case exercises only the Termix guard.
p = d + "/modules/hosts/la-admin-1/_nixos.nix"
s = open(p).read()
hostauth = """    identity.hostAuth = {
      enable = true;
      sshIntegration = true;
      pamAllowedLoginGroups = [ "admins" ];
    };
"""
assert s.count(hostauth) == 1, "identity.hostAuth consumer block drifted"
s = s.replace(hostauth, "", 1)
open(p, "w").write(s)
PYEOF

# Force the Termix client contract read in the eval below (Nix is lazy:
# only forcing a contract-consuming option exercises the guarded lookup).
stderr="$(nix eval --no-write-lock-file --raw --apply 'c: builtins.toJSON {
  enable = c.services.admin.termix.enable;
  forcedClientId = c.services.admin.termix.oidc.clientId;
}' "path:${D}#nixosConfigurations.la-admin-1.config" 2>&1 >/dev/null || true)"
if ! printf '%s' "$stderr" | grep -q "required OIDC contract 'services.identity.oidc.clients.termix' is missing"; then
  fail "Termix without the OIDC contract must fail with the named contract message; stderr was: $stderr"
fi

# 4b. Negative cases: a selected capability whose canonical web-policy route
# is missing must fail through the named contract throw when the lazy route
# consumer is forced, not silently fall back (decouple-identity-admin-capabilities
# 4.2). Both negatives run on one fresh copy so the chained subset mutations
# above never see a mutated policy file.
D2="$(mktemp -d /tmp/identity-neg.XXXXXX)"
trap 'rm -rf "$D" "$D2"' EXIT
tar -C "$ROOT" \
  --exclude=.git --exclude=.jj --exclude=./opentofu --exclude=./opentofu/* \
  --exclude=.hp-forge-esp-backup --exclude=.qmd --exclude=.direnv \
  --exclude=.cortexkit --exclude=.tmp --exclude=.pi --exclude=.firecrawl \
  --exclude=.ruff_cache \
  -cf - . | tar -C "$D2" -xf -

# 4b-1. Termix without the `termix-admin` route must still evaluate: the
# serve target is a module-local declaration (`127.0.0.1:8083`), so dropping
# the route degrades the OIDC gate instead of breaking the service. This pins
# the direction — a service's runtime config never comes from the policy.
# Termix is demoted on the real host, so this copy re-selects it first.
python3 - "$D2" <<'PYEOF' > /dev/null || fail "termix re-selection for the route negative failed"
import sys

d = sys.argv[1]
p = d + "/modules/hosts/la-admin-1/default.nix"
la = open(p).read()
anchor = "        aspects.push-server\n"
assert la.count(anchor) == 1, "push-server selection anchor drifted"
open(p, "w").write(la.replace(anchor, "        aspects.termix\n" + anchor, 1))

p = d + "/modules/hosts/la-admin-1/_nixos.nix"
host = open(p).read()
anchor = "    identity.hostAuth = {"
assert host.count(anchor) == 1, "identity.hostAuth anchor drifted"
open(p, "w").write(host.replace(anchor, "    admin.termix.secretFiles.oidc = ../../../secrets/hosts/la-admin-1/oidc.yaml;\n\n" + anchor, 1))
PYEOF

python3 - "$D2/policy/web-services.nix" <<'PYEOF' > /dev/null || fail "termix route-removal mutation failed"
import sys

p = sys.argv[1]
s = open(p).read()
assert s.count("        termix-admin = {") == 1, "termix-admin route anchor drifted"
end_marker = "\n        };\n"
i = s.index("        termix-admin = {")
j = s.index(end_marker, i) + len(end_marker)
s = s[:i] + s[j:]
open(p, "w").write(s)
PYEOF

json="$(nix eval --no-write-lock-file --raw --apply 'c: builtins.toJSON {
  enable = c.services.admin.termix.enable;
  forcedExecStart = c.systemd.services.tailscale-serve-termix.serviceConfig.ExecStart;
  oidcEnabled = c.services.admin.termix.oidc.enabled;
}' "path:${D2}#nixosConfigurations.la-admin-1.config")" ||
  fail "Termix must still evaluate when the termix-admin route is absent (runtime config is module-local)"
printf '%s' "$json" | python3 -c '
import json, sys
got = json.load(sys.stdin)
if not got["enable"]:
    raise SystemExit("termix re-selection did not enable the service")
if "127.0.0.1:8083" not in got["forcedExecStart"]:
    raise SystemExit("serve target is not module-local: " + repr(got["forcedExecStart"]))
if got["oidcEnabled"] is not True:
    raise SystemExit("a missing route must degrade the OIDC gate to enabled, not break evaluation")
' || fail "Termix route-independence contract violated"

# 4b-2. Homepage without the `admin-homepage` route: `homepageRoute` is
# `or { }`-safe at the merge, so the named throw fires only when a route
# consumer (listenPort) is forced.
python3 - "$D2/policy/web-services.nix" <<'PYEOF' > /dev/null || fail "homepage route-removal mutation failed"
import sys

p = sys.argv[1]
s = open(p).read()
assert s.count("        admin-homepage = {") == 1, "admin-homepage route anchor drifted"
end_marker = "\n        };\n"
i = s.index("        admin-homepage = {")
j = s.index(end_marker, i) + len(end_marker)
s = s[:i] + s[j:]
open(p, "w").write(s)
PYEOF

stderr="$(nix eval --no-write-lock-file --raw --apply 'c: builtins.toJSON {
  enable = c.services.admin.homepage.enable;
  forcedListenPort = c.services.homepage-dashboard.listenPort;
}' "path:${D2}#nixosConfigurations.la-admin-1.config" 2>&1 >/dev/null || true)"
if ! printf '%s' "$stderr" | grep -q 'homepage: required canonical web-policy route .*admin-homepage.* is missing'; then
  fail "Homepage without the admin-homepage route must fail with the named web-policy contract message when listenPort is forced; stderr was: $stderr"
fi

# 5. Direction-of-dependency ratchets: reintroducing a sibling-namespace
# dependency fails these greps.
# Comment-only lines are excluded: the contract headers document the
# forbidden namespace by name, and a name mention is not a read.
if grep -RnE --include='*.nix' 'applications\.admin' modules/identity/identity-provider.nix modules/identity/kanidm-runtime.nix \
  | grep -vE '^[^:]+:[0-9]+: *#'; then
  fail "identity-provider/Kanidm leaf must not read the applications.admin namespace"
fi
if grep -RnE --include='*.nix' 'services\.admin\.kanidm' modules | grep -vE '^[^:]+:[0-9]+: *#'; then
  fail "services.admin.kanidm must remain absent repo-wide (modules/)"
fi
test ! -e modules/flake/admin-hub.nix ||
  fail "admin-hub must stay deleted (decouple-identity-admin-capabilities 3.3); absence ratchets must not pass vacuously"
if grep -RnE --include='*.nix' 'applications\.admin' modules | grep -vE '^[^:]+:[0-9]+: *#'; then
  fail "applications.admin must remain absent from modules/ (comment mentions only)"
fi
# Global directionality ratchets (decouple-identity-admin-capabilities 4.2):
# no convenience bundle, no transitive public-aspect import, no direct
# host-to-service implementation import, exact explicit LA aspect selections,
# and no Quantum residue.
test ! -e modules/flake/admin.nix \
  && test ! -e modules/flake/_admin-hub \
  && test ! -e modules/admin/admin-hub.nix ||
  fail "no admin convenience bundle may exist (D-054: no convenience bundle)"
if grep -RnE --include='*.nix' 'aspects\.(admin-hub|admin)([^a-z0-9-]|$)' modules/flake modules/hosts \
  | grep -vE '^[^:]+:[0-9]+: *#'; then
  fail "no aspect may select or import an admin-hub/admin bundle aspect"
fi
if grep -RnE --include='*.nix' 'services\.admin\.quantum|(^|[^a-z0-9_-])quantum\.nix' modules \
  | grep -vE '^[^:]+:[0-9]+: *#'; then
  fail "no Quantum option namespace or import may survive the 3.3 deletion"
fi
test ! -e modules/hosts/la-admin-1/quantum.nix ||
  fail "modules/hosts/la-admin-1/quantum.nix must stay deleted (3.3); absence ratchet must not pass vacuously"
# Full retirement (2026-09-21, TD-07): Quantum is gone from every surface, not
# only the workload - identity client, web route, OCI image, secret-source map,
# admin SSH registrations, and the data-root ACL exclusion with them.
if grep -RniE 'quantum' policy modules --include='*.nix' --include='*.json' 2>/dev/null \
  | grep -vE '^[^:]+:[0-9]+: *#'; then
  fail "Quantum was retired; no policy, module, or secret-source reference may remain"
fi
if grep -RnE 'admin_ssh_identity|admin\.ssh\.identity|admin_ssh_known_hosts' modules/hosts modules/admin modules/identity 2>/dev/null \
  | grep -vE '^[^:]+:[0-9]+: *#'; then
  fail "the admin SSH secret registrations existed only for Quantum and must not return"
fi
python3 - <<'PYEOF' || fail "LA host imports / registry selections directionality drifted"
import sys

# 1. The LA host imports only its two host-private fragments: no direct
# host-to-service implementation import may return (D-053/D-054 invariant).
host = open("modules/hosts/la-admin-1/_nixos.nix").read()
i = host.index("  imports = [")
j = host.index("\n  ];", i)
imports = host[i:j].splitlines()[1:]  # skip the opening 'imports = [' line
for line in imports:
    entry = line.strip()
    if not entry or entry.startswith("#"):
        continue
    if entry != "./_admin-runtime.nix":
        raise SystemExit(f"LA host imports must contain only the _admin-runtime fragment, found: {entry!r}")

# 2. LA must select exactly the deployed placement aspects, one selection
# line each, plus the support quartet and foundation/operational aspects; no
# admin-hub selection may return, and the demoted capabilities stay
# unselected until something re-selects them deliberately.
la = open("modules/hosts/la-admin-1/default.nix").read()
placement = [
    "ingress", "push-server", "identity-provider", "vaultwarden",
    "gatus", "beszel", "homepage", "webhook",
]
for a in placement:
    if la.count(f"        aspects.{a}\n") != 1:
        raise SystemExit(f"LA host record must select aspects.{a} exactly once")
for a in ["admin-hub", "cockpit", "termix"]:
    if f"        aspects.{a}\n" in la:
        raise SystemExit(f"LA host record must not select the demoted/deleted aspects.{a}")
for a in ["provenance", "oci-images", "fleet-packages", "web-policy", "kanidm-host-auth",
          "base", "shell", "networking", "tailscale", "notify",
          "state-backups", "cache-publisher",
          "builder-access", "observability-agent"]:
    if la.count(f"        aspects.{a}\n") != 1:
        raise SystemExit(f"LA host record must explicitly select aspects.{a} exactly once")
PYEOF
if ! grep -q 'oauth2Clients = {' modules/identity/identity-provider.nix \
  || ! grep -q 'webPolicyKanidmUrl' modules/identity/_oidc.nix; then
  fail "provider-owned explicit oauth2 secret-source map / web-policy URL default missing"
fi
if grep -nE 'services\.identity\.oidc(\.[A-Za-z0-9_]+)?[[:space:]]*(=[^=]|=$)' \
  modules/identity/identity-provider.nix modules/identity/kanidm-runtime.nix; then
  fail "identity-provider/Kanidm leaf must not write services.identity.oidc.* (the intrinsic contract owns it)"
fi
if grep -RnE --include='*.nix' 'applications\.admin' modules/admin/termix.nix modules/admin/termix-runtime.nix \
  | grep -vE '^[^:]+:[0-9]+: *#'; then
  fail "termix aspect/intrinsic leaf must not read the applications.admin namespace"
fi
if grep -RnHE --include='*.nix' 'applications\.admin' modules/apps/vaultwarden.nix \
  | grep -vE '^[^:]+:[0-9]+: *#'; then
  fail "vaultwarden aspect/intrinsic leaf must not read the applications.admin namespace"
fi
if grep -RnHE --include='*.nix' 'applications\.admin' modules/observability/gatus.nix \
  | grep -vE '^[^:]+:[0-9]+: *#'; then
  fail "gatus aspect/intrinsic leaf must not read the applications.admin namespace"
fi
if grep -RnHE --include='*.nix' 'applications\.admin' modules/observability/beszel.nix \
  | grep -vE '^[^:]+:[0-9]+: *#'; then
  fail "beszel aspect/intrinsic leaf must not read the applications.admin namespace"
fi
if grep -RnE --include='*.nix' 'applications\.admin' modules/admin/homepage.nix modules/admin/homepage/_data.nix \
  | grep -vE '^[^:]+:[0-9]+: *#'; then
  fail "homepage aspect/intrinsic leaf/data must not read the applications.admin namespace"
fi
if grep -RnHE --include='*.nix' 'applications\.admin' modules/admin/webhook.nix \
  | grep -vE '^[^:]+:[0-9]+: *#'; then
  fail "webhook aspect/intrinsic leaf must not read the applications.admin namespace"
fi
if grep -RnHE --include='*.nix' 'repo\.web' modules/admin/webhook.nix \
  | grep -vE '^[^:]+:[0-9]+: *#'; then
  fail "webhook aspect/intrinsic leaf must consume no web policy (external/manual route only)"
fi
if grep -RnE --include='*.nix' 'applications\.admin' modules/admin/cockpit.nix modules/admin/cockpit/loopback-tls.nix modules/admin/cockpit/tailscale-serve.nix \
  | grep -vE '^[^:]+:[0-9]+: *#'; then
  fail "cockpit aspect/intrinsic leaves must not read the applications.admin namespace"
fi
if grep -nE 'applications\.admin\.(dataRoot|secretFiles\.host)' modules/hosts/la-admin-1/_nixos.nix; then
  fail "LA host must not re-declare the migrated applications.admin host observables"
fi

# 6. Vaultwarden subset (task 3.1): the provider-only mutation already
# deselected the admin-hub aspect and stripped the host's
# applications.admin block and both Vaultwarden host bindings. Additionally
# select the standalone `vaultwarden` aspect and re-add its secret source and
# smtpFrom value so the
# Vaultwarden composition must evaluate from the canonical web-policy route
# and its own host secret source alone, with no applications.admin
# namespace present. Option-level evaluation only (same scope as section 3):
# no identity-provider here, so system.build.toplevel is deliberately not
# forced; full toplevel coverage runs against the real LA config in
# section 1.
python3 - "$D" <<'PYEOF' > /dev/null || fail "vaultwarden subset mutation script failed"
import sys

d = sys.argv[1]

p = d + "/modules/hosts/la-admin-1/default.nix"
s = open(p).read()
assert s.count("        aspects.termix\n") == 1, "termix selection anchor drifted"
s = s.replace(
    "        aspects.termix\n",
    "        aspects.termix\n        aspects.vaultwarden\n",
    1,
)
open(p, "w").write(s)

p = d + "/modules/hosts/la-admin-1/_nixos.nix"
s = open(p).read()
anchor = "    hostRecovery = {\n"
assert s.count(anchor) == 1, "vaultwarden host binding insertion anchor drifted"
s = s.replace(
    anchor,
    "    admin.vaultwarden.secretFiles.host = ../../../secrets/applications/admin.yaml;\n"
    + '    admin.vaultwarden.smtpFrom = "[EMAIL_REDACTED]";\n'
    + anchor,
    1,
)
open(p, "w").write(s)
PYEOF

json="$(nix eval --no-write-lock-file --raw --apply 'c: builtins.toJSON {
  vaultEnable = c.services.vaultwarden.enable;
  vaultDomain = c.services.vaultwarden.config.DOMAIN;
  vaultDataFolder = c.services.vaultwarden.config.DATA_FOLDER;
  vaultDataDir = c.services.admin.vaultwarden.dataDir;
  vaultRocketAddress = c.services.vaultwarden.config.ROCKET_ADDRESS;
  vaultRocketPort = c.services.vaultwarden.config.ROCKET_PORT;
  vaultTemplateRegistered = c.sops.templates ? "vaultwarden.env";
  vaultTemplatePathNonEmpty = c.sops.templates."vaultwarden.env".path != "";
  vaultTokenSecretRegistered = c.sops.secrets ? vaultwarden_admin_token;
  vaultBackupPaths = c.services.state-backups.services.vaultwarden.paths;
  vaultBackupMode = c.services.state-backups.services.vaultwarden.mode;
  # `applications` itself is absent when no application stack is selected:
  # absence of the whole namespace satisfies "no admin application".
  adminNamespaceAbsent = !((c.applications or { }) ? admin);
}' "path:${D}#nixosConfigurations.la-admin-1.config")" || fail "Vaultwarden subset (LA without admin-hub, with aspects.vaultwarden) does not evaluate"
python3 - "$json" <<'PYEOF' || fail "Vaultwarden subset observables violated"
import json, sys

got = json.loads(sys.argv[1])
expected = {
    "vaultEnable": True,
    "vaultDomain": "https://vault.shrublab.xyz",
    "vaultDataFolder": "/srv/data/vaultwarden",
    "vaultDataDir": "/srv/data/vaultwarden",
    "vaultRocketAddress": "0.0.0.0",
    "vaultRocketPort": 8222,
    "vaultTemplateRegistered": True,
    "vaultTemplatePathNonEmpty": True,
    "vaultTokenSecretRegistered": True,
    "vaultBackupPaths": ["/srv/data/vaultwarden"],
    "vaultBackupMode": "export",
    "adminNamespaceAbsent": True,
}
errs = [f"{k}: got {got.get(k)!r} want {v!r}" for k, v in expected.items() if got.get(k) != v]
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

# 7. Gatus subset (task 3.2): the provider-only mutation already deselected
# the admin-hub aspect (and with it the Gatus import/enable) and stripped the
# host's applications.admin bindings. Selecting the standalone `aspects.gatus`
# aspect must compose the Gatus service from the canonical web-policy route
# alone: exact origin host/port, the full catalog-derived endpoint sweep, the
# notification-daemon alert URL/body, and the NixOS service settings, all with
# no applications.admin namespace present. Option-level evaluation only (same
# scope as sections 3 and 6): no identity-provider here, so
# system.build.toplevel is deliberately not forced.
python3 - "$D" <<'PYEOF' > /dev/null || fail "gatus subset mutation script failed"
import sys

d = sys.argv[1]

p = d + "/modules/hosts/la-admin-1/default.nix"
s = open(p).read()
assert s.count("        aspects.vaultwarden\n") == 1, "vaultwarden selection anchor drifted"
s = s.replace(
    "        aspects.vaultwarden\n",
    "        aspects.vaultwarden\n        aspects.gatus\n",
    1,
)
open(p, "w").write(s)
PYEOF

json="$(nix eval --no-write-lock-file --raw --apply 'c:
let
  probedNames = builtins.sort builtins.lessThan (builtins.map (e: e.name) c.services.gatus.settings.endpoints);
  publishedNames = builtins.sort builtins.lessThan (
    builtins.filter (n: c.repo.web.catalog.${n}.publicUrl != null) (builtins.attrNames c.repo.web.catalog)
  );
in builtins.toJSON {
  gatusEnable = c.services.gatus.enable;
  webAddress = c.services.gatus.settings.web.address;
  webPort = c.services.gatus.settings.web.port;
  openFirewall = c.services.gatus.openFirewall;
  serviceListenAligned = c.services.gatus.settings.web.address == "0.0.0.0" && c.services.gatus.settings.web.port == c.repo.web.catalog."gatus-admin".upstreamPort;
  endpointSweepMatchesCatalog = c.services.gatus.settings.endpoints != [ ] && probedNames == publishedNames;
  endpointUrlsMatchPublicUrls = builtins.all (e: e.url == c.repo.web.catalog.${e.name}.publicUrl) c.services.gatus.settings.endpoints;
  endpointCount = builtins.length c.services.gatus.settings.endpoints;
  alertUrl = c.services.gatus.settings.alerting.custom.url;
  alertMethod = c.services.gatus.settings.alerting.custom.method;
  alertContentType = c.services.gatus.settings.alerting.custom.headers."Content-Type";
  alertTiers = c.services.gatus.settings.alerting.custom.placeholders.ALERT_TRIGGERED_OR_RESOLVED;
  alertBody = c.services.gatus.settings.alerting.custom.body;
  # `applications` itself is absent when no application stack is selected:
  # absence of the whole namespace satisfies "no admin application".
  adminNamespaceAbsent = !((c.applications or { }) ? admin);
}' "path:${D}#nixosConfigurations.la-admin-1.config")" || fail "Gatus subset (LA without admin-hub/applications.admin, with aspects.gatus) does not evaluate"
python3 - "$json" <<'PYEOF' || fail "Gatus subset observables violated"
import json, sys

got = json.loads(sys.argv[1])
expected = {
    "gatusEnable": True,
    "openFirewall": False,
    "serviceListenAligned": True,
    "endpointSweepMatchesCatalog": True,
    "endpointUrlsMatchPublicUrls": True,
    "alertUrl": "http://127.0.0.1:5555/notify",
    "alertMethod": "POST",
    "alertContentType": "application/json",
    "alertTiers": {"TRIGGERED": "warning", "RESOLVED": "info"},
    "adminNamespaceAbsent": True,
}
errs = [f"{k}: got {got.get(k)!r} want {v!r}" for k, v in expected.items() if got.get(k) != v]
if not got["webAddress"]:
    errs.append("webAddress: empty (origin host not consumed from web policy)")
if got["endpointCount"] < 1:
    errs.append(f"endpointCount: got {got['endpointCount']!r} want >= 1")
for placeholder in ("[ALERT_TRIGGERED_OR_RESOLVED]", "[ENDPOINT_NAME]", "[ALERT_DESCRIPTION]"):
    if placeholder not in got["alertBody"]:
        errs.append(f"alertBody: lost notification-daemon placeholder {placeholder}: {got['alertBody']!r}")
if '"topic":"web"' not in got["alertBody"]:
    errs.append(f"alertBody: lost notification-daemon topic: {got['alertBody']!r}")
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

# 8. Beszel subset (task 3.2): the provider-only mutation already deselected
# the admin-hub aspect (and with it the Beszel import/enable) and stripped the
# host's applications.admin bindings. Selecting the standalone `aspects.beszel`
# aspect must compose the Beszel hub from the canonical web-policy route alone:
# exact origin host/port, the route public URL as APP_URL, and the live-mode
# state-backups registration, all with no applications.admin namespace present.
# Option-level evaluation only (same scope as sections 3, 6, and 7):
# no identity-provider here, so system.build.toplevel is deliberately not
# forced.
python3 - "$D" <<'PYEOF' > /dev/null || fail "beszel subset mutation script failed"
import sys

d = sys.argv[1]

p = d + "/modules/hosts/la-admin-1/default.nix"
s = open(p).read()
assert s.count("        aspects.gatus\n") == 1, "gatus selection anchor drifted"
s = s.replace(
    "        aspects.gatus\n",
    "        aspects.gatus\n        aspects.beszel\n",
    1,
)
open(p, "w").write(s)
PYEOF

json="$(nix eval --no-write-lock-file --raw --apply 'c: builtins.toJSON {
  beszelEnable = c.services.admin.beszel.enable;
  hubEnable = c.services.beszel.hub.enable;
  hubAddress = c.services.beszel.hub.host;
  hubPort = c.services.beszel.hub.port;
  appUrl = c.services.beszel.hub.environment.APP_URL;
  webPolicyUrl = c.repo.web.catalog."beszel-admin".publicUrl;
  urlAligned = c.services.beszel.hub.environment.APP_URL == c.repo.web.catalog."beszel-admin".publicUrl;
  listenAligned = c.services.beszel.hub.host == "0.0.0.0" && c.services.beszel.hub.port == c.repo.web.catalog."beszel-admin".upstreamPort;
  passwordAuthEnabled = c.services.beszel.hub.environment.DISABLE_PASSWORD_AUTH == "false";
  userCreationEnabled = c.services.beszel.hub.environment.USER_CREATION == "true";
  backupMode = c.services.state-backups.services.beszel.mode;
  backupPaths = c.services.state-backups.services.beszel.paths;
  backupPathDerivesFromDataDir = c.services.state-backups.services.beszel.paths == [ "/var/lib/private/${baseNameOf c.services.beszel.hub.dataDir}" ];
  # `applications` itself is absent when no application stack is selected:
  # absence of the whole namespace satisfies "no admin application".
  adminNamespaceAbsent = !((c.applications or { }) ? admin);
}' "path:${D}#nixosConfigurations.la-admin-1.config")" || fail "Beszel subset (LA without admin-hub/applications.admin, with aspects.beszel) does not evaluate"
python3 - "$json" <<'PYEOF' || fail "Beszel subset observables violated"
import json, sys

got = json.loads(sys.argv[1])
expected = {
    "beszelEnable": True,
    "hubEnable": True,
    "hubAddress": "0.0.0.0",
    "hubPort": 8090,
    "appUrl": "https://beszel.shrublab.xyz",
    "webPolicyUrl": "https://beszel.shrublab.xyz",
    "urlAligned": True,
    "listenAligned": True,
    "passwordAuthEnabled": True,
    "userCreationEnabled": True,
    "backupMode": "live",
    "backupPathDerivesFromDataDir": True,
    "adminNamespaceAbsent": True,
}
errs = [f"{k}: got {got.get(k)!r} want {v!r}" for k, v in expected.items() if got.get(k) != v]
if not got["backupPaths"]:
    errs.append("backupPaths: empty (state-backups registration lost)")
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

# 9. Homepage subset (task 3.2): the provider-only mutation already deselected
# the admin-hub aspect (and with it the Homepage import/enable) and stripped
# the host's applications.admin bindings and the direct Homepage secret
# binding. Selecting the standalone `aspects.homepage` aspect and re-adding the
# host-scoped secret source must compose the dashboard from the canonical
# web-policy route and the catalog alone: policy origin host/port, allowed
# hosts, the `homepage-auth.env` template, the exact 8-secret map, and the
# catalog-derived settings/widgets/services/bookmarks, all with no
# applications.admin namespace present. Option-level evaluation only (same
# scope as sections 3, 6, and 7): no identity-provider here, so
# system.build.toplevel is deliberately not forced.
python3 - "$D" <<'PYEOF' > /dev/null || fail "homepage subset mutation script failed"
import sys

d = sys.argv[1]

p = d + "/modules/hosts/la-admin-1/default.nix"
s = open(p).read()
assert s.count("        aspects.beszel\n") == 1, "beszel selection anchor drifted"
s = s.replace(
    "        aspects.beszel\n",
    "        aspects.beszel\n        aspects.homepage\n",
    1,
)
open(p, "w").write(s)

p = d + "/modules/hosts/la-admin-1/_nixos.nix"
s = open(p).read()
anchor = "    hostRecovery = {\n"
assert s.count(anchor) == 1, "homepage host binding insertion anchor drifted"
s = s.replace(
    anchor,
    "    admin.homepage.secretFiles.host = ../../../secrets/applications/admin.yaml;\n"
    + anchor,
    1,
)
open(p, "w").write(s)
PYEOF

json="$(nix eval --no-write-lock-file --raw --apply 'c:
let
  route = c.repo.web.catalog."admin-homepage";
  names = builtins.sort builtins.lessThan (builtins.filter (n: builtins.match "homepage_.*" n != null) (builtins.attrNames c.sops.secrets));
  allEntries = builtins.concatLists (builtins.map (g: builtins.concatLists (builtins.attrValues g)) c.services.homepage-dashboard.services);
  entry = name: (builtins.head (builtins.filter (e: e ? ${name}) allEntries)).${name};
  linkGroup = (builtins.head c.services.homepage-dashboard.bookmarks)."0Links";
  adminBookmark = builtins.head ((builtins.head linkGroup)."Admin Dashboard");
in
builtins.toJSON {
  homepageEnable = c.services.admin.homepage.enable;
  dashboardEnable = c.services.homepage-dashboard.enable;
  openFirewall = c.services.homepage-dashboard.openFirewall;
  listenPort = c.services.homepage-dashboard.listenPort;
  portAligned = c.services.homepage-dashboard.listenPort == route.upstreamPort;
  allowedHostsAligned = c.services.homepage-dashboard.allowedHosts == "localhost:${toString route.upstreamPort},127.0.0.1:${toString route.upstreamPort},${route.publicHost}";
  templateRegistered = c.sops.templates ? "homepage-auth.env";
  templatePathNonEmpty = c.sops.templates."homepage-auth.env".path != "";
  templateOwner = c.sops.templates."homepage-auth.env".owner;
  templateMode = c.sops.templates."homepage-auth.env".mode;
  environmentFilesAligned = c.services.homepage-dashboard.environmentFiles == [ c.sops.templates."homepage-auth.env".path ];
  secretNames = names;
  secretSpecs = builtins.map (n: {
    key = c.sops.secrets.${n}.key;
    path = c.sops.secrets.${n}.path;
    owner = c.sops.secrets.${n}.owner;
    group = c.sops.secrets.${n}.group;
    mode = c.sops.secrets.${n}.mode;
  }) names;
  sopsFilesAligned = builtins.all (n: builtins.match ".*secrets/applications/admin.yaml" (builtins.toString c.sops.secrets.${n}.sopsFile) != null) names;
  settingsTitle = c.services.homepage-dashboard.settings.title;
  startUrlAligned = c.services.homepage-dashboard.settings.startUrl == "${route.publicUrl}#overview";
  entryCount = builtins.length allEntries;
  navidromeHrefAligned = (entry "Navidrome").href == c.repo.web.catalog."navidrome".publicUrl;
  gatusHrefAligned = (entry "Gatus").href == c.repo.web.catalog."gatus-admin".publicUrl;
  cockpitOciHrefAligned = (entry "Cockpit (OCI)").href == c.repo.web.catalog."cockpit-oci-melb-1".publicUrl;
  # The demoted cockpit has no dashboard entry (its policy route is retired).
  # The widget dials the origin the module declares, not the policy: the
  # pattern pins that construction (short host + tailnet suffix + port)
  # without hardcoding the suffix, and asserts it is not the public URL.
  navidromeWidgetUrlAligned =
    let
      url = (entry "Navidrome").widget.url;
    in
    builtins.match "http://home-forge\\..*:4533" url != null
    && url != c.repo.web.catalog."navidrome".publicUrl;
  caddyWidgetUrl = (entry "Caddy").widget.url;
  tailscaleDeviceVar = (entry "Tailscale").widget.deviceid;
  slskdKeyVar = (entry "Slskd").widget.key;
  bookmarkCount = builtins.length linkGroup;
  bookmarkAdminHrefAligned = adminBookmark.href == route.publicUrl;
  widgetsCpu = (builtins.head c.services.homepage-dashboard.widgets).resources.cpu;
  # `applications` itself is absent when no application stack is selected:
  # absence of the whole namespace satisfies "no admin application".
  adminNamespaceAbsent = !((c.applications or { }) ? admin);
}' "path:${D}#nixosConfigurations.la-admin-1.config")" || fail "Homepage subset (LA without admin-hub/applications.admin, with aspects.homepage) does not evaluate"
python3 - "$json" <<'PYEOF' || fail "Homepage subset observables violated"
import json, sys

got = json.loads(sys.argv[1])
expected = {
    "homepageEnable": True,
    "dashboardEnable": True,
    "openFirewall": False,
    "portAligned": True,
    "allowedHostsAligned": True,
    "templateRegistered": True,
    "templatePathNonEmpty": True,
    "templateOwner": "root",
    "templateMode": "0400",
    "environmentFilesAligned": True,
    "secretNames": [
        "homepage_beszel_password",
        "homepage_beszel_username",
        "homepage_navidrome_salt",
        "homepage_navidrome_token",
        "homepage_navidrome_user",
        "homepage_slskd_key",
        "homepage_tailscale_api_key",
        "homepage_tailscale_device_id",
    ],
    "secretSpecs": [
        {"key": "homepage/beszel/password", "path": "/run/secrets/homepage.beszel.password", "owner": "root", "group": "root", "mode": "0400"},
        {"key": "homepage/beszel/username", "path": "/run/secrets/homepage.beszel.username", "owner": "root", "group": "root", "mode": "0400"},
        {"key": "homepage/navidrome/salt", "path": "/run/secrets/homepage.navidrome.salt", "owner": "root", "group": "root", "mode": "0400"},
        {"key": "homepage/navidrome/token", "path": "/run/secrets/homepage.navidrome.token", "owner": "root", "group": "root", "mode": "0400"},
        {"key": "homepage/navidrome/user", "path": "/run/secrets/homepage.navidrome.user", "owner": "root", "group": "root", "mode": "0400"},
        {"key": "homepage/slskd/key", "path": "/run/secrets/homepage.slskd.key", "owner": "root", "group": "root", "mode": "0400"},
        {"key": "homepage/tailscale/api_key", "path": "/run/secrets/homepage.tailscale.api_key", "owner": "root", "group": "root", "mode": "0400"},
        {"key": "homepage/tailscale/device_id", "path": "/run/secrets/homepage.tailscale.device_id", "owner": "root", "group": "root", "mode": "0400"},
    ],
    "sopsFilesAligned": True,
    "settingsTitle": "Shrublab Admin",
    "startUrlAligned": True,
    # 12 entries: the Quantum bookmark and the demoted Cockpit entry were
    # removed with the retired workloads.
    "entryCount": 12,
    "navidromeHrefAligned": True,
    "gatusHrefAligned": True,
    "cockpitOciHrefAligned": True,
    "navidromeWidgetUrlAligned": True,
    "caddyWidgetUrl": "http://127.0.0.1:2019",
    "tailscaleDeviceVar": "{{HOMEPAGE_VAR_TAILSCALE_DEVICEID}}",
    "slskdKeyVar": "{{HOMEPAGE_VAR_SLSKD_KEY}}",
    "bookmarkCount": 4,
    "bookmarkAdminHrefAligned": True,
    "widgetsCpu": True,
    "adminNamespaceAbsent": True,
}
errs = [f"{k}: got {got.get(k)!r} want {v!r}" for k, v in expected.items() if got.get(k) != v]
if not got["listenPort"]:
    errs.append("listenPort: not forced")
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

# 10. Webhook subset (task 3.2): the provider-only mutation already deselected
# the admin-hub aspect (and, before 3.2, its Webhook import/enable), stripped
# the standalone `aspects.webhook` selection, and removed the host's
# applications.admin bindings. Selecting the standalone `aspects.webhook`
# aspect must compose the upstream `services.webhook` service from the leaf
# alone: loopback bind address, closed firewall, and the exact single health
# hook, all with no applications.admin namespace present and no web-policy
# read in the aspect/leaf. The retained `webhook-admin` policy route stays
# untouched for external/manual callers; nothing in-repo consumes the service.
# Option-level evaluation only (same scope as sections 3 and 6-9): no
# identity-provider here, so system.build.toplevel is deliberately not forced.
python3 - "$D" <<'PYEOF' > /dev/null || fail "webhook subset mutation script failed"
import sys

d = sys.argv[1]

p = d + "/modules/hosts/la-admin-1/default.nix"
s = open(p).read()
assert s.count("        aspects.homepage\n") == 1, "homepage selection anchor drifted"
s = s.replace(
    "        aspects.homepage\n",
    "        aspects.homepage\n        aspects.webhook\n",
    1,
)
open(p, "w").write(s)
PYEOF

json="$(nix eval --no-write-lock-file --raw --apply 'c: builtins.toJSON {
  webhookLeafEnable = c.services.admin.webhook.enable;
  webhookServiceEnable = c.services.webhook.enable;
  webhookIp = c.services.webhook.ip;
  webhookOpenFirewall = c.services.webhook.openFirewall;
  hookNames = builtins.attrNames c.services.webhook.hooks;
  hookExec = c.services.webhook.hooks.health."execute-command";
  hookResponse = c.services.webhook.hooks.health."response-message";
  webhookAdminRoutePresent = c.repo.web.catalog ? "webhook-admin";
  # `applications` itself is absent when no application stack is selected:
  # absence of the whole namespace satisfies "no admin application".
  adminNamespaceAbsent = !((c.applications or { }) ? admin);
}' "path:${D}#nixosConfigurations.la-admin-1.config")" || fail "Webhook subset (LA without admin-hub/applications.admin, with aspects.webhook) does not evaluate"
python3 - "$json" <<'PYEOF' || fail "Webhook subset observables violated"
import json, re, sys

got = json.loads(sys.argv[1])
expected = {
    "webhookLeafEnable": True,
    "webhookServiceEnable": True,
    "webhookIp": "127.0.0.1",
    "webhookOpenFirewall": False,
    "hookNames": ["health"],
    "hookResponse": "ok",
    "webhookAdminRoutePresent": True,
    "adminNamespaceAbsent": True,
}
errs = [f"{k}: got {got.get(k)!r} want {v!r}" for k, v in expected.items() if got.get(k) != v]
if re.fullmatch(r"/nix/store/[0-9a-z]{32}-coreutils-[^/]+/bin/true", got["hookExec"]) is None:
    errs.append(f"hookExec: got {got['hookExec']!r} want the exact coreutils /bin/true command")
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

# 11. Cockpit subset: Cockpit is demoted on the real host, so this copy
# re-selects the aspect and restores the LA-only loopback TLS variant inline.
# The cockpit-admin policy route is gone (retired with the demoted cockpit),
# so the published identity comes from the explicit host overrides while the
# loopback socket bind and the loopback TLS material/ordering still hold
# through the leaf's own named assertions.
python3 - "$D" <<'PYEOF' > /dev/null || fail "cockpit subset mutation script failed"
import sys

d = sys.argv[1]

p = d + "/modules/hosts/la-admin-1/default.nix"
la = open(p).read()
anchor = "        aspects.push-server\n"
assert la.count(anchor) == 1, "push-server selection anchor drifted"
open(p, "w").write(la.replace(anchor, "        aspects.cockpit\n" + anchor, 1))

p = d + "/modules/hosts/la-admin-1/_nixos.nix"
s = open(p).read()
anchor = "  services = {\n"
assert s.count(anchor) == 1, "host services block anchor drifted"
variant = "    admin.cockpit.loopbackTls.enable = true;\n"
assert variant not in s, "cockpit loopback variant anchor drifted"
# The canonical cockpit-admin route is retired: a re-enabled host must supply
# its published identity through the module's explicit overrides.
variant += '    admin.cockpit.publicHost = "cockpit.shrublab.xyz";\n'
variant += '    admin.cockpit.urlRoot = "/la-admin-1";\n'
open(p, "w").write(s.replace(anchor, anchor + variant, 1))
PYEOF

[[ "$(grep -c 'message = "Cockpit loopback TLS material requires' modules/admin/cockpit/loopback-tls.nix)" -eq 3 ]] || fail "Cockpit loopback TLS assertion contract drifted"

json="$(nix eval --no-write-lock-file --raw --apply 'c:
let
  # The canonical route is retired; the demoted host supplies its published
  # identity through services.admin.cockpit.{publicHost,urlRoot} overrides.
  route = {
    publicHost = "cockpit.shrublab.xyz";
    path = "/la-admin-1";
    upstreamScheme = "https";
  };
in
builtins.toJSON {
  leafEnable = c.services.admin.cockpit.enable;
  cockpitEnable = c.services.cockpit.enable;
  openFirewall = c.services.cockpit.openFirewall;
  listenStreams = c.systemd.sockets.cockpit.listenStreams;
  origins = c.services.cockpit.settings.WebService.Origins;
  originsAligned = c.services.cockpit.settings.WebService.Origins == "https://${route.publicHost} wss://${route.publicHost}";
  urlRoot = c.services.cockpit.settings.WebService.UrlRoot;
  urlRootAligned = c.services.cockpit.settings.WebService.UrlRoot == route.path;
  protocolHeader = c.services.cockpit.settings.WebService.ProtocolHeader;
  forwardedForHeader = c.services.cockpit.settings.WebService.ForwardedForHeader;
  loginTo = c.services.cockpit.settings.WebService.LoginTo;
  loopbackTlsEnable = c.services.admin.cockpit.loopbackTls.enable;
  loopbackBackupEnable = c.services.state-backups.services.cockpit-loopback-tls.enable;
  loopbackBackupMode = c.services.state-backups.services.cockpit-loopback-tls.mode;
  loopbackBackupPaths = c.services.state-backups.services.cockpit-loopback-tls.paths;
  loopbackMaterialUnit = c.systemd.services ? cockpit-loopback-tls-material;
  loopbackOrdering = builtins.elem "cockpit-loopback-tls-material.service" c.systemd.services.cockpit.requires && builtins.elem "cockpit-loopback-tls-material.service" c.systemd.services.cockpit.after;
  routeScheme = route.upstreamScheme;
  # `applications` itself is absent when no application stack is selected:
  # absence of the whole namespace satisfies "no admin application".
  adminNamespaceAbsent = !((c.applications or { }) ? admin);
}' "path:${D}#nixosConfigurations.la-admin-1.config")" || fail "Cockpit subset (LA without admin-hub/applications.admin, with aspects.cockpit) does not evaluate"
python3 - "$json" <<'PYEOF' || fail "Cockpit subset observables violated"
import json, sys

got = json.loads(sys.argv[1])
expected = {
    "leafEnable": True,
    "cockpitEnable": True,
    "openFirewall": False,
    "listenStreams": ["", "127.0.0.1:9090"],
    "origins": "https://cockpit.shrublab.xyz wss://cockpit.shrublab.xyz",
    "originsAligned": True,
    "urlRoot": "/la-admin-1",
    "urlRootAligned": True,
    "protocolHeader": "X-Forwarded-Proto",
    "forwardedForHeader": "X-Forwarded-For",
    "loginTo": False,
    "loopbackTlsEnable": True,
    "loopbackBackupEnable": True,
    "loopbackBackupMode": "live",
    "loopbackBackupPaths": ["/var/lib/cockpit-loopback-tls"],
    "loopbackMaterialUnit": True,
    "loopbackOrdering": True,
    "routeScheme": "https",
    "adminNamespaceAbsent": True,
}
errs = [f"{k}: got {got.get(k)!r} want {v!r}" for k, v in expected.items() if got.get(k) != v]
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

# 12. Host-local admin remainder (task 3.3): the `/srv/data` operator
# ACL/reconcile unit and the admin SSH identity SOPS registrations are
# la-admin-1 host-local configuration, owned by the host-private
# `_admin-runtime.nix` fragment imported from the host default. The fragment
# is not a placement aspect, and admin-hub must not regain any of these
# mechanisms (section 5 ratchets the absence side).
python3 - <<'PYEOF' || fail "host-local admin runtime fragment drifted"
FRAG = "modules/hosts/la-admin-1/_admin-runtime.nix"
HOST = "modules/hosts/la-admin-1/_nixos.nix"
frag = open(FRAG).read()
required_frag = [
    '"d /srv/data 0755 root root - -"',
    '"z /srv/data 0755 root root - -"',
    '"a+ /srv/data - - - - user:dev:r-X"',
    '"a+ /srv/data - - - - default:user:dev:r-X"',
    'description = "Reconcile dev read/traverse access on admin data root";',
    'wantedBy = [ "multi-user.target" ];',
    'after = [ "systemd-tmpfiles-setup.service" ];',
    'ExecStart = pkgs.writeShellScript "admin-dev-data-access-reconcile"',
    'Type = "oneshot";',
    "set -euo pipefail",
    'if [ -d "/srv/data" ]; then',
    '${pkgs.acl}/bin/setfacl -m u:dev:rX "/srv/data"',
    'find "/srv/data" -xdev -type d -exec ${pkgs.acl}/bin/setfacl -m d:u:dev:rX {} +',
]
missing = [line for line in required_frag if line not in frag]
if missing:
    raise SystemExit(f"{FRAG}: missing exact lines: {missing!r}")
if "sops.secrets" in frag or "admin/ssh/" in frag:
    raise SystemExit(f"{FRAG}: the admin SSH registrations existed only for the retired Quantum workload and must not return")
host = open(HOST).read()
if host.count("    ./_admin-runtime.nix\n") != 1:
    raise SystemExit(f"{HOST}: must import ./_admin-runtime.nix exactly once")
if "applications.admin" in host:
    raise SystemExit(f"{HOST}: applications.admin must be fully absent after the 3.3 admin-hub deletion")
PYEOF

json="$(ne 'c:
let
  unit = c.systemd.services.admin-dev-data-access-reconcile;
in
builtins.toJSON {
  sshSecretsAbsent = !(c.sops.secrets ? admin_ssh_identity) && !(c.sops.secrets ? admin_ssh_known_hosts);
  unitPresent = c.systemd.services ? admin-dev-data-access-reconcile;
  unitDescription = unit.description;
  unitWantedBy = builtins.elem "multi-user.target" unit.wantedBy;
  unitAfter = builtins.elem "systemd-tmpfiles-setup.service" unit.after;
  unitType = unit.serviceConfig.Type;
  unitExecName = builtins.baseNameOf (builtins.toString unit.serviceConfig.ExecStart);
  tmpfilesExact = builtins.all (r: builtins.elem r c.systemd.tmpfiles.rules) [
    "d /srv/data 0755 root root - -"
    "z /srv/data 0755 root root - -"
    "a+ /srv/data - - - - user:dev:r-X"
    "a+ /srv/data - - - - default:user:dev:r-X"
  ];
  # `applications` itself is absent when no application stack is selected:
  # absence of the whole namespace satisfies "no admin application".
  adminNamespaceAbsent = !((c.applications or { }) ? admin);
}')"
python3 - "$json" <<'PYEOF' || fail "LA host-local admin runtime observables violated"
import json, sys

got = json.loads(sys.argv[1])
expected = {
    "sshSecretsAbsent": True,
    "unitPresent": True,
    "unitDescription": "Reconcile dev read/traverse access on admin data root",
    "unitWantedBy": True,
    "unitAfter": True,
    "unitType": "oneshot",
    "tmpfilesExact": True,
    "adminNamespaceAbsent": True,
}
errs = [f"{k}: got {got.get(k)!r} want {v!r}" for k, v in expected.items() if got.get(k) != v]
if not got["unitExecName"].endswith("-admin-dev-data-access-reconcile"):
    errs.append(f"unitExecName: got {got['unitExecName']!r} want suffix '-admin-dev-data-access-reconcile'")
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

# 13. oci-melb-1 / home-forge host-record pinning (Stage 8 HIC-1/HIC-2): the LA
# pin in §5.2 covers la-admin-1 exactly-once across all selections; oci and
# forge need the same duplicate-selection protection that the scaffold's 7b
# exact-set assertions cannot give (they apply sort -u). Placement sets mirror
# the 7b expectations: oci nine, forge three.
python3 - <<'PYEOF' || fail "host-record selection pins drifted"
pins = {
    "modules/hosts/oci-melb-1/default.nix": [
        "oci", "ingress", "cockpit", "paperless", "postgres",
        "bifrost", "karakeep", "niks3-cache", "langfuse",
    ],
    "modules/hosts/home-forge/default.nix": [
        "dj", "music", "omniroute",
    ],
}
shared = [
    "provenance", "oci-images", "fleet-packages", "web-policy",
    "base", "shell", "networking", "tailscale", "notify",
    "state-backups", "cache-publisher",
    "builder-access", "observability-agent",
]
for path, placement in pins.items():
    body = open(path).read()
    for a in placement + shared + (["kanidm-host-auth"] if "oci-melb-1" in path else []):
        if body.count(f"        aspects.{a}\n") != 1:
            raise SystemExit(f"{path}: must select aspects.{a} exactly once")
PYEOF

# 14. Provider-only composition (make-oidc-contract-intrinsic): the provider
# leaf consumes the intrinsic OIDC contract itself, so the provider host must
# evaluate with the host-auth capability absent and must not need any client
# capability selected to read the derived provider URL. The host's own
# `identity.hostAuth` assignment goes with the deselected capability, because
# the capability declares that namespace (select-then-configure coupling).
D3="$(mktemp -d /tmp/identity-prov.XXXXXX)"
trap 'rm -rf "$D" "$D2" "$D3"' EXIT
tar -C "$ROOT" \
  --exclude=.git --exclude=.jj --exclude=./opentofu --exclude=./opentofu/* \
  --exclude=.hp-forge-esp-backup --exclude=.qmd --exclude=.direnv \
  --exclude=.cortexkit --exclude=.tmp --exclude=.pi --exclude=.firecrawl \
  --exclude=.ruff_cache \
  -cf - . | tar -C "$D3" -xf -
python3 - "$D3" <<'PYEOF' > /dev/null || fail "provider-only mutation script failed"
import sys

d = sys.argv[1]

p = d + "/modules/hosts/la-admin-1/default.nix"
s = open(p).read()
assert s.count("        aspects.kanidm-host-auth\n") == 1, "kanidm-host-auth selection anchor drifted"
open(p, "w").write(s.replace("        aspects.kanidm-host-auth\n", "", 1))

p = d + "/modules/hosts/la-admin-1/_nixos.nix"
s = open(p).read()
block = """    identity.hostAuth = {
      enable = true;
      sshIntegration = true;
      pamAllowedLoginGroups = [ "admins" ];
    };
"""
assert s.count(block) == 1, "identity.hostAuth consumer block drifted"
open(p, "w").write(s.replace(block, "", 1))
PYEOF
json="$(nix eval --no-write-lock-file --raw --apply 'c: builtins.toJSON {
  providerUrl = c.services.identity.oidc.providerUrl;
  identityNamespaces = builtins.attrNames c.services.identity;
  hostAuthAbsent = !(c.services.identity ? hostAuth);
  kanidmServerEnable = c.services.identity.kanidm.enable;
  kanidmUnixEnable = c.services.kanidm.unix.enable or false;
  kanidmProvisionEnable = c.services.kanidm.provision.enable or false;
  provisionClientKeys = builtins.attrNames (c.services.kanidm.provision.systems.oauth2 or {});
  oauth2SecretSourceKeys = builtins.attrNames c.services.identity.kanidm.secretFiles.oauth2Clients;
}' "path:${D3}#nixosConfigurations.la-admin-1.config")" ||
  fail "provider-only composition (LA without the host-auth capability) does not evaluate"
python3 - "$json" <<'PYEOF' || fail "provider-only composition observables violated"
import json, sys
got = json.loads(sys.argv[1])
expected = {
    "providerUrl": "https://id.shrublab.xyz",
    "identityNamespaces": ["kanidm", "oidc"],
    "hostAuthAbsent": True,
    "kanidmServerEnable": True,
    "kanidmUnixEnable": False,
    "kanidmProvisionEnable": True,
}
errs = [f"{k}: got {got.get(k)!r} want {v!r}" for k, v in expected.items() if got.get(k) != v]
if got.get("provisionClientKeys") != ["beszel", "cloudflare-access", "karakeep", "paperless", "termix"]:
    errs.append(f"provisionClientKeys: got {got.get('provisionClientKeys')!r}")
if got.get("oauth2SecretSourceKeys") != ["beszel", "cloudflare-access", "karakeep", "paperless", "termix"]:
    errs.append(f"oauth2SecretSourceKeys: got {got.get('oauth2SecretSourceKeys')!r}")
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

# 15. Projection-only probe (make-oidc-contract-intrinsic): the contract is a
# standalone module, so importing it alone — with no identity aspect selected
# anywhere — must still resolve every enabled client's canonical endpoints, and
# it must not drag the host-auth capability or the Kanidm runtime with it.
oidc_fragment_probe() { # $1 copy root -> eval report JSON
  local d="$1" t out
  t="$(mktemp -d /tmp/identity-fragment.XXXXXX)"
  cat >"$t/flake.nix" <<EOF2
{
  inputs.repo.url = "path:$d";
  outputs = { self, repo }: {
    report = let
      sys = repo.inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          (import "$d/modules/identity/_oidc.nix")
          {
            services.identity.oidc.providerUrl = "https://probe-id.example";
            networking.hostName = "probe-host";
            system.stateVersion = "25.11";
          }
        ];
      };
      c = sys.config;
      beszel = c.services.identity.oidc.clients.beszel or { };
    in {
      providerUrl = c.services.identity.oidc.providerUrl;
      clientPathPrefix = c.services.identity.oidc.clientPathPrefix;
      tokenUrl = c.services.identity.oidc.tokenUrl;
      clientKeys = builtins.attrNames c.services.identity.oidc.clients;
      paperlessWellknown = c.services.identity.oidc.clients.paperless.wellknownUrl or "";
      beszel = {
        clientId = beszel.clientId or "";
        issuerUrl = beszel.issuerUrl or "";
        wellknownUrl = beszel.wellknownUrl or "";
        authorizationUrl = beszel.authorizationUrl or "";
        tokenUrl = beszel.tokenUrl or "";
        userinfoUrl = beszel.userinfoUrl or "";
      };
      hostAuthAbsent = !(c.services.identity ? hostAuth);
      providerNamespaceAbsent = !(c.services.identity ? kanidm);
      # The contract deploys nothing: the nixpkgs Kanidm options exist because
      # every nixosSystem carries the nixpkgs module list, so the meaningful
      # absence is that no Kanidm runtime surface is ENABLED by importing it.
      kanidmServerEnable = c.services.kanidm.server.enable or false;
      kanidmClientEnable = c.services.kanidm.client.enable or false;
      kanidmUnixEnable = c.services.kanidm.unix.enable or false;
      kanidmProvisionEnable = c.services.kanidm.provision.enable or false;
    };
  };
}
EOF2
  out="$(nix eval --raw --impure --no-write-lock-file --expr "builtins.toJSON ((builtins.getFlake (toString $t)).report)")"
  rm -rf "$t"
  printf '%s' "$out"
}
D4="$(mktemp -d /tmp/identity-projection.XXXXXX)"
trap 'rm -rf "$D" "$D2" "$D3" "$D4"' EXIT
tar -C "$ROOT" \
  --exclude=.git --exclude=.jj --exclude=./opentofu --exclude=./opentofu/* \
  --exclude=.hp-forge-esp-backup --exclude=.qmd --exclude=.direnv \
  --exclude=.cortexkit --exclude=.tmp --exclude=.pi --exclude=.firecrawl \
  --exclude=.ruff_cache \
  -cf - . | tar -C "$D4" -xf -
frag_json="$(oidc_fragment_probe "$D4")" || fail "projection-only fragment probe did not evaluate"
python3 - "$frag_json" <<'PYEOF' || fail "projection-only fragment observables violated"
import json, sys
got = json.loads(sys.argv[1])
expected = {
    "providerUrl": "https://probe-id.example",
    "clientPathPrefix": "https://probe-id.example/oauth2/openid",
    "tokenUrl": "https://probe-id.example/oauth2/token",
    "paperlessWellknown": "https://probe-id.example/oauth2/openid/paperless/.well-known/openid-configuration",
    "hostAuthAbsent": True,
    "providerNamespaceAbsent": True,
    "kanidmServerEnable": False,
    "kanidmClientEnable": False,
    "kanidmUnixEnable": False,
    "kanidmProvisionEnable": False,
}
errs = [f"{k}: got {got.get(k)!r} want {v!r}" for k, v in expected.items() if got.get(k) != v]
if got.get("clientKeys") != ["beszel", "cloudflare-access", "karakeep", "paperless", "termix"]:
    errs.append(f"clientKeys: got {got.get('clientKeys')!r}")
beszel = got.get("beszel") or {}
for field, want in {
    "clientId": "beszel",
    "issuerUrl": "https://probe-id.example/oauth2/openid/beszel",
    "wellknownUrl": "https://probe-id.example/oauth2/openid/beszel/.well-known/openid-configuration",
    "authorizationUrl": "https://probe-id.example/ui/oauth2",
    "tokenUrl": "https://probe-id.example/oauth2/token",
    "userinfoUrl": "https://probe-id.example/oauth2/openid/beszel/userinfo",
}.items():
    if beszel.get(field) != want:
        errs.append(f"beszel.{field}: got {beszel.get(field)!r} want {want!r}")
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

# 16. Terminology ratchet (make-oidc-contract-intrinsic): the retired aspect
# name must not survive in the implementation or in either suite. This file is
# excluded so the pattern cannot match its own source; archived changes and
# historical documents are out of scope, because they record what was true when
# they were written.
retired_hits="$(grep -rn --include='*.nix' --include='*.sh' 'identity-client' modules/ tests/ \
  | grep -v '^tests/check-identity-contract-directionality.sh:' || true)"
[ -z "$retired_hits" ] ||
  fail "the retired identity aspect name must not appear in modules/ or tests/: $retired_hits"
grep -rq 'kanidm-host-auth' modules/ ||
  fail "the replacement capability name must be present, so the terminology ratchet cannot pass vacuously"

echo "check-identity-contract-directionality: PASS"
