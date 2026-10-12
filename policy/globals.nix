{
  # The fleet Tailscale tailnet DNS suffix is written once, here. Canonical
  # host records set
  # `tailscale.tailnetSuffix = globals.tailnet.suffix` and derive their
  # `tailscale.fqdn` from it; the web policy composes host-backed FQDNs as
  # `"${hostId}.${globals.tailnet.suffix}"` in policy/web-services.nix, so a
  # renamed tailnet or changed host set can only disagree loudly, never drift.
  tailnet = {
    suffix = "tail0fe19b.ts.net";
  };

  # The host's stable, container-facing service address: a NixOS-owned dummy
  # interface that exists from boot, independent of every Podman network. A
  # container cannot reach a native host service over the bridge it sits on — the
  # host owns that bridge but is not a member of it — so every native service a
  # container must reach binds this address, and containers dial the stable name
  # below. The address is advertised nowhere: containers reach it through their own
  # bridge gateway, and neither the tailnet nor the provider network routes it.
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

  # Beszel's agent credential is the hub's SSH public key: every agent accepts
  # the hub's connection only against it, and the matching private half never
  # leaves the hub's data directory. Public data, delivered as plain
  # configuration — no sops, no per-host secret, no bootstrap gate.
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
