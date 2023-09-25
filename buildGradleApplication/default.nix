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
  # Read all build and runtime dependencies from the verification-metadata XML
  depSpecs = builtins.fromJSON (builtins.readFile (
    runCommand "depSpecs" {buildInputs = [python3];}
    "python ${./parse.py} ${src}/${verificationFile} ${builtins.toString (builtins.map lib.escapeShellArg repositories)}> $out"
  ));
  mkDep = depSpec: {
    inherit (depSpec) urls path name hash component;
    jar = fetchArtifact {
      inherit (depSpec) urls hash name;
    };
  };
  deps = builtins.map (depSpec: mkDep depSpec) depSpecs;

  # Build maven repository that contains all build dependencies

  # write a dedicated script for the m2 repository creation. Otherwise, the m2Repository derivation might crash with 'Argument list too long'
  m2CreationScript = writeShellScript "create-m2-repository" (lib.concatMapStringsSep "\n" (dep: "mkdir -p $out/${dep.path}\nln -s ${builtins.toString dep.jar} $out/${dep.path}/${dep.name}") deps);
  m2Repository = stdenvNoCC.mkDerivation {
    inherit version src;
    pname = "${pname}-m2-repository";
    installPhase = ''
      mkdir $out
      ${m2CreationScript}
    '';
  };

  # Prepare a script that will replace that jars with references into the NIX store.
  linkScript = writeShellScript "link-to-jars" ''
    declare -A depsByName
    ${
      lib.concatMapStringsSep "\n"
      (dep: "depsByName[\"${dep.name}\"]=\"${builtins.toString dep.jar}\"")
      (builtins.filter (dep: (lib.strings.hasSuffix ".jar" dep.name && !lib.strings.hasSuffix "-javadoc.jar" dep.name && !lib.strings.hasSuffix "-sources.jar" dep.name)) deps)
    }

    find $out/lib/ -type f > jars
    while IFS= read -r jar; do
      dep=''${depsByName[$(basename "$jar")]}
      if [[ -n "$dep" ]]; then
          echo "Replacing $jar with nix store reference $dep"
          rm "$jar"
          ln -s "$dep" "$jar"
      fi
    done < jars
  '';

  package = stdenvNoCC.mkDerivation {
    inherit pname version src meta buildInputs;
    nativeBuildInputs = [gradle jdk makeWrapper] ++ nativeBuildInputs;
    buildPhase = ''
      runHook preBuild

      # Setup maven repo
      export MAVEN_SOURCE_REPOSITORY=${m2Repository}
      echo "Using maven repository at: $MAVEN_SOURCE_REPOSITORY"

      # create temporary gradle home
      export GRADLE_USER_HOME=$(mktemp -d)

      # Export application version to the build
      export APP_VERSION=${version}

      # built the dam thing!
      gradle --offline --no-daemon --no-watch-fs --no-configuration-cache --no-build-cache --console=plain ${buildTask}

      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/
      mv ${installLocaltion}/lib/*.jar $out/lib/

      ${linkScript}

      mkdir -p $out/bin

      cp $(ls ${installLocaltion}/bin/* | grep -v ".bat") $out/bin/${pname}

      wrapProgram $out/bin/${pname} \
         --set-default JAVA_HOME "${jdk.home}"

      runHook postInstall
    '';
  };
in
  package
