{
  pkgs,
  lib,
  stdenvNoCC,
  writeShellScript,
  makeWrapper,
  mkM2Repository,
  updateVerificationMetadata,
}: {
  pname,
  version,
  src,
  meta ? {},
  env ? {},
  jdk ? pkgs.jdk,
  gradle ? pkgs.gradle,
  buildInputs ? [],
  nativeBuildInputs ? [],
  dependencyFilter ? depSpec: true,
  repositories ? ["https://plugins.gradle.org/m2/" "https://repo1.maven.org/maven2/"],
  verificationFile ? "gradle/verification-metadata.xml",
  buildTask ? ":installDist",
  installPhase ? null,
  ...
}@params: let
  m2Repository = mkM2Repository {
    inherit pname version src dependencyFilter repositories verificationFile;
  };

in 
  stdenvNoCC.mkDerivation ({
    inherit pname version src buildInputs env;
    meta =
      {
        # set default for meta.mainProgram here to gain compatibility with:
        # `lib.getExe`, `nix run`, `nix bundle`, etc.
        mainProgram = pname;
      }
      // meta;

    passthru = {
      inherit jdk gradle;
      updateVerificationMetadata = updateVerificationMetadata.override {inherit gradle;};
    };

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
      gradle --offline --no-daemon --no-watch-fs -Dorg.gradle.unsafe.isolated-projects=false --no-configuration-cache --no-build-cache -Dorg.gradle.console=plain --no-scan -Porg.gradle.java.installations.auto-download=false --init-script ${./init.gradle.kts} ${buildTask}

      runHook postBuild
    '';

    linkToJars = writeShellScript "link-to-jars" ''
    declare -A fileByName
    declare -A hashByName
    ${
      lib.concatMapStringsSep "\n"
      (dep: "fileByName[\"${dep.name}\"]=\"${builtins.toString dep.jar}\"\nhashByName[\"${dep.name}\"]=\"${builtins.toString dep.hash}\"")
      (builtins.filter (dep: (lib.strings.hasSuffix ".jar" dep.name && !lib.strings.hasSuffix "-javadoc.jar" dep.name && !lib.strings.hasSuffix "-sources.jar" dep.name)) m2Repository.dependencies)
    }

    for jar in "$1"/*.jar; do
      dep=''${fileByName[$(basename "$jar")]}
      if [[ -n "$dep" ]]; then
          jarHash=$(sha256sum "$jar" | cut -c -64)
          sriHash=''${hashByName[$(basename "$jar")]}
          if [[ $sriHash == sha256-* ]]; then
            referenceHash="$(echo ''${sriHash#sha256-} | base64 -d | ${pkgs.hexdump}/bin/hexdump -v -e '/1 "%02x"')"
          else
            referenceHash=$(sha256sum "$dep" | cut -c -64)
          fi

          if [[ "$referenceHash" == "$jarHash" ]]; then
            echo "Replacing $jar with nix store reference $dep"
            rm "$jar"
            ln -s "$dep" "$jar"
          else
            echo "Hash of $jar differs from expected store reference $dep"
          fi
      else
        echo "No linking candidate found for $jar"
      fi
    done
  '';

    installPhase = ''
      # Default build phase for buildGradleArtifact
      echo 'buildGradleArtifact should specify an installPhase'
      echo 'You can call $linkToJars} in order to replace jar files inside the parameter folder'
      echo 'with links to nix store'
      exit 1
    '';
  } // params)
