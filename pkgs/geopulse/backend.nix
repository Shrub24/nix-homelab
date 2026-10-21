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

  # Our PKCE patch is gone: the login no longer sends a code challenge, and the
  # Kanidm client opts out declaratively (`allowInsecureClientDisablePkce` in
  # policy/identity.json), so upstream sources build unmodified. The repeatable
  # migration that created the verifier column stays, because Flyway records an
  # applied repeatable migration by description and checksum: dropping the file
  # would leave that migration unresolved locally and fail validation. Its content
  # is unchanged from the one that ran, so it re-runs as a no-op.
  postPatch = ''
    cp ${./migrations/R__Add_oidc_session_code_verifier.sql} \
      backend/src/main/resources/db/migration/
  '';

  mvnJdk = jdk25;

  # brotli4j (a Quarkus transitive) selects its native jar through OS/arch
  # activated profiles, so one architecture's resolve omits the other's. The
  # fetch therefore resolves both Linux profiles into the one repository: the
  # fixed-output set is the union, and the same hash holds on every builder.
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
