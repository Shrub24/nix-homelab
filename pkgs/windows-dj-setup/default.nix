{
  lib,
  stdenv,
  fetchurl,
  p7zip,
  writeShellApplication,
  python3,
  cacert,
  nix,
}:
let
  winfspSrc = fetchurl {
    url = "https://github.com/winfsp/winfsp/releases/download/v2.2/winfsp-2.2.26323.msi";
    hash = "sha256-Ns4B+e7bvmhCt/tL7cedfU9xmD6KzraHe0agezMcfhk=";
  };
  # MinGW build: the 26.2.x MSVC artifact regressed upstream and ships no
  # OpenGL DLLs; upstream's own workaround is the MinGW x64 build.
  mesaSrc = fetchurl {
    url = "https://github.com/pal1000/mesa-dist-win/releases/download/26.3.1/mesa3d-26.3.1-release-mingw.7z";
    hash = "sha256-x9jDn0OiSKBt67VSPTn6y1jQ4CngM07Um/0jJz5ICc8=";
  };

  updater = writeShellApplication {
    name = "windows-dj-setup-update";
    runtimeInputs = [
      python3
      cacert
      nix
    ];
    text = ''
      export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
      exec python3 ${./update.py} "$@"
    '';
  };
in
stdenv.mkDerivation {
  pname = "windows-dj-setup";
  # WinFsp carries the version: it is the primary pin and the pair's setup order,
  # and its release is what `checkUpdate` reports. Mesa is refreshed with it.
  version = "2.2.26323";
  dontUnpack = true;
  nativeBuildInputs = [ p7zip ];

  installPhase = ''
    mkdir -p $out
    cp ${winfspSrc} $out/winfsp.msi

    mkdir -p /tmp/mesa
    7z x ${mesaSrc} -o/tmp/mesa > /dev/null
    cp /tmp/mesa/x64/opengl32.dll $out/opengl32sw.dll
    cp /tmp/mesa/x64/libgallium_wgl.dll $out/libgallium_wgl.dll
    cp /tmp/mesa/x64/libEGL.dll $out/libEGL.dll

    cp ${./setup.ps1} $out/setup.ps1
    cat > $out/README.txt <<'EOF'
    windows-dj setup share (read-only, mounted as S:\):
      winfsp.msi       — WinFsp installer (required before virtiofs services)
      opengl32sw.dll   — Mesa software GL fallback for Engine DJ on virtio-gpu
      setup.ps1        - one-shot setup: installs WinFsp, registers VirtIO-FS services (M: music, S: setup), removes the legacy L: Engine-library share, disables sleep, installs Mesa fallback
    Run once as Administrator:  powershell -ExecutionPolicy Bypass -File S:\setup.ps1
    EOF
  '';

  passthru = {
    # Release check for `--check`: both pins live in one derivation, so standard discovery
    # cannot apply.
    checkUpdate = writeShellApplication {
      name = "windows-dj-setup-check-update";
      runtimeInputs = [
        python3
        cacert
      ];
      text = ''
        export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
        exec python3 ${./update.py} --check
      '';
    };

    # Run by the batch through nix-update's update-script path. It refreshes both
    # coupled pins and writes only pkgs/windows-dj-setup/.
    updateScript = lib.getExe updater;
  };

  meta = {
    description = "Windows DJ setup media — WinFsp, Mesa fallback, and setup script for Engine DJ VM";
    platforms = lib.platforms.all;
  };
}
