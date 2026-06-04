{
  oci-melb-1 = {
    hostName = "oci-melb-1";
    # hostName = "161.33.71.82";
    sshUser = "dev";
    system = "aarch64-linux";
    remoteBuild = true;
    strictSubstituteOnly = false;
  };

  do-admin-1 = {
    hostName = "do-admin-1";
    # hostName = "139.59.199.81";
    sshUser = "dev";
    system = "x86_64-linux";
    remoteBuild = true;
    strictSubstituteOnly = true;
  };
}
