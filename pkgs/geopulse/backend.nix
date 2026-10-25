{
  lib,
  maven,
  jdk25,
  src,
  version,
}:
maven.buildMavenPackage {
  pname = "geopulse-backend";
  inherit version src;

  # Sources build unmodified: the client opts out of PKCE in policy/identity.json. The
  # repeatable migration stays because Flyway records it by checksum.
  postPatch = ''
    # The destination name is explicit: `cp` from a store path would keep the
    # hash prefix Nix adds, and Flyway then rejects the file as non-conforming.
    install -Dm644 ${./migrations/R__Add_oidc_session_code_verifier.sql} \
      backend/src/main/resources/db/migration/R__Add_oidc_session_code_verifier.sql
  '';

  mvnJdk = jdk25;

  # brotli4j selects its native jar by OS/arch profile, so the fetch resolves both Linux
  # profiles into one repository and the hash holds on every builder.
  mvnFetchExtraArgs = {
    postBuild = ''
      for arch in amd64 aarch64; do
        MAVEN_OPTS="-Dos.arch=$arch -Dos.name=linux" mvn $MAVEN_EXTRA_ARGS package \
          -Dmaven.repo.local=$out/.m2 -pl backend -Dquarkus.profile=prod -DskipTests
      done
    '';
  };
  mvnHash = "sha256-WucDIjE95ZuioTcLodG6IuI1O55WKE116jjv42YGM1w=";
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
}
