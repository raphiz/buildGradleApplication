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
  dependencyFilter ? depSpec: let
    # Lots of libraries have references to metadata jars that are not present on maven central, for example:
    # - kasechange-metadata-1.4.1.jar (net.pearx.kasechange:kasechange)
    # - kotlin-result-metadata-2.0.0.jar (com.michael-bull.kotlin-result:kotlin-result)
    # - kotlinx-serialization-core-metadata-1.7.0.jar (org.jetbrains.kotlinx:kotlinx-serialization-core)
    # These will make the nix build fail because we cannot fetch them. They are usually not needed for the build, so it's relatively safe to ignore them by default.
    # However, it MIGHT be the case that some -metadata.jars ARE actually required but I have not yet found one. If you do, please open an issue!
    isUnpublishedMetadataJar =
      depSpec.name == "${depSpec.component.name}-metadata-${depSpec.component.version}.jar";
  in
    if isUnpublishedMetadataJar
    then builtins.trace "Ignoring potentially unpublished metadata jar: ${depSpec.name}" false
    else true,
  repositories ? ["https://plugins.gradle.org/m2/" "https://repo1.maven.org/maven2/"],
  verificationFile ? "gradle/verification-metadata.xml",
  buildTask ? ":installDist",
  installLocation ? "build/install/*/",
}: let
  m2Repository = mkM2Repository {
    inherit pname version src dependencyFilter repositories verificationFile;
  };

  # Prepare a script that will replace that jars with references into the NIX store.
  linkScript = writeShellScript "link-to-jars" ''
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

  package = stdenvNoCC.mkDerivation {
    inherit pname version src buildInputs env;
    meta =
      {
        # set default for meta.mainProgram here to gain compatibility with:
        # `lib.getExe`, `nix run`, `nix bundle`, etc.
        mainProgram = pname;
      }
      // meta;

    passthru = {
      inherit jdk gradle updateVerificationMetadata;
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

    installPhase = ''
      runHook preInstall
      directories=( $(shopt -s nullglob; echo ${installLocation}) )

      if [ ''${#directories[@]} -eq 0 ]; then
        echo "Error: The built gradle application could not be found at ${installLocation}.
        Most likely the option 'installLocation' is not set correctly.
        The default value for 'installLocation' only works when the application plugin is applied on the root project itself.
        If you applied it on a sub-project, adapt 'installLocation' accordingly, for example 'installLocation = \"path/to/sub-project/build/install/*/\"'." 1>&2;
        exit 1
      elif [ ''${#directories[@]} -gt 1 ]; then
          echo "Error: The built gradle application could not be found at ${installLocation} because there are multiple matching directories (''${directories[@]})
          Please adapt 'installLocation' to be more specific, for example by removing any wildcards." 1>&2;
          exit 1
      fi

      pushd ${installLocation}

      mkdir -p $out/lib/
      mv lib/*.jar $out/lib/
      echo ${linkScript} $out/lib/
      ${linkScript} $out/lib/

      if [ -d agent-libs/ ]; then
          mkdir -p $out/agent-libs/
          mv agent-libs/*.jar $out/agent-libs/
          ${linkScript} $out/agent-libs/
      fi

      mkdir -p $out/bin

      cp $(ls bin/* | grep -v ".bat") $out/bin/${pname}

      popd
      runHook postInstall
    '';

    dontWrapGApps = true;
    postFixup = ''
      wrapProgram $out/bin/${pname} \
        --set-default JAVA_HOME "${jdk.home}" \
        ''${gappsWrapperArgs[@]}
    '';
  };
in
  package
