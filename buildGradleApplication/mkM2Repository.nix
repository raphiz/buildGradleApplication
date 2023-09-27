{
  lib,
  stdenvNoCC,
  runCommand,
  writeShellScript,
  python3,
  fetchArtifact,
}: {
  pname,
  version,
  src,
  repositories ? ["https://plugins.gradle.org/m2/" "https://repo1.maven.org/maven2/"],
  verificationFile ? "gradle/verification-metadata.xml",
}: let
  filteredSrc = let
    origSrc =
      if src ? _isLibCleanSourceWith
      then src.origSrc
      else src;
    getRelativePath = path: lib.removePrefix (toString origSrc + "/") path;
    cleanedSource = lib.cleanSourceWith {
      src = src;
      filter = path: type: lib.hasPrefix (getRelativePath path) verificationFile;
    };
  in
    if lib.canCleanSource src
    then cleanedSource
    else src;

  # Read all build and runtime dependencies from the verification-metadata XML
  depSpecs = builtins.fromJSON (builtins.readFile (
    runCommand "depSpecs" {buildInputs = [python3];}
    "python ${./parse.py} ${filteredSrc}/${verificationFile} ${builtins.toString (builtins.map lib.escapeShellArg repositories)}> $out"
  ));
  mkDep = depSpec: {
    inherit (depSpec) urls path name hash component;
    jar = fetchArtifact {
      inherit (depSpec) urls hash name;
    };
  };
  dependencies = builtins.map (depSpec: mkDep depSpec) depSpecs;

  # write a dedicated script for the m2 repository creation. Otherwise, the m2Repository derivation might crash with 'Argument list too long'
  m2CreationScript = writeShellScript "create-m2-repository" (lib.concatMapStringsSep "\n" (dep: "mkdir -p $out/${dep.path}\nln -s ${builtins.toString dep.jar} $out/${dep.path}/${dep.name}") dependencies);
  m2Repository = stdenvNoCC.mkDerivation {
    inherit version;
    src = filteredSrc;
    pname = "${pname}-m2-repository";
    installPhase = ''
      mkdir $out
      ${m2CreationScript}
    '';
  };
in {inherit dependencies m2Repository;}
