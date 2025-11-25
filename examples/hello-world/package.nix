{
  lib,
  jdk,
  version ? "1.0.0",
  buildGradleApplication,
  gradleFromWrapper,
}: let
  gradle = gradleFromWrapper {
    wrapperPropertiesPath = ./gradle/wrapper/gradle-wrapper.properties;
    defaultJava = jdk;
  };
in
  buildGradleApplication {
    inherit gradle version jdk;
    pname = "hello-world";
    src = lib.cleanSourceWith {
      src = lib.cleanSource ./.;
      filter = path: type: let
        ignore = builtins.elem (baseNameOf path);
      in
        ! ignore [
          "package.nix"
          "gradlew.bat"
          "gradlew"
        ];
    };

    meta = with lib; {
      description = "Hello World Application";
      longDescription = ''
        Not much to say here...
      '';
      sourceProvenance = with sourceTypes; [
        fromSource
        binaryBytecode
      ];
      platforms = platforms.unix;
    };
  }
