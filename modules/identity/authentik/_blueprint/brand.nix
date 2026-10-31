# The identity host's brand, keyed by domain so Authentik's default brand is left alone.
{
  lib,
  brand,
  providerDomain,
  dashboardGroups,
}:
[
  {
    model = "authentik_brands.brand";
    id = "brand";
    identifiers.domain = providerDomain;
    attrs = {
      domain = providerDomain;
      branding_title = brand.title;
      # One logo serves the card and the top bar; the theme swaps the bar to the icon.
      branding_logo = brand.logo;
      branding_favicon = brand.favicon;
      branding_default_flow_background = brand.flowBackground;
      branding_custom_css = import ./theme.nix {
        inherit lib;
        groups = dashboardGroups;
        inherit (brand) backgroundTint;
        logoUrl = brand.logo;
        iconUrl = brand.favicon;
        wallpaperUrl = brand.dashboardBackground;
      };
      attributes.settings = {
        theme.base = brand.themeBase;
        # Rendered as the inline style of a fixed layer, so it is a whole declaration.
        theme.background = "background: linear-gradient(${brand.backgroundTint}, ${brand.backgroundTint}), url(\"${brand.dashboardBackground}\") center / cover no-repeat;";
        layout.type = brand.dashboardLayout;
        navbar.userDisplay = brand.navbarUserDisplay;
        enabledFeatures.applicationEdit = brand.applicationEdit;
      };
    };
  }
]
