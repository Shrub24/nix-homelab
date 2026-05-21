{
  description = "Modular NixOS fleet infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";
    niks3.url = "github:Mic92/niks3";
    niks3.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      disko,
      sops-nix,
      deploy-rs,
      niks3,
      ...
    }:
    let
      devShellSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      mkDevShell =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.mkShell {
          packages = with pkgs; [
            just
            git
            jq
            yq
            opentofu
            sops
            age
            nixos-anywhere
            deploy-rs.packages.${system}.default
            nix-output-monitor
            nixfmt
            statix
            ssh-to-age
            self.packages.${system}.notification-daemon
            self.packages.${system}.notify
          ];
          shellHook = ''
            if [ -f /tmp/notification-daemon.json ]; then
              NOTIFICATION_DAEMON_CONFIG=/tmp/notification-daemon.json notification-daemon &
              DAEMON_PID=$!
              trap "kill $DAEMON_PID 2>/dev/null; echo 'notification-daemon stopped'" EXIT TERM INT
              echo "notification-daemon started (PID: $DAEMON_PID)"
            fi
          '';
        };

      deployConfig = import ./lib/deploy {
        inherit self nixpkgs deploy-rs;
        hosts = import ./lib/deploy/hosts.nix;
      };

    in
    {
      devShells = nixpkgs.lib.genAttrs devShellSystems (system: {
        default = mkDevShell system;
      });

      packages = nixpkgs.lib.genAttrs devShellSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          deploy-rs = deploy-rs.packages.${system}.default;
          notification-daemon = pkgs.callPackage ./pkgs/notification-daemon { };
          notify = pkgs.callPackage ./pkgs/notify { };
        }
      );

      formatter = nixpkgs.lib.genAttrs devShellSystems (
        system: (import nixpkgs { inherit system; }).nixfmt
      );

      nixosConfigurations.oci-melb-1 = nixpkgs.lib.nixosSystem {
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          niks3.nixosModules.niks3
          niks3.nixosModules.niks3-auto-upload
          ./hosts/oci-melb-1/default.nix
        ];
        specialArgs = { inherit self inputs; };
      };

      nixosConfigurations.do-admin-1 = nixpkgs.lib.nixosSystem {
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          niks3.nixosModules.niks3-auto-upload
          ./hosts/do-admin-1/default.nix
        ];
        specialArgs = { inherit self inputs; };
      };

      deploy = deployConfig.deploy;
      checks = deployConfig.checks;
    };
}
