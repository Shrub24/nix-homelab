{ lib }:
let
  policy = import ../policy/identity.nix;
in
import ../modules/identity/authentik/_blueprint/document.nix {
  inherit lib;
  inherit (policy) groups;
  inherit (policy.providers.authentik)
    groupParents
    superuserGroups
    appRoles
    brand
    enrollment
    ;
  users = { };
  clients = { };
  providerDomain = "testserver";
  routeFor = _: throw "enrollment acceptance has no application routes";
}
