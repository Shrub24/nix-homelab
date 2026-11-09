{
  config,
  self,
  lib,
  ...
}:
let
  sources = map (entry: entry.value.outPath) (
    builtins.genericClosure {
      startSet = [
        {
          key = toString self.outPath;
          value = self;
        }
      ];
      operator =
        entry:
        map (value: {
          key = toString value.outPath;
          inherit value;
        }) (builtins.attrValues (entry.value.inputs or { }));
    }
  );
in
{
  perSystem =
    { system, pkgs, ... }:
    lib.mkIf (system == "x86_64-linux") {
      checks.repository-contracts = pkgs.testers.runNixOSTest {
        name = "repository-contracts";
        nodes.machine = {
          virtualisation = {
            memorySize = 8192;
            cores = 4;
            diskSize = 32768;
            additionalPaths = sources ++ [
              pkgs.stdenv
              pkgs.stdenvNoCC
              pkgs.caddy
              pkgs.shellcheck-minimal
              pkgs.jdk25
            ];
          };
          environment.systemPackages = with pkgs; [
            bash
            git
            jujutsu
            nix
            just
            python3
            openssh
            jq
            yq-go
            openssl
            curl
            gnutar
            gzip
            coreutils
            gnugrep
            gnused
            gawk
          ];
          nix.settings = {
            experimental-features = [
              "nix-command"
              "flakes"
            ];
            allow-import-from-derivation = false;
            substituters = lib.mkForce [ ];
            builders = lib.mkForce "";
            max-jobs = 2;
            connect-timeout = 1;
          };
        };
        # The suite mutates disposable source trees and realises small fixture helpers.
        testScript = ''
          from datetime import timedelta
          start_all()
          machine.wait_for_unit("multi-user.target")
          machine.succeed("cp -r --no-preserve=ownership ${self.outPath} /root/repository && chmod -R u+w /root/repository")
          machine.succeed("cd /root/repository && git init -q && git add -A && jj git init --colocate && JJ_USER=fixture JJ_EMAIL=fixture@example.invalid jj status")
          try:
              machine.succeed("cd /root/repository && bash scripts/run-repository-contracts.sh > /tmp/contracts.log 2>&1", timeout=timedelta(hours=1))
          finally:
              print(machine.execute("cat /tmp/contracts.log")[1])
        '';
      };
    };
}
