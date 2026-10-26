#!/usr/bin/env bash
set -euo pipefail

# Behavioural checks for the directional identity contracts: the OIDC client
# contract is intrinsic and provider-neutral, the provider reads policy rather
# than consumer configuration, and host authentication resolves independently
# of the active application provider. Targeted evaluations only: never reads or
# decrypts secret ciphertext, never touches .sops.yaml, never builds.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "check-identity-contract-directionality: $*" >&2
  exit 1
}

# Mutation fixtures are copied trees without a Git repository, so `path:` is the
# only form that resolves there.
make_copy() {
  local dest="$1"
  tar -C "$ROOT" \
    --exclude=.git --exclude=.jj --exclude=./opentofu --exclude=./opentofu/* \
    --exclude=.hp-forge-esp-backup --exclude=.qmd --exclude=.direnv \
    --exclude=.cortexkit --exclude=.tmp --exclude=.pi --exclude=.firecrawl \
    --exclude=.ruff_cache \
    -cf - . | tar -C "$dest" -xf -
}

report() { # $1 flake ref, $2 apply expression
  nix eval --no-write-lock-file --raw --apply "$2" "$1"
}

WORK="$(mktemp -d /tmp/identity-contract.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# 1b. Applications whose provider identifier appears in their callback path take that
# identifier from the client id, so a policy rename cannot leave the path behind.
python3 - "$ROOT/policy/identity.nix" <<'PYEOF' || fail "a callback path does not carry its client id"
import re, sys

policy = open(sys.argv[1]).read()
errors = []
for name in ("paperless", "tududi"):
    block = policy.split(f"    {name} = {{", 1)
    if len(block) != 2:
        errors.append(f"client {name} not found in policy")
        continue
    body = block[1].split("    };", 1)[0]
    path = re.search(r'callbackPath = "([^"]*)"', body)
    if not path:
        errors.append(f"{name}: no callbackPath")
    elif f"/{name}/" not in path.group(1) and not path.group(1).endswith(f"/{name}"):
        errors.append(f"{name}: callback path {path.group(1)!r} does not carry the client id")
if errors:
    print("; ".join(errors), file=sys.stderr)
    sys.exit(1)
PYEOF

# 2. The client contract alone resolves endpoints and starts nothing. Explicit
# override of the provider URL keeps this probe independent of policy.
probe_dir="$WORK/fragment"
mkdir -p "$probe_dir"
cat >"$probe_dir/flake.nix" <<EOF2
{
  inputs.repo.url = "path:$ROOT";
  outputs = { self, repo }: {
    report = let
      sys = repo.inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          (import "$ROOT/modules/identity/_oidc.nix")
          {
            services.identity.oidc.providerUrl = "https://probe-id.example";
            networking.hostName = "probe-host";
            system.stateVersion = "25.11";
          }
        ];
      };
      c = sys.config;
    in {
      clients = c.services.identity.oidc.clients;
      providerNamespaceAbsent = !(c.services.identity ? kanidm);
      hostAuthAbsent = !(c.services.identity ? hostAuth);
    };
  };
}
EOF2
fragment="$(nix eval --raw --impure --no-write-lock-file --expr \
  "builtins.toJSON ((builtins.getFlake (toString $probe_dir)).report)")" ||
  fail "the intrinsic client contract alone does not evaluate"

python3 - "$fragment" <<'PYEOF' || fail "intrinsic client contract observables violated"
import json, sys

got = json.loads(sys.argv[1])
errors = []
if not got.get("clients"):
    errors.append("no clients resolved from policy")
for absent in ("providerNamespaceAbsent", "hostAuthAbsent"):
    if got.get(absent) is not True:
        errors.append(f"{absent} must hold when only the client contract is imported")
if errors:
    print("; ".join(errors), file=sys.stderr)
    sys.exit(1)
PYEOF

# 3. A remote client host resolves the same contract with no provider selected:
# the contract is intrinsic, not a side effect of the provider's aspect.
report ".#nixosConfigurations.oci-melb-1.config" \
  'c: c.services.identity.oidc.clients.paperless.issuerUrl' > /dev/null ||
  fail "a remote client host resolves no client contract"

# 7. Fixture: Authentik with its runtime credentials supplied and a controlled roster.
authentik="$WORK/authentik"
mkdir -p "$authentik"
make_copy "$authentik"
cat >"$authentik/secrets/identity/authentik.yaml" <<'YAML'
# Fixture: evaluation reads the file's presence and keys, never its values.
authentik:
  secret_key: fixture
  postgres_password: fixture
  bootstrap_password: fixture
  bootstrap_token: fixture
YAML
# A roster to render: seeding is the behaviour under test, so the fixture supplies one.
python3 - "$authentik" <<'PYEOF'
import re, sys

p = sys.argv[1] + "/policy/identity.nix"
s = open(p).read()
# Replace the declared roster wholesale, so the suite controls exactly what renders.
pattern = re.compile(r"(?ms)^  users = \{ \};\n|^  users = \{\n.*?^  \};\n")
assert len(pattern.findall(s)) == 1, "seed-roster block drifted"
open(p, "w").write(pattern.sub("""  users = {
    alice = { name = "Alice"; email = "alice@example.com"; groups = [ "admins" ]; };
    bob = { name = "Bob"; email = "bob@example.com"; groups = [ "users" ]; };
    carol = { name = "Carol"; email = "carol@example.com"; groups = [ "users" "service-admins" ]; };
  };""", s, 1))
PYEOF
# 7b. The document Authentik applies: the seeded roster, invitation-gated enrollment and
# the brand. Rendered directly from policy, so this checks what policy produces rather
# than what a build happens to contain.
doc_yaml="$WORK/blueprint.yaml"
doc_json="$WORK/blueprint.json"
blueprint_tool_dir="$(
  nix build --no-link --print-out-paths --impure --expr '
    let
      flake = builtins.getFlake "path:'"${authentik}"'";
      tools = import ("'"${authentik}"'" + "/modules/identity/authentik/_blueprint/tools.nix") {
        pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
      };
    in
    tools.tool
  '
)" || fail "the blueprint helper does not build"
blueprint_tool="$blueprint_tool_dir/bin/authentik-blueprint-tools"
blueprint_python="$blueprint_tool_dir/bin/authentik-blueprint-python"
nix eval --no-write-lock-file --impure --json --expr '
  let
    root = '"${authentik}"';
    policy = import (root + "/policy/identity.nix");
    flake = builtins.getFlake "path:'"${authentik}"'";
    lib = flake.inputs.nixpkgs.lib;
    route = {
      publicUrl = "https://auth.example";
      endpoint = {
        host = "auth.example";
        port = 443;
      };
    };
  in
  import (root + "/modules/identity/authentik/_blueprint/document.nix") {
    inherit lib;
    groups = policy.groups;
    groupParents = policy.providers.authentik.groupParents;
    superuserGroups = policy.providers.authentik.superuserGroups;
    appRoles = policy.providers.authentik.appRoles;
    users = policy.users;
    inherit (policy.providers.authentik) brand enrollment;
    providerDomain = "auth.example";
    clients = policy.clients;
    routeFor = _: route;
  }
' >"$doc_json" || fail "the blueprint document does not render"
"$blueprint_tool" --output "$doc_yaml" "$doc_json" \
  || fail "the blueprint document does not assemble"
python3 "$ROOT/tests/assert-authentik-email-policy.py" "$doc_yaml" || fail "email-code proof policy failed"
"$blueprint_python" "$ROOT/tests/assert-authentik-mfa-invariants.py" "$doc_yaml" || fail "a session would be created without a second factor"
"$blueprint_python" - "$doc_yaml" "$authentik/policy/identity.nix" <<'PYEOF' || fail "the blueprint document violates the roster/enrollment/brand contract"
import re, sys

from ruamel.yaml import YAML

raw = YAML().load(open(sys.argv[1]))


def resolve(value, context):
    tag = str(getattr(value, "tag", ""))
    if tag == "!Context":
        return resolve(context.get(str(value)), context)
    if tag.startswith("!"):
        return str(value) if not isinstance(value, list) else [resolve(i, context) for i in value]
    if isinstance(value, dict):
        return {key: resolve(item, context) for key, item in value.items()}
    if isinstance(value, list):
        return [resolve(item, context) for item in value]
    return value


context = resolve(raw.get("context") or {}, {})
entries = resolve(raw["entries"], context)
policy = open(sys.argv[2]).read()
errors = []


def of_model(model):
    return [e for e in entries if e.get("model") == model]


# Roster: created once, never carrying a credential.
users = of_model("authentik_core.user")
for entry in users:
    if entry.get("state") != "created":
        errors.append(f"seeded user {entry.get('identifiers')} must use state: created")
    if {"password", "password_hash"} & set(entry.get("attrs") or {}):
        errors.append(f"seeded user {entry.get('identifiers')} must not declare a credential")
    if not (entry.get("attrs") or {}).get("email"):
        errors.append(f"seeded user {entry.get('identifiers')} carries no email")

# Group semantics: the projection marks the IdP-administrator groups, and self-enrollment
# must never land a person in one.
superuser_groups = sorted(
    g["identifiers"]["name"]
    for g in of_model("authentik_core.group")
    if (g.get("attrs") or {}).get("is_superuser") is True
)
# The tree must resolve, and the superuser flag must sit on a leaf: an ancestor that
# carries it escalates every group beneath it.
declared = {g["identifiers"]["name"]: (g.get("attrs") or {}) for g in of_model("authentik_core.group")}
for name, attrs in declared.items():
    for parent in str(attrs.get("parents") or "").split():
        if "group-" not in parent:
            continue
        resolved = parent.split("group-", 1)[1].strip("'\"[]")
        if resolved not in declared:
            errors.append(f"group {name} names an undeclared parent {resolved}")
        if resolved in superuser_groups:
            errors.append(f"group {name} inherits superuser status from {resolved}")

# A role may only be bound to a group its own application already admits, so declaring a
# role cannot widen access to an application.
app_groups = {}
for binding in of_model("authentik_policies.policybinding"):
    ids = binding.get("identifiers") or {}
    target, group = str(ids.get("target")), str(ids.get("group"))
    if target.startswith("app-") and "group-" in group:
        app_groups.setdefault(target, set()).add(group)
roles_by_app = {}
for entry in of_model("authentik_core.applicationentitlement"):
    ids = entry.get("identifiers") or {}
    roles_by_app.setdefault(str(ids.get("app")), []).append(ids.get("name"))
for entry in of_model("authentik_policies.policybinding"):
    ids = entry.get("identifiers") or {}
    target, group = str(ids.get("target")), str(ids.get("group"))
    if not target.startswith("entitlement-"):
        continue
    app = "app-" + target.split("entitlement-", 1)[1].rsplit("-", 1)[0]
    if app not in roles_by_app:
        errors.append(f"binding {target} names an entitlement the document omits")
    elif group not in app_groups.get(app, set()):
        errors.append(f"entitlement {target} grants {group}, which {app} does not admit")

# Enrollment must never place a person in a group that administers the provider.
enrolled_into = [
    w.get("attrs") or {}
    for w in of_model("authentik_stages_user_write.userwritestage")
    if "create_users_group" in (w.get("attrs") or {})
]
for attrs in enrolled_into:
    target = str(attrs.get("create_users_group"))
    if any(f"group-{name}" in target for name in superuser_groups):
        errors.append(f"enrollment places new people in an administrator group: {target}")

# Enrollment: one invitation-gated flow, closed without a token.
invitations = of_model("authentik_stages_invitation.invitationstage")
if len(invitations) != 1 or (invitations[0].get("attrs") or {}).get("continue_flow_without_invitation") is not False:
    errors.append(f"enrollment must stop without an invitation: {invitations}")
code_stages = of_model("authentik_stages_authenticator_email.authenticatoremailstage")
if len(code_stages) != 1:
    errors.append("email verification must use one shared native code stage")
else:
    code_id = code_stages[0]["id"]
    code_bindings = [b for b in of_model("authentik_flows.flowstagebinding")
                     if code_id in str((b.get("attrs") or {}).get("stage"))]
    if len(code_bindings) != 3:
        errors.append("enrollment, login and re-verification must share the code stage")
    for binding in code_bindings:
        if not any(binding["id"] in str((p.get("attrs") or {}).get("target"))
                   and "policy-email-" in str((p.get("attrs") or {}).get("policy"))
                   for p in of_model("authentik_policies.policybinding")):
            errors.append(f"code stage is not gated by address verification: {binding['id']}")

#
# Recovery has its own user-write stage; the enrollment one is the one that creates people.
writes = [
    w
    for w in of_model("authentik_stages_user_write.userwritestage")
    if "create_users_group" in (w.get("attrs") or {})
]
if len(writes) != 1 or "group-" not in str((writes[0].get("attrs") or {}).get("create_users_group")):
    errors.append(f"the enrollment flow must place new people in a declared group: {writes}")
elif (writes[0].get("attrs") or {}).get("create_users_as_inactive") is not True:
    errors.append("enrollment must create people inactive until their email is confirmed")


# Brand: keyed to the identity host rather than replacing the default brand.
brands = of_model("authentik_brands.brand")
if len(brands) != 1:
    errors.append(f"expected one brand, got {len(brands)}")
else:
    attrs = brands[0].get("attrs") or {}
    if attrs.get("default"):
        errors.append("the brand must not claim to be Authentik's default")
    css = attrs.get("branding_custom_css") or ""
    # A background must come from the fleet's own assets host, not a third-party URL.
    backgrounds = "\n".join(line for line in css.splitlines() if "background" in line)
    remote = [
        url
        for url in re.findall(r"url\(\s*['\"]?([^'\")]+)", backgrounds)
        if url.startswith(("http://", "https://", "//"))
        and not url.startswith("https://assets.shrublab.xyz/")
    ]
    if remote:
        errors.append(f"the flow background fetches a third-party asset: {remote}")
    if re.search(r"@import\s+url\(\s*['\"]?https?://", css):
        errors.append("the login theme imports a remote stylesheet")

# Account continuity across a provider swap keys on the email claim, so the IdP must
# assert a verified address and every provider must reference that mapping.
email_maps = [
    e
    for e in of_model("authentik_providers_oauth2.scopemapping")
    if (e.get("attrs") or {}).get("scope_name") == "email"
]
if len(email_maps) != 1:
    errors.append(f"expected one fleet email mapping, got {len(email_maps)}")
for provider in (
    e for e in of_model("authentik_providers_oauth2.oauth2provider") if e.get("state") != "absent"
):
    mappings = str((provider.get("attrs") or {}).get("property_mappings"))
    if "scope-homelab-email" not in mappings:
        errors.append(f"provider {provider.get('identifiers')} omits the fleet email mapping")
    if "OpenID 'email'" in mappings:
        errors.append(
            f"provider {provider.get('identifiers')} still uses Authentik's default email mapping"
        )
    # An empty grant list still creates the provider, then rejects every authorize request.
    grants = (provider.get("attrs") or {}).get("grant_types")
    if "authorization_code" not in (grants or []):
        errors.append(f"provider {provider.get('identifiers')} admits no authorization-code grant")
if errors:
    print("; ".join(errors), file=sys.stderr)
    sys.exit(1)
PYEOF

# 7c. A roster naming an undeclared group must fail by name, not seed a group that
# does not exist.
undeclared_out="$(
  nix eval --no-write-lock-file --impure --raw --expr '
    let
      root = '"${authentik}"';
      policy = import (root + "/policy/identity.nix");
      flake = builtins.getFlake "path:'"${authentik}"'";
    lib = flake.inputs.nixpkgs.lib;
    in
    import (root + "/modules/identity/authentik/_blueprint/document.nix") {
      inherit lib;
      groups = policy.groups;
      groupParents = policy.providers.authentik.groupParents;
      superuserGroups = policy.providers.authentik.superuserGroups;
      appRoles = policy.providers.authentik.appRoles;
      users = {
        dave = {
          name = "Dave";
          email = "dave@example.com";
          groups = [ "operators" ];
        };
      };
      inherit (policy.providers.authentik) brand enrollment;
      providerDomain = "auth.example";
      clients = { };
      routeFor = _: { };
    }
  ' 2>&1
)" && fail "an undeclared roster group must fail rendering"
case "$undeclared_out" in
*"undeclared groups: operators"*) ;;
*) fail "expected the named undeclared-group error, got: $(printf '%s' "$undeclared_out" | tail -3)" ;;
esac

# 8. Cloudflare Access federates with the same client contract. A cutover that moved the
# provider without moving the Access IdP would leave every Access-gated route unreachable,
# so the infrastructure input is checked against the contract rather than trusted.
# Read from a host that composes the contract: the provider host runs no OIDC client of
# its own, so the namespace is absent there by design.
idp_json="$(report ".#nixosConfigurations.oci-melb-1.config" 'c: let k = c.services.identity.oidc.clients."cloudflare-access"; in builtins.toJSON {
  name = k.providerName;
  authUrl = k.authorizationUrl;
  tokenUrl = k.tokenUrl;
  certsUrl = k.jwksUrl;
}')" || fail "the Cloudflare Access client does not resolve"
python3 - "$idp_json" "$ROOT/opentofu/cloudflare/config.auto.tfvars" <<'PYEOF' || fail "Cloudflare Access must federate with the client contract"
import json, re, sys

contract = json.loads(sys.argv[1])
tfvars = open(sys.argv[2]).read()

def value(key):
    match = re.search(rf'^{key}\s*=\s*"([^"]*)"', tfvars, re.MULTILINE)
    return match.group(1) if match else None

errors = []
for key, want in (
    ("idp_name", contract["name"]),
    ("idp_auth_url", contract["authUrl"]),
    ("idp_token_url", contract["tokenUrl"]),
    ("idp_certs_url", contract["certsUrl"]),
):
    got = value(key)
    if got != want:
        errors.append(f"{key}: opentofu declares {got!r}, the client contract resolves {want!r}")
if errors:
    print("; ".join(errors), file=sys.stderr)
    sys.exit(1)
PYEOF

echo "check-identity-contract-directionality: PASS"
