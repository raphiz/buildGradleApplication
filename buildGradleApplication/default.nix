{
  lib,
  stdenvNoCC,
  runCommand,
  writeShellScript,
  python3,
  gradle,
  jdk,
  makeWrapper,
  fetchArtifact,
  mkM2Repository,
}: {
  pname,
  version,
  src,
  meta,
  buildInputs ? [],
  nativeBuildInputs ? [],
  repositories ? ["https://plugins.gradle.org/m2/" "https://repo1.maven.org/maven2/"],
  verificationFile ? "gradle/verification-metadata.xml",
  buildTask ? ":installDist",
  installLocaltion ? "build/install/*/",
}: let
  m2Repository = mkM2Repository {
    inherit pname version src repositories verificationFile;
  };

  # Prepare a script that will replace that jars with references into the NIX store.
  linkScript = writeShellScript "link-to-jars" ''
    declare -A depsByName
    ${
      lib.concatMapStringsSep "\n"
      (dep: "depsByName[\"${dep.name}\"]=\"${builtins.toString dep.jar}\"")
      (builtins.filter (dep: (lib.strings.hasSuffix ".jar" dep.name && !lib.strings.hasSuffix "-javadoc.jar" dep.name && !lib.strings.hasSuffix "-sources.jar" dep.name)) m2Repository.dependencies)
    }

    for jar in "$1"/*.jar; do
      dep=''${depsByName[$(basename "$jar")]}
      if [[ -n "$dep" ]]; then
          echo "Replacing $jar with nix store reference $dep"
          rm "$jar"
          ln -s "$dep" "$jar"
      fi
    done
  '';

  package = stdenvNoCC.mkDerivation {
    inherit pname version src meta buildInputs;
    nativeBuildInputs = [gradle jdk makeWrapper] ++ nativeBuildInputs;
    buildPhase = ''
      runHook preBuild

      # Setup maven repo
      export MAVEN_SOURCE_REPOSITORY=${m2Repository.m2Repository}
      echo "Using maven repository at: $MAVEN_SOURCE_REPOSITORY"

      # create temporary gradle home
      export GRADLE_USER_HOME=$(mktemp -d)

      # Export application version to the build
      export APP_VERSION=${version}

      # built the dam thing!
      gradle --offline --no-daemon --no-watch-fs --no-configuration-cache --no-build-cache --console=plain --no-scan --init-script ${./init.gradle.kts} ${buildTask}

      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      pushd ${installLocaltion}

      mkdir -p $out/lib/
      mv lib/*.jar $out/lib/
      ${linkScript} $out/lib/

      if [ -d agent-libs/ ]; then
          mkdir -p $out/agent-libs/
          mv agent-libs/*.jar $out/agent-libs/
          ${linkScript} $out/agent-libs/
      fi

      mkdir -p $out/bin

      cp $(ls bin/* | grep -v ".bat") $out/bin/${pname}

      wrapProgram $out/bin/${pname} \
         --set-default JAVA_HOME "${jdk.home}"

      popd
      runHook postInstall
    '';
  };
in
  package
