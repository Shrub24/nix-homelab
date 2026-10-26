# The fleet stylesheet plus policy-owned tokens and one mark rule per dashboard group. Marks key on
# `data-group-id` (the lowercased group name); a group without a mark fails evaluation.
{
  lib,
  backgroundTint,
  wallpaperUrl,
  logoUrl,
  iconUrl,
  groups,
}:
let
  quote = "\\\"";

  marks = {
    Capture = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><path fill='white' d='M4 17.5V20h2.5L19 7.5 16.5 5z'/><path fill='white' d='M15 6.5L17.5 9l1.6-1.6a1 1 0 0 0 0-1.4l-1.1-1.1a1 1 0 0 0-1.4 0z'/></svg>";
    Media = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><path fill='white' d='M8 5.5v13l11-6.5z'/></svg>";
    Utility = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><path fill='none' stroke='white' stroke-width='2' stroke-linecap='round' d='M4 7h16M4 12h16M4 17h16'/><circle cx='9' cy='7' r='2.4' fill='white'/><circle cx='15' cy='12' r='2.4' fill='white'/><circle cx='8' cy='17' r='2.4' fill='white'/></svg>";
    Observability = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><path fill='none' stroke='white' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round' d='M3 18l5-6 4 3 8-9'/></svg>";
    Everyday = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><path fill='white' d='M12 3l9 8h-3v9h-5v-6h-2v6H6v-9H3z'/></svg>";
    Admin = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><path fill='white' d='M5 10h14v10H5z'/><path fill='none' stroke='white' stroke-width='2.2' d='M8.5 10V7.5a3.5 3.5 0 0 1 7 0V10'/></svg>";
  };

  dataUri =
    svg: "data:image/svg+xml," + builtins.replaceStrings [ "<" ">" quote ] [ "%3C" "%3E" "'" ] svg;

  groupId = group: builtins.replaceStrings [ " " ] [ "-" ] (lib.toLower group);

  rule = group: ''
    :host(ak-library-impl) [part="app-group"][data-group-id="${groupId group}"] [part="row-link"]::after {
        background-image: url("${dataUri marks.${group}}");
    }
  '';

  unmarked = builtins.filter (group: !(marks ? ${group})) groups;
in
if unmarked != [ ] then
  throw "identity theme: no dashboard mark for group(s) ${builtins.concatStringsSep ", " unmarked}"
else
  builtins.readFile ./login-theme.css
  + ''
    :root, :host {
      --shrublab-background-tint: ${backgroundTint};
      --shrublab-wallpaper: url("${wallpaperUrl}");
      --shrublab-logo: url("${logoUrl}");
      --shrublab-icon: url("${iconUrl}");
    }
  ''
  + builtins.concatStringsSep "\n" (map rule groups)
