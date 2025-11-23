pkgs: args: let
  inherit (pkgs) lib;
  safeArgs =
    if (lib.isString args || lib.isPath args)
    then
      lib.warn
      "DEPRECATED: gradleFromWrapper now expects an attrset like gradleFromWrapper { wrapperPropertiesPath = ${args}; defaultJava = pkgs.jdk;}."
      {
        wrapperPropertiesPath = args;
        defaultJava = pkgs.jdk;
      }
    else if builtins.isAttrs args
    then args
    else throw "Expected an attrset, path (deprecated) or string (deprecated), got: ${builtins.typeOf args}";

  wrapperProperties = builtins.readFile safeArgs.wrapperPropertiesPath;
  lines = pkgs.lib.strings.splitString "\n" wrapperProperties;

  # Extract version from gradle-wrapper.properties
  distributionUrlMatches = builtins.filter (line: builtins.match "distributionUrl=(.*)" line != null) lines;
  rawDistributionUrl = builtins.head (builtins.match "distributionUrl=(.*)" (builtins.head distributionUrlMatches));
  distributionUrl = builtins.replaceStrings ["\\:"] [":"] rawDistributionUrl;
  version = builtins.head (builtins.match ".*/gradle-([^-]*)-(bin|all).zip" distributionUrl);

  # Extract hash from gradle-wrapper.properties
  sha256SumLine = builtins.head (builtins.filter (line: builtins.match "distributionSha256Sum=.*" line != null) lines);
  sha256Hex = builtins.head (builtins.match "distributionSha256Sum=(.*)" sha256SumLine);
  hash = "sha256:" + sha256Hex;
in
  (pkgs.gradle-packages.mkGradle {
    inherit version hash;
    inherit (safeArgs) defaultJava;
  }).overrideAttrs {
    src = pkgs.fetchurl {
      url = distributionUrl;
      inherit hash;
    };
  }
