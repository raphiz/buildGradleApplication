{
  lib,
  runCommandNoCC,
  python3,
  fetchArtifact,
}: {
  pname,
  version,
  src,
  dependencyFilter ? depSpec: true,
  privateRepository ? null,
  repositories ? ["https://plugins.gradle.org/m2/" "https://repo1.maven.org/maven2/"],
  verificationFile ? "gradle/verification-metadata.xml",
}: let
  filteredSrc = lib.fileset.toSource {
    root = src;
    fileset = lib.path.append src verificationFile;
  };

  depSpecs = builtins.filter dependencyFilter (
    # Read all build and runtime dependencies from the verification-metadata XML
    builtins.fromJSON (builtins.readFile (
      runCommandNoCC "depSpecs" {buildInputs = [python3];}
      "python ${./parse.py} -f ${filteredSrc}/${verificationFile} -r ${builtins.toString (builtins.map lib.escapeShellArg repositories)}"
        + lib.strings.optionalString (privateRepository != null) " -p ${lib.escapeShellArg privateRepository}"
        + " > $out"
    ))
  );
  mkDep = { privateUrl ? null, ... }@depSpec: {
    inherit (depSpec) urls path name hash component;
    jar = fetchArtifact {
      inherit (depSpec) urls hash name;
      inherit privateUrl;
    };
  };
  dependencies = builtins.map (depSpec: mkDep depSpec) depSpecs;

  # write a dedicated script for the m2 repository creation. Otherwise, the m2Repository derivation might crash with 'Argument list too long'
  m2Repository =
    runCommandNoCC "${pname}-${version}-m2-repository"
    {src = filteredSrc;}
    (
      "mkdir $out"
      + lib.concatMapStringsSep "\n" (dep: "mkdir -p $out/${dep.path}\nln -s ${builtins.toString dep.jar} $out/${dep.path}/${dep.name}") dependencies
    );
in {inherit dependencies m2Repository;}
