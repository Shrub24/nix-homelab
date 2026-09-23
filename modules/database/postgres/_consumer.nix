# PostgreSQL consumer contract.
#
# Declaration-only fragment: the options a consumer feature writes
# (`services.postgres.consumers.<name>`) and the host facts the provider
# consumes (`instances.<name>`, `localEndpoint`). No configuration here.
#
# Import this where a feature registers a consumer; the postgres aspect
# imports it too, so both sides share one declaration surface.
{ lib, ... }:
{
  options.services.postgres = {
    enable = lib.mkEnableOption "the shared PostgreSQL mechanism" // {
      default = false;
    };

    instances = lib.mkOption {
      default = { };
      description = ''
        PostgreSQL clusters this host runs, keyed by the instance name the
        internal contract refers to. Port and data directory are host facts.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            port = lib.mkOption {
              type = lib.types.port;
              description = "TCP port this instance listens on.";
            };
            dataDir = lib.mkOption {
              type = lib.types.str;
              description = "Data directory on the shared service-state mount.";
            };
          };
        }
      );
    };

    localEndpoint = lib.mkOption {
      readOnly = true;
      type = lib.types.nullOr (
        lib.types.submodule {
          options.port = lib.mkOption {
            type = lib.types.port;
            description = "Port of this host's cluster.";
          };
        }
      );
      description = ''
        This host's cluster endpoint when it declares one, so a co-located
        consumer reaches the database directly instead of over the tailnet.
      '';
    };

    consumers = lib.mkOption {
      default = { };
      description = ''
        Databases and roles registered against this host's cluster, keyed by
        consumer name. A consumer registers itself from its own module; the
        mechanism owns provisioning.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            database = lib.mkOption {
              type = lib.types.str;
              description = "Database the consumer owns.";
            };
            role = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Login role owning the database; defaults to the consumer name.";
            };
            auth = lib.mkOption {
              type = lib.types.enum [
                "peer"
                "scram"
              ];
              default = "peer";
              description = ''
                `peer` authenticates a host-local consumer over the Unix socket
                and needs no credential; `scram` provisions a password role
                reachable from the consumer's `allowedCIDRs`.
              '';
            };
            password = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.submodule {
                  options = {
                    file = lib.mkOption {
                      type = lib.types.path;
                      description = "SOPS-encrypted file holding this role's password.";
                    };
                    key = lib.mkOption {
                      type = lib.types.str;
                      description = "Key path of this role's password within that file.";
                    };
                  };
                }
              );
              default = null;
              description = ''
                The role's credential, owned by the consumer that uses it. The
                same file and key are read here to provision the role and by the
                consumer to authenticate, so the value has one authoritative
                source.
              '';
            };
            allowedCIDRs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "100.64.0.0/10"
                "fd7a:115c:a1e0::/48"
              ];
              description = "CIDR ranges allowed to authenticate as this role with password authentication.";
            };
            extensions = lib.mkOption {
              type = lib.types.functionTo (lib.types.listOf lib.types.package);
              default = _: [ ];
              example = lib.literalExpression "ps: [ ps.pgvector ]";
              description = ''
                Server-side extension packages this consumer needs, in the shape
                `services.postgresql.extensions` uses: a function of the
                instance's own extension set, so the package always matches the
                server version. The matching SQL belongs in `setupSQL`.
              '';
            };
            setupSQL = lib.mkOption {
              type = lib.types.lines;
              default = "";
              example = lib.literalExpression ''"CREATE EXTENSION IF NOT EXISTS vector;"'';
              description = ''
                SQL run in this consumer's database on every cluster start, as
                the `postgres` superuser. Must be idempotent.
              '';
            };
          };
        }
      );
    };
  };
}
