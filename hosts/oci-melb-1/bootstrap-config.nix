{
  hostName = "oci-melb-1";
  bootstrapUser = "ubuntu";
  bootstrapDisk = "/dev/sda";
  mediaDisk = "/dev/sdb";
  rootPartitionSize = "20G";
  dataRoot = "/srv/data";
  mediaRoot = "/srv/media";
  flake = "path:.#oci-melb-1";
}
