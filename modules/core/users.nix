{
  lib,
  pkgs,
  ...
}:
let
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFBqFsxbrn6SVOHXi4+LS5olKxEW8JlZ5V+irA18/586 saurabhj@arch"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMrzW7nXTeKqejlnIYmccciDJ4/PfjV6ek4Wvo7v86/a termix"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBsHnolkmLVudDN3HKQ/Q4Xw2ZqDVjax177hbi15jqRW la-admin-1-dev@shrublab"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINRh71N504a6X1OkZ6XxhJrllHiEEWC/4o5s3+RtPuI8 home-forge-dev@shrublab"
  ];
in
{
  users.mutableUsers = false;

  users.users.dev = {
    isNormalUser = true;
    description = "Dev User";
    extraGroups = [
      "wheel"
    ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = sshKeys;
  };

  users.users.root = {
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys = sshKeys;
  };

  systemd.tmpfiles.settings."user-homes" = {
    "/home/dev/.config".d = {
      user = "dev";
      group = "users";
      mode = "0755";
    };
    "/home/dev/.cache".d = {
      user = "dev";
      group = "users";
      mode = "0755";
    };
    "/home/dev/.local".d = {
      user = "dev";
      group = "users";
      mode = "0755";
    };
    "/home/dev/.local/share".d = {
      user = "dev";
      group = "users";
      mode = "0755";
    };
    "/home/dev/.local/state".d = {
      user = "dev";
      group = "users";
      mode = "0755";
    };
  };
}
