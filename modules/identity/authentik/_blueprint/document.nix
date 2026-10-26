# The blueprint document rendered from policy: brand, seed roster, groups and bindings,
# enrollment and approved clients.
{
  lib,
  groups,
  groupParents,
  superuserGroups,
  users,
  brand,
  enrollment,
  providerDomain,
  appRoles,
  clients,
  links ? { },
  routeFor,
}:
let
  identityRedirects = import ../../_redirects.nix;
  assets = import ../../../../policy/assets.nix;
  iconFor =
    name: origin:
    let
      source = assets.icons.${name} or { };
    in
    if source ? url then
      source.url
    else if origin == null then
      null
    else if source ? path then
      "${origin}${source.path}"
    else
      "${origin}/favicon.ico";
  credentials = import ../_credentials.nix { inherit lib; };
  clientScopes = client: lib.unique (builtins.concatLists (lib.attrValues client.access));

  tag = text: { __raw = text; };
  fragment = path: { __file = path; };

  needsGroupsClaim = builtins.any (client: lib.elem "groups" (clientScopes client)) (
    builtins.attrValues clients
  );

  # Parents must apply before children; policy declares groups in the reverse order.
  groupOrder =
    let
      step =
        done: remaining:
        let
          eligible = builtins.filter (
            name: builtins.all (parent: lib.elem parent done) (lib.toList (groupParents.${name} or [ ]))
          ) remaining;
        in
        if remaining == [ ] then
          done
        else if eligible == [ ] then
          throw "authentik blueprint: group parentage is cyclic: ${lib.concatStringsSep ", " remaining}"
        else
          step (done ++ eligible) (builtins.filter (name: !(lib.elem name eligible)) remaining);
    in
    step [ ] groups;

  groupEntries = map (name: {
    model = "authentik_core.group";
    id = "group-${name}";
    identifiers.name = name;
    attrs = {
      name = name;
    }
    // lib.optionalAttrs (groupParents ? ${name}) {
      parents = [ (tag "!KeyOf group-${groupParents.${name}}") ];
    }
    // lib.optionalAttrs (lib.elem name superuserGroups) { is_superuser = true; };
  }) groupOrder;

  # `created`, never `present`: the provider owns the person after seeding.
  userEntries = lib.mapAttrsToList (username: user: {
    model = "authentik_core.user";
    id = "user-${username}";
    state = "created";
    identifiers.username = username;
    attrs = {
      inherit username;
      inherit (user) name email;
      is_active = true;
    }
    // lib.optionalAttrs (user.groups or [ ] != [ ]) {
      groups = map (group: tag "!KeyOf group-${group}") user.groups;
    };
  }) users;

  dashboardGroups = lib.unique (
    builtins.filter (group: group != null) (
      lib.mapAttrsToList (_: client: client.group or null) clients
      ++ lib.mapAttrsToList (_: link: link.group or null) links
    )
  );

  brandEntries = import ./brand.nix {
    inherit
      lib
      brand
      providerDomain
      dashboardGroups
      ;
  };

  clientEntries =
    name: client:
    let
      redirects = identityRedirects {
        clientPolicy = client;
        route = if client ? route then routeFor name else null;
      };
      scopes = clientScopes client;
      defaultMappings =
        lib.optional (lib.elem "openid" scopes) "authentik default OAuth Mapping: OpenID 'openid'"
        ++ lib.optional (lib.elem "profile" scopes) "authentik default OAuth Mapping: OpenID 'profile'";
      routeUrl = if client ? route then (routeFor name).publicUrl or null else null;
      icon = iconFor name routeUrl;
      allowedGroups = lib.attrNames client.access;
      releasesGroups = lib.elem "groups" scopes;
    in
    [
      {
        model = "authentik_providers_oauth2.oauth2provider";
        id = "provider-${name}";
        identifiers.name = name;
        attrs = {
          name = name;
          client_type = "confidential";
          client_id = name;
          client_secret = tag "!Env ${credentials.envVar name}";
          include_claims_in_id_token = true;
          # An empty grant list rejects every authorize request, and blueprints get no default.
          grant_types = [
            "authorization_code"
            "refresh_token"
          ];
          authorization_flow = tag "!Find [authentik_flows.flow, [slug, default-provider-authorization-implicit-consent]]";
          invalidation_flow = tag "!Find [authentik_flows.flow, [slug, default-provider-invalidation-flow]]";
          signing_key = tag "!Find [authentik_crypto.certificatekeypair, [name, authentik Self-signed Certificate]]";
          redirect_uris = map (uri: {
            matching_mode = "strict";
            url = uri;
          }) redirects;
          property_mappings =
            map (
              mapping: tag "!Find [authentik_providers_oauth2.scopemapping, [name, \"${mapping}\"]]"
            ) defaultMappings
            ++ lib.optional (lib.elem "email" scopes) (tag "!KeyOf scope-homelab-email")
            ++ lib.optional releasesGroups (tag "!KeyOf scope-homelab-groups");
        };
      }
      {
        model = "authentik_core.application";
        id = "app-${name}";
        identifiers.slug = name;
        attrs = {
          name = client.displayName;
          slug = name;
          meta_hide = !(client.showInDashboard or true);
          provider = tag "!KeyOf provider-${name}";
          policy_engine_mode = "any";
        }
        // lib.optionalAttrs (icon != null) { meta_icon = icon; }
        // lib.optionalAttrs (client.group or null != null) { group = client.group; };
      }
    ]
    ++ lib.imap0 (index: group: {
      model = "authentik_policies.policybinding";
      id = "binding-${name}-${group}";
      identifiers = {
        target = tag "!KeyOf app-${name}";
        group = tag "!KeyOf group-${group}";
      };
      attrs = {
        target = tag "!KeyOf app-${name}";
        group = tag "!KeyOf group-${group}";
        order = index + 10;
        enabled = true;
      };
    }) allowedGroups;

  linkEntries =
    name: link:
    let
      url = (routeFor name).publicUrl;
    in
    [
      {
        model = "authentik_core.application";
        id = "app-${name}";
        identifiers.slug = name;
        attrs = {
          name = link.displayName;
          slug = name;
          meta_launch_url = url;
          meta_icon = iconFor name url;
          policy_engine_mode = "any";
        }
        // lib.optionalAttrs (link.group or null != null) { group = link.group; };
      }
    ]
    ++ lib.imap0 (index: group: {
      model = "authentik_policies.policybinding";
      id = "binding-${name}-${group}";
      identifiers = {
        target = tag "!KeyOf app-${name}";
        group = tag "!KeyOf group-${group}";
      };
      attrs = {
        target = tag "!KeyOf app-${name}";
        group = tag "!KeyOf group-${group}";
        order = index + 10;
        enabled = true;
      };
    }) link.access;

  # A role is realised as <client>-<role>, bound to the group that holds it.
  clientRoleEntries =
    name: client:
    let
      allowedGroups = lib.attrNames client.access;
      leastPrivileged = holders: lib.findFirst (holder: lib.elem holder allowedGroups) null holders;
      admitsUser = leastPrivileged appRoles.user != null;
      held = lib.filterAttrs (_role: holders: admitsUser && leastPrivileged holders != null) appRoles;
    in
    lib.concatLists (
      lib.mapAttrsToList (role: holders: [
        {
          model = "authentik_core.applicationentitlement";
          id = "entitlement-${name}-${role}";
          identifiers = {
            name = "${name}-${role}";
            app = tag "!KeyOf app-${name}";
          };
          attrs = {
            name = "${name}-${role}";
            app = tag "!KeyOf app-${name}";
          };
        }
        {
          model = "authentik_policies.policybinding";
          id = "entitlement-binding-${name}-${role}";
          identifiers = {
            target = tag "!KeyOf entitlement-${name}-${role}";
            group = tag "!KeyOf group-${leastPrivileged holders}";
          };
          attrs = {
            target = tag "!KeyOf entitlement-${name}-${role}";
            group = tag "!KeyOf group-${leastPrivileged holders}";
            order = 10;
            enabled = true;
          };
        }
      ]) held
    );

  # Reconciliation never deletes, so a disabled client needs a tombstone to leave the dashboard.
  retiredClients = [ "termix" ];
  retiredClientEntries =
    map (name: {
      model = "authentik_core.application";
      id = "app-${name}";
      identifiers.slug = name;
      state = "absent";
    }) retiredClients
    ++ map (name: {
      model = "authentik_providers_oauth2.oauth2provider";
      id = "provider-${name}";
      identifiers.name = name;
      state = "absent";
    }) retiredClients;

  undeclaredGroups = lib.unique (
    lib.optionals (!(lib.elem enrollment.group groups)) [ enrollment.group ]
    ++ lib.concatMap (user: lib.subtractLists groups (user.groups or [ ])) (lib.attrValues users)
  );
in
if undeclaredGroups != [ ] then
  throw "authentik blueprint: policy/identity.nix uses undeclared groups: ${lib.concatStringsSep ", " undeclaredGroups}"
else
  {
    version = 1;
    metadata = {
      name = "homelab-identity";
      labels."blueprints.goauthentik.io/description" = "Fleet identity clients and access";
    };
    context = {
      enrollment-flow = enrollment.flow;
      enrollment-title = enrollment.title;
      enrollment-group = tag "!KeyOf group-${enrollment.group}";
      flow-background = brand.flowBackground;
    };
    entries =
      brandEntries
      ++ groupEntries
      ++ [ (fragment ./fragments/email-claim.yaml) ]
      ++ lib.optional needsGroupsClaim (fragment ./fragments/groups-claim.yaml)
      ++ userEntries
      ++ map fragment [
        ./fragments/recovery.yaml
        ./fragments/passkeys.yaml
        ./fragments/mfa.yaml
        ./fragments/wording.yaml
        ./fragments/verification.yaml
        ./fragments/enrollment.yaml
      ]
      ++ lib.concatLists (lib.mapAttrsToList clientEntries clients)
      ++ lib.concatLists (lib.mapAttrsToList clientRoleEntries clients)
      ++ lib.concatLists (lib.mapAttrsToList linkEntries links)
      ++ retiredClientEntries;
  }
