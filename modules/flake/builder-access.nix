# Builder access: nixbuild.net SSH trust only. Substituter policy stays in the
# base aspect; selection is enablement, and the SSH trust is nested in the
# publication, so there is no private leaf.
{ ... }:
{
  flake.modules.nixos.builder-access = {
    programs.ssh.knownHosts.nixbuild = {
      hostNames = [ "eu.nixbuild.net" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM";
    };

    programs.ssh.extraConfig = ''
      Host eu.nixbuild.net
      IPQoS throughput
      PubkeyAcceptedKeyTypes ssh-ed25519
      ServerAliveInterval 60
      TCPKeepAlive no
      Compression no
      ControlMaster auto
      ControlPath /tmp/nixbuild-%r@%h:%p
      ControlPersist 10m
    '';
  };
}
