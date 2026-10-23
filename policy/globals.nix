{
  # The tailnet suffix, written once: host records derive their FQDN from it and the
  # web policy composes host-backed FQDNs with it.
  tailnet = {
    suffix = "tail0fe19b.ts.net";
  };

  # Container-facing service address: a dummy interface on from boot. A container cannot
  # reach a native service over its own bridge, so such services bind this address.
  serviceNetwork = {
    interface = "svc0";
    address = "10.255.0.1";
    prefixLength = 32;
    # Dial this instead of `host.containers.internal`, which resolves to whichever
    # gateway the container's own network happens to have.
    hostName = "host.services.internal";
    # Supernet every Podman network is drawn from; scopes both the ingress rule and
    # the service-level ACLs, so only container traffic reaches the service address.
    containerSourceCIDR = "10.89.0.0/16";
  };

  # ClickHouse HTTP, off its conventional 8123 because home-forge runs Home Assistant
  # there on the host network. Declared once so the server and every consumer agree.
  observability = {
    clickhouseHttpPort = 8124;
  };

  # Beszel's agent credential is the hub's public SSH key: public data, so plain
  # configuration rather than a secret.
  beszel = {
    hubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILETioYsZkau/yIH2LocWZP3d7z0nZAKIMb2POQNEhst";
  };

  bifrost = {
    aliases = {
      text = "shrublab-text";
      image = "shrublab-image";
      embedding = "voyage/voyage-4";
      fallback = "shrublab-fallback";
    };
  };

  s3 = {
    endpoint = "https://bef816e6776e8f13f5c03d2af70b036e.r2.cloudflarestorage.com";
    region = "auto";
    forcePathStyle = true;
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
    karakeep-pod = {
      dataDir = "/srv/data/karakeep";
      port = 3010;
      s3.bucket = "karakeep";
    };
    trek = {
      dataDir = "/srv/data/trek";
      port = 3020;
    };
    bifrost-gateway = {
      dataDir = "/srv/data/bifrost";
    };
  };
}
