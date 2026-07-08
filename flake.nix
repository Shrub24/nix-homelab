{
  description = "Modular NixOS fleet infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
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
          packages =
            with pkgs;
            [
              just
              git
              jq
              yq
              opentofu
              prettier
              shfmt
              taplo
              treefmt
              sops
              age
              nixos-anywhere
              nix-output-monitor
              nixfmt
              ruff
              statix
              ssh-to-age
              lefthook
              self.packages.${system}.notification-daemon
              self.packages.${system}.notify
              self.packages.${system}.niks3
              self.packages.${system}.nix-path-filter
            ]
            ++ [ pkgs.deploy-rs ];
          shellHook = ''
            if [ -f /tmp/notification-daemon.json ]; then
              NOTIFICATION_DAEMON_CONFIG=/tmp/notification-daemon.json notification-daemon &
              DAEMON_PID=$!
              trap "kill $DAEMON_PID 2>/dev/null; echo 'notification-daemon stopped'" EXIT TERM INT
              echo "notification-daemon started (PID: $DAEMON_PID)"
            fi
          '';
        };

      ociImages = import ./policy/oci-images.nix;

      deployConfig = import ./lib/deploy {
        inherit self nixpkgs deploy-rs;
        hosts = import ./lib/deploy/hosts.nix;
      };

    in
    {
      devShells = nixpkgs.lib.genAttrs devShellSystems (system: {
        default = mkDevShell system;
      });

      packages = nixpkgs.lib.genAttrs devShellSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          deploy-rs = pkgs.deploy-rs;
          niks3 = niks3.packages.${system}.niks3;
          nix-path-filter = pkgs.callPackage ./pkgs/nix-path-filter { };
          notification-daemon = pkgs.callPackage ./pkgs/notification-daemon { };
          notify = pkgs.callPackage ./pkgs/notify { };
          host-do-admin-1 = deployConfig.deploy.nodes.do-admin-1.profiles.system.path;
          host-oci-melb-1 = deployConfig.deploy.nodes.oci-melb-1.profiles.system.path;
        }
      );

      deployHosts = import ./lib/deploy/hosts.nix;

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
        specialArgs = {
          inherit
            self
            inputs
            ociImages
            ;
        };
      };

      nixosConfigurations.do-admin-1 = nixpkgs.lib.nixosSystem {
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          niks3.nixosModules.niks3-auto-upload
          ./hosts/do-admin-1/default.nix
        ];
        specialArgs = {
          inherit
            self
            inputs
            ociImages
            ;
        };
      };

      deploy = deployConfig.deploy;
      checks = deployConfig.checks;
    };
}
