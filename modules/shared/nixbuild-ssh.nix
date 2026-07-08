{ config, lib, ... }:
{
  options.fleet.nixbuild-ssh.enable = lib.mkEnableOption "nixbuild.net SSH known_hosts and host config";

  config = lib.mkIf (config.fleet.nixbuild-ssh.enable) {
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
