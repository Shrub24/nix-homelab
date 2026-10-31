{
  lib,
  maven,
  jdk25,
  src,
  version,
}:
let
  # `mvnHash` pins a fixed-output dependency repository, and a fixed-output
  # derivation is identified by its hash alone: a Maven bump leaves the frozen
  # repository "already fetched" while the offline build resolves the new Maven's
  # default lifecycle plugins from it (3.10.0 wants maven-resources-plugin 3.5.0,
  # 3.9.x an older one). The hash is only valid for the Maven that produced it, so
  # bind the two. Set this value before re-running nix-update: the regeneration
  # evaluates the package to reach the fetch derivation.
  mvnToolchain = "3.10.0";

  package = maven.buildMavenPackage {
    pname = "geopulse-backend";
    inherit version src;

    # Sources build unmodified: the client opts out of PKCE in policy/identity.nix. The
    # repeatable migration stays because Flyway records it by checksum.
    postPatch = ''
      # The destination name is explicit: `cp` from a store path would keep the
      # hash prefix Nix adds, and Flyway then rejects the file as non-conforming.
      install -Dm644 ${./migrations/R__Add_oidc_session_code_verifier.sql} \
        backend/src/main/resources/db/migration/R__Add_oidc_session_code_verifier.sql
    '';

    mvnJdk = jdk25;

    # brotli4j selects its native jar by OS/arch-activated profile, so one build
    # carries one architecture while this one hash serves every builder: the fetch
    # runs the project's own build once per architecture. The spoofed `os.arch` also
    # reaches JLine, whose FFM terminal provider then selects the linker of a
    # platform the JVM is not running on and aborts before Maven reads a pom; the
    # stream provider leaves the terminal alone and the profile selection spoofed.
    mvnFetchExtraArgs = {
      postBuild = ''
        for arch in amd64 aarch64; do
          MAVEN_OPTS="-Dos.arch=$arch -Dos.name=linux -Dorg.jline.terminal.provider=stream" \
            mvn $MAVEN_EXTRA_ARGS package -Dmaven.repo.local=$out/.m2 -pl backend \
              -Dquarkus.profile=prod -DskipTests
        done
      '';
    };
    mvnHash = "sha256-cXHz+vsVawgYeHPlC+aGWcuaSbDwTXwEVbRJNKtm+hY=";
    mvnParameters = "-pl backend -Dquarkus.profile=prod";
    doCheck = false;

    # Quarkus fast-jar: quarkus-run.jar resolves lib/, app/ and quarkus/ relative
    # to itself, so the directory is installed whole.
    installPhase = ''
      runHook preInstall
      mkdir -p $out/quarkus-app
      cp -r backend/target/quarkus-app/. $out/quarkus-app/
      install -Dm644 LICENSE $out/share/licenses/geopulse/LICENSE
      runHook postInstall
    '';

    meta = {
      description = "GeoPulse backend (Quarkus fast-jar)";
      license = lib.licenses.bsl11;
      platforms = lib.platforms.linux;
    };
  };
in
if maven.version == mvnToolchain then
  package
else
  throw ''
    geopulse-backend: mvnHash was generated with Maven ${mvnToolchain}, but nixpkgs now
    provides Maven ${maven.version}. Set mvnToolchain to "${maven.version}" in
    pkgs/geopulse/backend.nix, then regenerate the dependency hash:

      nix-update --flake --version=skip --no-src geopulse-backend
  ''
