{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.admin.cockpit;
  loopbackTls = cfg.loopbackTls;
  hasCockpitRoute = lib.hasAttrByPath [
    "applications"
    "admin"
    "policyServices"
    "cockpit-admin"
  ] config;
  cockpitRoute =
    if hasCockpitRoute then config.applications.admin.policyServices."cockpit-admin" else null;
  stateDir = loopbackTls.stateDir;
  publicCaCert = "/etc/cockpit/loopback-ca.crt";
  certName = "99-loopback";
  caCert = "${stateDir}/ca.crt";
  cert = "${stateDir}/cockpit.crt";
  key = "${stateDir}/cockpit.key";
in
{
  config = lib.mkIf (cfg.enable && loopbackTls.enable) {
    services.state-backups.services.cockpit-loopback-tls = {
      enable = true;
      mode = "live";
      paths = [ stateDir ];
    };

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0700 root root - -"
      "d /etc/cockpit 0755 root root - -"
      "d /etc/cockpit/ws-certs.d 0755 root root - -"
      "L+ /etc/cockpit/ws-certs.d/${certName}.cert - - - - ${cert}"
      "L+ /etc/cockpit/ws-certs.d/${certName}.key - - - - ${key}"
    ];

    systemd.services.cockpit-loopback-tls-material = {
      description = "Generate host-local CA and Cockpit loopback TLS certificate";
      wantedBy = [ "multi-user.target" ];
      before = [
        "cockpit.service"
        "caddy.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "cockpit-loopback-tls-material" ''
          set -euo pipefail
          umask 077

          state_dir="${stateDir}"
          ca_key="$state_dir/ca.key"
          ca_crt="$state_dir/ca.crt"
          leaf_key="$state_dir/cockpit.key"
          leaf_crt="$state_dir/cockpit.crt"
          leaf_csr="$state_dir/cockpit.csr"
          leaf_cfg="$state_dir/cockpit-openssl.cnf"

          install -d -m 0700 "$state_dir"

          if [ ! -s "$ca_key" ] || [ ! -s "$ca_crt" ]; then
            ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:4096 -nodes -sha256 -days 3650 \
              -subj "/CN=Shrublab Cockpit Loopback CA/" \
              -keyout "$ca_key" \
              -out "$ca_crt"
          fi

          cat > "$leaf_cfg" <<'EOF'
          [ req ]
          distinguished_name = dn
          prompt = no
          req_extensions = v3_req

          [ dn ]
          CN = ${loopbackTls.serverName}

          [ v3_req ]
          keyUsage = critical, digitalSignature, keyEncipherment
          extendedKeyUsage = serverAuth
          subjectAltName = @alt_names

          [ alt_names ]
          DNS.1 = ${loopbackTls.serverName}
          DNS.2 = localhost
          IP.1 = 127.0.0.1
          EOF

          if [ ! -s "$leaf_key" ] || [ ! -s "$leaf_crt" ]; then
            ${pkgs.openssl}/bin/openssl req -new -newkey rsa:2048 -nodes \
              -keyout "$leaf_key" \
              -out "$leaf_csr" \
              -config "$leaf_cfg"

            ${pkgs.openssl}/bin/openssl x509 -req -sha256 -days 825 \
              -in "$leaf_csr" \
              -CA "$ca_crt" \
              -CAkey "$ca_key" \
              -CAcreateserial \
              -out "$leaf_crt" \
              -extfile "$leaf_cfg" \
              -extensions v3_req
          fi

          rm -f "$leaf_csr"
          chmod 0400 "$ca_key" "$leaf_key"
          chmod 0444 "$ca_crt" "$leaf_crt"
          install -D -m 0444 "$ca_crt" "${publicCaCert}"
        '';
      };
    };

    systemd.services.cockpit = {
      requires = [ "cockpit-loopback-tls-material.service" ];
      after = [ "cockpit-loopback-tls-material.service" ];
    };

    systemd.services.caddy = lib.mkIf config.services.caddy.enable {
      wants = [ "cockpit-loopback-tls-material.service" ];
      after = [ "cockpit-loopback-tls-material.service" ];
    };

    assertions = [
      {
        assertion = config.services.cockpit.enable;
        message = "Cockpit loopback TLS material requires services.cockpit.enable=true.";
      }
      {
        assertion = cockpitRoute != null;
        message = "Cockpit loopback TLS material requires a resolved cockpit-admin policy route.";
      }
      {
        assertion = cockpitRoute.origin.scheme == "https";
        message = "Cockpit loopback TLS material requires cockpit-admin upstream scheme=https.";
      }
    ];
  };
}
