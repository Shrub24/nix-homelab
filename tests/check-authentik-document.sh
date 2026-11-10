#!/usr/bin/env bash
set -euo pipefail

# The document Authentik applies, rendered from policy: the seeded roster, the
# invitation-gated enrollment flow, group and role semantics, and the brand. The
# invariants here are the ones no evaluation fails on — a role bound to a group
# its application does not admit, a superuser flag on an ancestor group, an
# enrollment flow that admits a stranger.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "check-authentik-document: $*" >&2
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

WORK="$(mktemp -d /tmp/authentik-document.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# 1. The client contract alone resolves endpoints and starts nothing. Explicit
# 3. Fixture: Authentik with its runtime credentials supplied and a controlled roster.
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
# Lifecycle: a client the policy disables leaves through a tombstone, because reconciliation
# never deletes and the provider would otherwise keep a working login path.
"$blueprint_python" - "$doc_yaml" <<'PYTOMB' || fail "a disabled client is not tombstoned"
import sys

from ruamel.yaml import YAML

raw = YAML().load(open(sys.argv[1]))
entries = raw["entries"]
errors = []

absent = [
    entry
    for entry in entries
    if entry.get("state") == "absent" and entry.get("model", "").startswith("authentik_")
]
retired = {
    str(entry["identifiers"].get("name"))
    for entry in absent
    if entry["model"] == "authentik_providers_oauth2.oauth2provider"
}

for name in retired:
    models = {entry["model"] for entry in absent if name in str(entry.get("identifiers", {}))}
    for model in ("authentik_core.application", "authentik_providers_oauth2.oauth2provider"):
        if model not in models:
            errors.append(f"{name}: no {model} tombstone")
    if any(
        entry.get("model") == "authentik_providers_oauth2.oauth2provider"
        and entry.get("state") != "absent"
        and str(entry["identifiers"].get("name")) == name
        for entry in entries
    ):
        errors.append(f"{name}: tombstoned client still renders an active provider")

if errors:
    print("; ".join(errors), file=sys.stderr)
    sys.exit(1)
PYTOMB

"$blueprint_python" - "$doc_yaml" <<'PYREDIR' || fail "the rendered redirect allowlist is wrong"
import sys

from ruamel.yaml import YAML

raw = YAML().load(open(sys.argv[1]))
errors = []


def text(value):
    return str(value)


providers = [
    entry
    for entry in raw["entries"]
    if entry.get("model") == "authentik_providers_oauth2.oauth2provider"
    and entry.get("state") != "absent"
]
if not providers:
    errors.append("the document renders no OAuth provider")

for entry in providers:
    name = entry["identifiers"]["name"]
    uris = [text(uri["url"]) for uri in entry["attrs"].get("redirect_uris", [])]
    if not uris:
        errors.append(f"{name}: no redirect URI")
        continue
    for uri in uris:
        scheme = uri.split("://", 1)[0] if "://" in uri else ""
        if not scheme:
            errors.append(f"{name}: redirect {uri!r} is not absolute")
        elif scheme == "http":
            # A native client may register its own scheme, but no redirect travels in clear.
            errors.append(f"{name}: redirect {uri!r} is plaintext")
    # A provider whose identifier appears in its callback path takes it from the client id,
    # so the two cannot drift apart under a rename.
    if name in ("paperless", "tududi"):
        if not all(f"/{name}/" in uri or uri.endswith(f"/{name}") for uri in uris):
            errors.append(f"{name}: redirect {uris!r} does not carry the client id")

if errors:
    print("; ".join(errors), file=sys.stderr)
    sys.exit(1)
PYREDIR
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
code_ids = {e["id"] for e in of_model("authentik_stages_authenticator_email.authenticatoremailstage")}
code_bindings = [b for b in of_model("authentik_flows.flowstagebinding")
                 if any(stage in str((b.get("attrs") or {}).get("stage")) for stage in code_ids)]
if not code_bindings:
    errors.append("no email verification path is checked")
else:
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


echo "check-authentik-document: PASS"
