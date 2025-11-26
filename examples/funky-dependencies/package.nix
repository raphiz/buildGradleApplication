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
    pname = "funky-dependencies";
    src = ./.;
    meta = with lib; {
      description = "Example project with funky dependencies";
      longDescription = ''
        Lots of libraries have references to (metadata) jars that have a different url than the name in the verification.xml file, for example:
        - kasechange-metadata-1.4.1.jar (net.pearx.kasechange:kasechange)
        - kotlin-result-metadata-2.0.0.jar (com.michael-bull.kotlin-result:kotlin-result)
        - kotlinx-serialization-core-metadata-1.7.0.jar (org.jetbrains.kotlinx:kotlinx-serialization-core)
        To get the proper URL, the corresponding gradle module metadata (.module) must first be analyzed to get the correct URL.
      '';
      sourceProvenance = with sourceTypes; [
        fromSource
        binaryBytecode
      ];
      platforms = platforms.unix;
    };
  }
