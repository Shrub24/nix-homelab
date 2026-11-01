# Redirect allowlist for one approved client, resolved once so a provider swap cannot
# change what is permitted.
{ clientPolicy, route }:
let
  canonical =
    if (clientPolicy.originUrl or null) != null then
      clientPolicy.originUrl
    else
      "${route.publicUrl}${clientPolicy.callbackPath}";
in
(if builtins.isList canonical then canonical else [ canonical ])
++ (clientPolicy.additionalRedirectUrls or [ ])
