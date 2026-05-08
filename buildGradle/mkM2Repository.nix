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
  mkDep = depSpec: let
    # Gradle module metadata may specify a different url suffix than the artifact name
    urlSuffixFallback = depSpec.name;
    urlSuffix =
      if (depSpec.module == null)
      then urlSuffixFallback
      else let
        module = fetchArtifact {
          urls = lib.map (prefix: "${prefix}/${depSpec.module.name}") depSpec.url_prefixes;
          inherit (depSpec.module) hash name;
        };
        moduleMetadata = builtins.fromJSON (builtins.readFile module);
        variantFiles = lib.flatten (lib.map (variant: variant.files or []) (moduleMetadata.variants or []));
        matchingVariantFiles =
          builtins.filter (
            file: (file.${depSpec.hash_algo} or null) == depSpec.hash_value && file.name == depSpec.name
          )
          variantFiles;
        firstMatchingVariantFile = builtins.head matchingVariantFiles;
      in
        if matchingVariantFiles == []
        then urlSuffixFallback
        else if builtins.all (f: f.url == firstMatchingVariantFile.url) matchingVariantFiles
        then firstMatchingVariantFile.url
        else throw "Found multiple matching urls with name ${depSpec.name} and hash ${depSpec.hash} in ${module}: ${builtins.toString (lib.map (f: f.url) matchingVariantFiles)}";
    urls = lib.map (prefix: "${prefix}/${urlSuffix}") depSpec.url_prefixes;
  in {
    inherit urls urlSuffix;
    inherit (depSpec) path name hash component;
    jar = fetchArtifact {
      inherit urls;
      inherit (depSpec) hash name;
    };
  };
  dependencies = builtins.map mkDep depSpecs;

  # write a dedicated script for the m2 repository creation. Otherwise, the m2Repository derivation might crash with 'Argument list too long'
  m2Repository =
    runCommand "${pname}-${version}-m2-repository"
    {}
    (
      "mkdir $out"
      + lib.concatMapStringsSep "\n" (dep: "mkdir -p $out/${dep.path}\nln -s ${builtins.toString dep.jar} $out/${dep.path}/${dep.urlSuffix}") dependencies
    );
in {inherit dependencies m2Repository;}
