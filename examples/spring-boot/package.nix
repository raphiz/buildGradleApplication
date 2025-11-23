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
    pname = "spring-boot";
    src = ./.;
    meta = with lib; {
      description = "Spring Boot Example Application";
      longDescription = ''
        Will start a server at Port 8080
      '';
      sourceProvenance = with sourceTypes; [
        fromSource
        binaryBytecode
      ];
      platforms = platforms.unix;
    };
  }
