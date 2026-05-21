{ lib, ... }:
let
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFBqFsxbrn6SVOHXi4+LS5olKxEW8JlZ5V+irA18/586 saurabhj@arch"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMrzW7nXTeKqejlnIYmccciDJ4/PfjV6ek4Wvo7v86/a termix"
  ];
in
{
  users.mutableUsers = false;

  assertions = [
    {
      assertion = sshKeys != [ ];
      message = "shared users module requires at least one declarative SSH key";
    }
  ];

  users.users.dev = {
    isNormalUser = true;
    description = "Dev User";
    extraGroups = [
      "wheel"
    ];
    openssh.authorizedKeys.keys = sshKeys;
  };

  users.users.root.openssh.authorizedKeys.keys = sshKeys;
}
