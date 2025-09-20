pkgs: wrapperPropertiesPath: let
  wrapperProperties = builtins.readFile wrapperPropertiesPath;
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
  pkgs.gradle.unwrapped.overrideAttrs (previousAttrs: {
    inherit version;
    src = pkgs.fetchurl {
      url = distributionUrl;
      inherit hash;
    };
  })
