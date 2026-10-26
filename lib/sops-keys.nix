# SOPS encrypts values, not key names, so a credential's presence is visible without
# decrypting. Consumers use this to keep a binding inert until an operator supplies the
# key, instead of failing activation on a missing secret.
{ lib }:
{
  hasKey =
    file: section: key:
    (lib.foldl'
      (
        acc: line:
        if line == "${section}:" || line == "\"${section}\":" then
          {
            inSection = true;
            found = acc.found;
          }
        else if acc.inSection && lib.hasPrefix " " line then
          {
            inSection = true;
            found = acc.found || lib.hasInfix "${key}:" line;
          }
        else if line == "" then
          acc
        else
          {
            inSection = false;
            found = acc.found;
          }
      )
      {
        inSection = false;
        found = false;
      }
      (if file == null then [ ] else lib.splitString "\n" (builtins.readFile file))
    ).found;
}
