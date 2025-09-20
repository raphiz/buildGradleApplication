{
  lib,
  python3,
  git,
  writeShellApplication,
  updateAction ? "dependencies",
  cmd ? "gradle --refresh-dependencies --write-verification-metadata sha256 ${updateAction}",
  verificationFile ? "gradle/verification-metadata.xml",
  whitelist ? [],
}:
writeShellApplication {
  name = "update-verification-metadata";

  runtimeInputs = [python3 git];
  text = ''
    verificationFile=''${1:-${verificationFile}}
    if [ ! -f "$verificationFile" ]
    then
      echo "WARNING: $verificationFile does not (yet) exist." 1>&2
    fi

    update_metadata() {
      if [ -f "$verificationFile" ]; then
        echo "Removing all component entries from $build/$verificationFile for build $build"
      fi
      python ${./update-verification-metadata.py} "$verificationFile" ${builtins.toString (builtins.map lib.escapeShellArg whitelist)}
      echo "(Re)generating gradle verification data for build $build"
      ${cmd}
    }


    echo "Locating included builds"
    includedBuilds=$(gradle -q -Dorg.gradle.unsafe.isolated-projects=false --no-configuration-cache --init-script ${./listIncludedBuildsRelative.init.gradle.kts} listIncludedBuilds)
    for build in $includedBuilds; do
      pushd "$build" > /dev/null
      update_metadata
      popd > /dev/null
    done

    build=. update_metadata

    python ${./merge-verification-metadata.py} "$verificationFile" "''${includedBuilds[@]}"
  '';
}
