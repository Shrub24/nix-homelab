# degoog's packaging mirrors upstream's `third-party/nix/package.nix`; only the
# dependency expression differs. Upstream generates `bun.nix` during evaluation,
# which makes every evaluation that forces the package an import-from-derivation;
# this repository carries the generated file and regenerates it from the pinned
# input through the registered package updater.
#
# The build sits behind a wrapper like GeoPulse's: nix-update reads a package's
# `version` position, so it has to be defined here rather than inside bun2nix's
# derivation builder.
{
  bun2nix,
  curl,
  curl-impersonate,
  diffutils,
  git,
  lib,
  nix,
  nixfmt,
  stdenv,
  src,
  symlinkJoin,
  writeShellApplication,
}:
let
  packageJson = builtins.fromJSON (builtins.readFile "${src}/package.json");

  app = bun2nix.writeBunApplication {
    inherit src;
    packageJson = "${src}/package.json";

    buildPhase = "bun run build";

    startScript = "bun run start";

    bunDeps = bun2nix.fetchBunDeps {
      bunNix = ./bun.nix;
    };

    runtimeInputs = [
      curl
      curl-impersonate
      git
    ];
  };

  # The producer refreshes flake inputs before it runs registered updaters, so
  # the source is resolved at run time: a path baked in here would regenerate
  # the expression from the previous lock.
  updater = writeShellApplication {
    name = "degoog-update";
    runtimeInputs = [
      bun2nix
      diffutils
      git
      nix
      nixfmt
    ];
    text = ''
      # `.#` resolves through the Git index, so the refreshed lock has to reach
      # it before anything evaluates the flake.
      git add -A

      src=$(nix eval --raw ".#packages.${stdenv.hostPlatform.system}.degoog.source")

      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT
      bun2nix --lock-file "$src/bun.lock" --output-file "$work/bun.nix"
      nixfmt "$work/bun.nix"

      if cmp -s "$work/bun.nix" pkgs/degoog/bun.nix; then
        echo "degoog-update: pkgs/degoog/bun.nix already matches $src"
        exit 0
      fi

      cp "$work/bun.nix" pkgs/degoog/bun.nix
      echo "degoog-update: regenerated pkgs/degoog/bun.nix from $src"
    '';
  };
in
symlinkJoin {
  pname = packageJson.name;
  version = packageJson.version;

  paths = [ app ];

  passthru = {
    # The updater resolves the current source through this attribute, so the
    # flake input stays the only place the revision is declared.
    source = src;
    updateScript = lib.getExe updater;
  };

  meta = {
    description = "Search engine aggregator with a comprehensive plugin/extension system";
    homepage = "https://github.com/degoog-org/degoog";
    license = lib.licenses.agpl3Only;
    maintainers = [ lib.maintainers.quadradical ];
    platforms = lib.platforms.linux;
    mainProgram = "degoog";
  };
}
