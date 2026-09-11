# nixbuild.net SSH trust (raw private leaf, imported by the builder-access
# aspect). Selection is enablement: the aspect's import is the enablement, so
# the fleet.nixbuild-ssh.enable option is retired (OPS-7). Substituter policy
# stays in the base aspect; this leaf only owns SSH known-hosts and host
# configuration.
{ ... }:
{
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
}
