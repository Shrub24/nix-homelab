# Fleet identity registration policy: approved OIDC clients, their allowed groups and
# granted scopes. The client contract and the provider projection read this independently
# — registration is approval, not a side effect of composing an application.
let
  assets = import ./assets.nix;
  globals = import ./globals.nix;
in
{
  # The provider serving application SSO; a retained provider is selected through its
  # own aspect and is not redirected by this value.
  provider = "authentik";

  # Each provider's route carries its public identity; a null route makes selecting
  # that provider fail closed instead of inventing a URL.
  providers = {
    kanidm.route = "kanidm-admin";
    authentik = {
      route = "authentik-admin";
      # A member of a group is an effective member of its ancestors, so authority accumulates
      # upward and a person belongs to the most privileged group they need. The superuser flag
      # sits on the leaf: an ancestor that carries it escalates every group beneath it.
      groupParents = {
        service-admins = "users";
        admins = "service-admins";
        superusers = "admins";
      };
      superuserGroups = [ "superusers" ];
      # Per-application roles, each with the groups that may hold it in privilege order: the
      # role binds to the first one the client admits. A client that admits no user group keeps
      # using the group names alone, so an admin-only application declares no roles.
      appRoles = {
        user = [ "users" ];
        admin = [
          "service-admins"
          "admins"
          "superusers"
        ];
      };
      # Invitation-gated enrollment: a person is created only from an invitation and
      # lands in this group.
      enrollment = {
        flow = "enrollment";
        title = "Welcome to Shrublab!";
        group = "users";
      };
      # The identity host's own surface. The logo and favicon are the fleet's public
      # assets, fetched by the viewer's browser from the assets host.
      brand = {
        title = "shrublab";
        logo = assets.brand.logo.url;
        favicon = assets.brand.icon.url;
        flowBackground = assets.brand.wallpaper.url;
        # Same image as the flows; Authentik takes this one as a CSS declaration on the
        # Application Dashboard's fixed background layer rather than as a URL.
        dashboardBackground = assets.brand.wallpaper.url;
        backgroundTint = "rgb(0 0 0 / 40%)";
        themeBase = "dark";
        dashboardLayout = "2-column";
        navbarUserDisplay = "name";
        applicationEdit = false;
      };
    };
  };

  # Declared groups; membership is provider-owned state.
  groups = [
    "admins"
    "service-admins"
    "superusers"
    "users"
  ];

  # Seed roster: created once and owned by the provider afterwards; credentials are never
  # declared here. Removing an entry does not delete the account it already created.
  users = { };

  # `access` maps each allowed group to the scopes it grants. `groups` is intent, not a
  # provider scope name: it means "release the caller's group names", which each
  # provider realises its own way.
  # Applications with their own sign-in: a launcher tile for the people in `access`, with no
  # provider behind it. Listing one grants nothing at the destination.
  links = {
    inbox-zero = {
      displayName = "Inbox Zero";
      group = "Utility";
      route = "inbox-zero";
      access = [ "users" ];
    };
  };

  clients = {
    beszel = {
      displayName = "Beszel";
      # Dashboard grouping: the library renders one section per group.
      group = "Observability";
      route = "beszel-admin";
      callbackPath = "/api/oauth2-redirect";
      access.admins = [
        "openid"
        "profile"
        "email"
      ];
    };

    termix = {
      enable = false;
      displayName = "Termix";
      # Dashboard grouping: the library renders one section per group.
      group = "Admin";
      route = "termix-admin";
      callbackPath = "/users/oidc/callback";
      access.admins = [
        "openid"
        "profile"
        "email"
      ];
      kanidm.allowInsecureClientDisablePkce = true;
    };

    karakeep = {
      displayName = "Karakeep";
      # Dashboard grouping: the library renders one section per group.
      group = "Capture";
      route = "karakeep";
      callbackPath = "/api/auth/callback/custom";
      access = {
        service-admins = [
          "openid"
          "profile"
          "email"
        ];
        users = [
          "openid"
          "profile"
          "email"
        ];
      };
      kanidm.enableLegacyCrypto = true;
    };

    paperless = {
      displayName = "Paperless";
      # Dashboard grouping: the library renders one section per group.
      group = "Utility";
      route = "paperless";
      callbackPath = "/accounts/oidc/paperless/login/callback/";
      access = {
        service-admins = [
          "openid"
          "profile"
          "email"
          "groups"
        ];
        users = [
          "openid"
          "profile"
          "email"
          "groups"
        ];
      };
    };

    langfuse = {
      displayName = "Langfuse";
      # Dashboard grouping: the library renders one section per group.
      group = "Observability";
      route = "langfuse";
      callbackPath = "/api/auth/callback/custom";
      access = {
        service-admins = [
          "openid"
          "profile"
          "email"
        ];
        users = [
          "openid"
          "profile"
          "email"
        ];
      };
    };

    grafana = {
      displayName = "Grafana";
      # Dashboard grouping: the library renders one section per group.
      group = "Observability";
      route = "grafana";
      callbackPath = "/login/generic_oauth";
      access.admins = [
        "openid"
        "profile"
        "email"
        "groups"
      ];
    };

    actual = {
      displayName = "Actual Budget";
      # Dashboard grouping: the library renders one section per group.
      group = "Utility";
      route = "actual";
      callbackPath = "/openid/callback";
      access = {
        service-admins = [
          "openid"
          "profile"
          "email"
        ];
        users = [
          "openid"
          "profile"
          "email"
        ];
      };
      kanidm.enableLegacyCrypto = true;
    };

    memos = {
      displayName = "Memos";
      # Dashboard grouping: the library renders one section per group.
      group = "Capture";
      route = "memos";
      callbackPath = "/auth/callback";
      access = {
        service-admins = [
          "openid"
          "profile"
          "email"
        ];
        users = [
          "openid"
          "profile"
          "email"
        ];
      };
    };

    bookorbit = {
      displayName = "BookOrbit";
      # Dashboard grouping: the library renders one section per group.
      group = "Media";
      route = "bookorbit";
      callbackPath = "/oauth2-callback";
      additionalRedirectUrls = [ "bookorbit://oauth2-callback" ];
      access = {
        service-admins = [
          "openid"
          "profile"
          "email"
          "groups"
        ];
        users = [
          "openid"
          "profile"
          "email"
          "groups"
        ];
      };
      kanidm.preferShortUsername = true;
    };

    tududi = {
      displayName = "tududi";
      # Dashboard grouping: the library renders one section per group.
      group = "Capture";
      route = "tududi";
      callbackPath = "/api/oidc/callback/tududi";
      access = {
        service-admins = [
          "openid"
          "profile"
          "email"
        ];
        users = [
          "openid"
          "profile"
          "email"
        ];
      };
      kanidm.enableLegacyCrypto = true;
    };

    geopulse = {
      displayName = "GeoPulse";
      # Dashboard grouping: the library renders one section per group.
      group = "Everyday";
      route = "geopulse";
      callbackPath = "/oidc/callback";
      includePrivateEndpointCallback = true;
      access.users = [
        "openid"
        "profile"
        "email"
      ];
      kanidm = {
        allowInsecureClientDisablePkce = true;
        enableLegacyCrypto = true;
      };
    };

    homarr = {
      displayName = "Homarr";
      # Dashboard grouping: the library renders one section per group.
      group = "Everyday";
      route = "homarr";
      callbackPath = "/api/auth/callback/oidc";
      includePrivateEndpointCallback = true;
      access = {
        service-admins = [
          "openid"
          "profile"
          "email"
          "groups"
        ];
        users = [
          "openid"
          "profile"
          "email"
          "groups"
        ];
      };
    };

    # Registered for Cloudflare Access, which configures itself through the
    # provider's console: no application module consumes this client.
    cloudflare-access = {
      displayName = "Cloudflare Access";
      # Dashboard grouping: the library renders one section per group.
      group = "Admin";
      showInDashboard = false;
      originUrl = "https://shrublab.cloudflareaccess.com/cdn-cgi/access/callback";
      access = {
        admins = [
          "openid"
          "profile"
          "email"
          "groups"
        ];
        users = [
          "openid"
          "profile"
          "email"
          "groups"
        ];
      };
    };
  };
}
