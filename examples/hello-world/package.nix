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
    src = ./.;
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
