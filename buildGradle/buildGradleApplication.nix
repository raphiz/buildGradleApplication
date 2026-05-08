{
  pkgs,
  lib,
  stdenvNoCC,
  writeShellScript,
  makeWrapper,
  mkM2Repository,
  updateVerificationMetadata,
  buildGradleArtifact,
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
  installLocation ? "build/install/*/",
  ...
}@params: 
buildGradleArtifact ({

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
    $linkToJars $out/lib/

    if [ -d agent-libs/ ]; then
        mkdir -p $out/agent-libs/
        mv agent-libs/*.jar $out/agent-libs/
        $linkToJars} $out/agent-libs/
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
} // params)
