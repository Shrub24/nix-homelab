{
  aiGateway = {
    aliases = {
      text = "shrublab-text";
      image = "shrublab-image";
      embedding = "shrublab-embedding";
      fallback = "shrublab-fallback";
    };
    configFile = ./bifrost-config.json;
  };

  s3 = {
    endpoint = "https://bef816e6776e8f13f5c03d2af70b036e.r2.cloudflarestorage.com";
    region = "auto";
    forcePathStyle = true;
  };

  applications = {
    music = {
      dataRoot = "/srv/data";
      mediaRoot = "/srv/media";
    };
    admin = {
      dataRoot = "/srv/data";
    };
    edge-ingress = {
      enable = false;
      role = "none";
    };
  };

  notifications = {
    telegram = {
      chatId = "-1003913476155";

      topics = {
        critical = "2";
        warning = "3";
        info = "4";
        music = "5";
        system = "6";
      };
    };
  };

  services = {
    nix = {
      substituters = [
        "ssh-ng://eu.nixbuild.net?priority=0"
        "https://nix-community.cachix.org"
        "https://cache.shrublab.xyz"
      ];
      trustedSubstituters = [
        "ssh-ng://eu.nixbuild.net?priority=0"
        "https://nix-community.cachix.org"
        "https://cache.shrublab.xyz"
      ];
      trustedPublicKeys = [
        "nixbuild.net/HWWKWC-1:dnSfpPDHQN/U9wexkK6r3GTaYrwqNwKS70SNGXistKg="
        "nix-cache-1:FW0bJll9BP5ch0mHI+bXOImcD0RKLrH117WfQC+CU4A="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };

    karakeep-pod = {
      dataDir = "/srv/data/karakeep";
      port = 3010;
      s3.bucket = "karakeep";
    };
    bifrost-gateway = {
      dataDir = "/srv/data/bifrost";
    };
  };
}
