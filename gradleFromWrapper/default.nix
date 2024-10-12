pkgs: {
  wrapperPropertiesPath,
  defaultJava ? pkgs.jdk,
}:
pkgs.callPackage (pkgs.gradleGen (let
  wrapperProperties = builtins.readFile wrapperPropertiesPath;
  lines = pkgs.lib.strings.splitString "\n" wrapperProperties;
in {
  inherit defaultJava;

  # Extract version from gradle-wrapper.properties
  version = let
    distributionUrlLine = builtins.head (builtins.filter (
        line:
          builtins.match "distributionUrl=.*" line != null
      )
      lines);
    versionMatch = builtins.match ".*/gradle-([^-]*)-bin.zip" distributionUrlLine;
    versionValue = builtins.elemAt versionMatch 0;
  in
    versionValue;

  # Extract hash from gradle-wrapper.properties
  hash = let
    sha256SumLine = builtins.head (builtins.filter (
        line:
          builtins.match "distributionSha256Sum=.*" line != null
      )
      lines);
    sha256Hex = builtins.elemAt (builtins.match "distributionSha256Sum=(.*)" sha256SumLine) 0;
    formattedHash = "sha256:" + sha256Hex;
  in
    formattedHash;
})) {}
