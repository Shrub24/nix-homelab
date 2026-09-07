{
  lib,
  stdenv,
  fetchurl,
  p7zip,
}:
let
  winfspSrc = fetchurl {
    url = "https://github.com/winfsp/winfsp/releases/download/v2.1/winfsp-2.1.25156.msi";
    hash = "sha256-Bzpw4A93Qj40vtmLhuYA3vkzk7pYIiBPrFeikyTbn3o=";
  };
  mesaSrc = fetchurl {
    url = "https://github.com/pal1000/mesa-dist-win/releases/download/26.2.0/mesa3d-26.2.0-release-msvc.7z";
    hash = "sha256-3LJxnvNG2rW2Cfyxk6XxPPxLBQLj9N4a1D00lHdAL0c=";
  };
in
stdenv.mkDerivation {
  pname = "windows-dj-setup";
  version = "1.0";
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
      setup.ps1        - one-shot setup: installs WinFsp, registers VirtIO-FS services (M: music, L: Engine library, S: setup), disables sleep, creates the Engine library link, installs Mesa fallback
    Run once as Administrator:  powershell -ExecutionPolicy Bypass -File S:\setup.ps1
    EOF
  '';

  meta = with lib; {
    description = "Windows DJ setup media — WinFsp, Mesa fallback, and setup script for Engine DJ VM";
    platforms = platforms.all;
  };
}
