{
  lib,
  runCommand,
  python3,
  fetchArtifact,
}: {
  pname,
  version,
  src,
  dependencyFilter ? depSpec: true,
  repositories ? ["https://plugins.gradle.org/m2/" "https://repo1.maven.org/maven2/"],
  verificationFile ? "gradle/verification-metadata.xml",
}: let
  verificationXmlFile =
    if lib.isPath src
    then lib.path.append src verificationFile
    else let
      storePathPrefix = "${src}/";
    in
      lib.cleanSourceWith {
        src = storePathPrefix;
        filter = path: type: let
          relPath = lib.removePrefix storePathPrefix path;
        in
          if type == "directory"
          then lib.strings.hasPrefix relPath verificationFile
          else relPath == verificationFile;
      }
      + "/"
      + verificationFile;

  depSpecs = builtins.filter dependencyFilter (
    # Read all build and runtime dependencies from the verification-metadata XML
    builtins.fromJSON (builtins.readFile (
      runCommand "depSpecs" {buildInputs = [python3];}
      "python ${./parse.py} ${verificationXmlFile} ${builtins.toString (builtins.map lib.escapeShellArg repositories)}> $out"
    ))
  );
  mkDep = depSpec: {
    inherit (depSpec) urls path name hash component;
    jar = fetchArtifact {
      inherit (depSpec) urls hash name;
    };
  };
  dependencies = builtins.map mkDep depSpecs;

  # write a dedicated script for the m2 repository creation. Otherwise, the m2Repository derivation might crash with 'Argument list too long'
  m2Repository =
    runCommand "${pname}-${version}-m2-repository"
    {}
    (
      "mkdir $out"
      + lib.concatMapStringsSep "\n" (dep: "mkdir -p $out/${dep.path}\nln -s ${builtins.toString dep.jar} $out/${dep.path}/${dep.name}") dependencies
    );
in {inherit dependencies m2Repository;}
