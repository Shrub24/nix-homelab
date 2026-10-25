# BookOrbit indexer plugins, vendored from a pinned upstream revision. BookOrbit loads them
# from its data path, so the module links these into `<APP_DATA_PATH>/plugins/indexers/<name>`.
# Only index.mjs is needed at runtime; verify.mjs and fixtures/ are development files.
{
  lib,
  fetchFromGitHub,
  stdenv,
}:
stdenv.mkDerivation {
  pname = "bookorbit-plugins";
  version = "2026-10-23";

  src = fetchFromGitHub {
    owner = "orbit-plugins";
    repo = "bookorbit-plugins-extra";
    # Upstream tags each plugin separately (myanonamouse-v2.1.2, libgen-v2.1.0), so the
    # revision is the pin: it carries both.
    rev = "138644f62198d1a1dc335b427f3d8d1b894ad954";
    hash = "sha256-7YvUqoONckwRLoVDWt1DIH2yjyonj0VwaliIUvIzazY=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    for plugin in libgen myanonamouse; do
      install -Dm644 indexers/$plugin/index.mjs $out/plugins/indexers/$plugin/index.mjs
    done
    runHook postInstall
  '';

  meta = {
    description = "BookOrbit indexer plugins (libgen, myanonamouse)";
    homepage = "https://github.com/orbit-plugins/bookorbit-plugins-extra";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
