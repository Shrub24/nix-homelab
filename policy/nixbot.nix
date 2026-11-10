{
  github = {
    appId = 5492536;
    oauthId = "Iv23li2ikULpKoDTZbEF";
    admins = [ "github:Shrub24" ];
  };
  builderPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMPLCsAPacFhNUF3sKzN4zghkN9lfV9a4FRD0a7ayGd0 nixbot-builder";
  # Repo policy: this repository reviews dependency updates, it does not land
  # them. A repository that wants them landed sets this and gets auto-merge.
  updateAutoMerge = false;
}
