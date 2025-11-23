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
        Lots of libraries have references to metadata jars that are not present on maven central, for example:
        - kasechange-metadata-1.4.1.jar (net.pearx.kasechange:kasechange)
        - kotlin-result-metadata-2.0.0.jar (com.michael-bull.kotlin-result:kotlin-result)
        - kotlinx-serialization-core-metadata-1.7.0.jar (org.jetbrains.kotlinx:kotlinx-serialization-core)
        These will make the nix build fail because we cannot fetch them. They are usually not needed for the build, so it's relatively safe to ignore them by default.
        However, it MIGHT be the case that some -metadata.jars ARE actually required but I have not yet found one. If you do, please open an issue!
      '';
      sourceProvenance = with sourceTypes; [
        fromSource
        binaryBytecode
      ];
      platforms = platforms.unix;
    };
  }
