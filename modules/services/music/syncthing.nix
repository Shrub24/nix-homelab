{
  lib,
  config,
  ...
}:
let
  cfg = config.services.syncthing;

  folderSettings = lib.mapAttrs (
    _name: folder:
    builtins.removeAttrs folder [
      "ensureDir"
      "ensureMarker"
      "ensureAcl"
      "dirMode"
      "dirUser"
      "dirGroup"
    ]
  ) cfg.folderTargets;

  folderTmpfiles = lib.flatten (
    lib.mapAttrsToList (
      _name: folder:
      lib.optionals folder.ensureDir [
        "d ${folder.path} ${folder.dirMode} ${folder.dirUser} ${folder.dirGroup} - -"
      ]
      ++ lib.optionals folder.ensureAcl [
        "a+ ${folder.path} - - - - user:syncthing:rwx"
        "a+ ${folder.path} - - - - default:user:syncthing:rwx"
      ]
      ++ lib.optionals folder.ensureMarker [
        "f ${folder.path}/.stfolder 0664 syncthing syncthing - -"
      ]
    ) cfg.folderTargets
  );
in
{
  options.services.syncthing.deviceTargets = lib.mkOption {
    type = lib.types.attrsOf lib.types.attrs;
    default = { };
    description = "Device definitions to merge into services.syncthing.settings.devices.";
  };

  options.services.syncthing.folderTargets = lib.mkOption {
    default = { };
    description = "Folder definitions to merge into services.syncthing.settings.folders.";
    type = lib.types.attrsOf (
      lib.types.submodule {
        freeformType = lib.types.attrs;
        options = {
          path = lib.mkOption {
            type = lib.types.str;
            description = "Folder path for this Syncthing target.";
          };

          ensureDir = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether tmpfiles should create the folder path.";
          };

          ensureMarker = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether tmpfiles should create .stfolder for the folder path.";
          };

          ensureAcl = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether tmpfiles should add Syncthing ACL entries to folder path.";
          };

          dirMode = lib.mkOption {
            type = lib.types.str;
            default = "2775";
            description = "Directory mode when ensureDir=true.";
          };

          dirUser = lib.mkOption {
            type = lib.types.str;
            default = "root";
            description = "Directory owner when ensureDir=true.";
          };

          dirGroup = lib.mkOption {
            type = lib.types.str;
            default = "media";
            description = "Directory group when ensureDir=true.";
          };
        };
      }
    );
  };

  config = {
    services.syncthing = {
      enable = true;
      dataDir = lib.mkDefault "/srv/data/syncthing";
      configDir = lib.mkDefault "/srv/data/syncthing/config";
      guiAddress = lib.mkDefault "0.0.0.0:8384";
      openDefaultPorts = false;
      overrideDevices = lib.mkDefault true;
      overrideFolders = lib.mkDefault true;
      settings.devices = cfg.deviceTargets;
      settings.folders = folderSettings;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 syncthing syncthing - -"
      "d ${cfg.configDir} 0750 syncthing syncthing - -"
    ]
    ++ folderTmpfiles;
  };
}
