# The credential name shared by the runtime environment and the generated blueprints.
{ lib }:
let
  envSuffix = name: lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] name);
in
{
  secretName = name: "authentik_client_secret_${envSuffix name}";
  envVar = name: "AUTHENTIK_CLIENT_SECRET_${envSuffix name}";
}
