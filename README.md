# `buildGradleApplication`

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

**`buildGradleApplication`** is a [Nix](https://nixos.org/nix/) builder function for packaging [Gradle](https://gradle.org/) applications.

`buildGradleApplication` drastically simplifies the integration of Gradle projects in the Nix ecosystem by defining a set of rules/constraints that a Gradle project must follow.

## Goals

- For now, the focus is on packaging Gradle applications, not libraries.
- Using the builder function should feel idiomatic to Nix. It should provide the same experience as `buildPythonPackage` or `buildPerlPackage` but with fewer options.
- The rules imposed on the Gradle build should be idiomatic to Gradle and ideally promote Gradle best practices.
- Support automatic updates with tools such as renovate.
- All dependencies (jars) should be packaged into discrete derivations to facilitate efficient deployments and [layered OIC images](https://ryantm.github.io/nixpkgs/builders/images/dockertools/#ssec-pkgs-dockerTools-buildLayeredImage).
- This project should be small and simple.

## Non-Goals

- `buildGradleApplication` is _not_ a general purpose solution for building arbitrary Gradle projects. If you want to do that, check out [gradle2nix](https://github.com/tadfisher/gradle2nix) instead.
- Do not try to replicate Gradle's behaviour, e.g. to construct a runtime classpath. Instead, use the Gradle built-ins to produce these results.

## Rules

### Rule #1: Requires Checksum Verification (`verification-metadata.xml`)

Using Gradles built-in Mechanism for [dependency verification](https://docs.gradle.org/current/userguide/dependency_verification.html) is not only a security best practice, but also allows `buildGradleApplication` to fetch an fixed version (as a [fixed-output derivations](https://nixos.org/manual/nix/stable/language/advanced-attributes.html#adv-attr-outputHash)) of a dependency and its metadata.

While it should be straight forward to generate a `verification-metadata.xml` file by following the [documentation](https://docs.gradle.org/current/userguide/dependency_verification.html), take extra care that Gradle version and JDK version align! This should not be a problem when using Nix for your development environment.

Once such a `verification-metadata.xml` file exists, Gradle will refuse to download anything not mentioned in it. This can lead to issues when using an IDE such as [IntelliJ IDEA which might attempt to download javadoc and source artifacts](https://youtrack.jetbrains.com/issue/IDEA-258328/Dependency-verification-failed-Checksums-of-downloaded-sources-not-included-in-verification-metadata.xml) not listed in the `verification-metadata.xml` file. You can automatically trust all javadocs/sources as follows:

```xml
<!-- gradle/verification-metadata.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<verification-metadata xmlns="https://schema.gradle.org/dependency-verification" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="https://schema.gradle.org/dependency-verification https://schema.gradle.org/dependency-verification/dependency-verification-1.2.xsd">
   <configuration>
      <verify-metadata>true</verify-metadata>
      <verify-signatures>false</verify-signatures>
      <trusted-artifacts>
        <!-- See https://youtrack.jetbrains.com/issue/IDEA-258328 -->
         <trust file=".*-javadoc[.]jar" regex="true"/>
         <trust file=".*-sources[.]jar" regex="true"/>
         <trust file="gradle-[0-9.]+-src.zip" regex="true"/>
         <trust file="groovy-[a-z]*-?[0-9.]+.pom" regex="true"/>
      </trusted-artifacts>
   </configuration>
   <components>
       <!-- ... -->
   </components>
</verification-metadata>
```

Here is an example command to let Gradle add all dependency artifacts to your `verification-metadata.xml`:

```bash
gradle --refresh-dependencies --write-verification-metadata sha256 --write-locks prepareKotlinBuildScriptModel
```

Gradle not remove any artefacts from the `verification-metadata.xml` even if they are not used anymore. This can lead to . The `updateVerificationMetadata` package from this flake can be used to re-generate the file while keeping the `<configuration>` section. You must ensure that the Gradle version and JDK version align.

```bash
update-verification-metadata
```

Note: [Renovate can and will re-generate this file](https://docs.renovatebot.com/modules/manager/gradle/#dependency-verification) when updating dependencies - Yay 🎉

### Rule #2: Maven Repositories Only

`buildGradleApplication` only supports Maven repositories to fetch dependencies. Ivy is not supported.

### Rule #3: No Downloads

Nix uses a sandbox which prevents internet access during build time (for a good reason). All other (implicit) build dependencies must be provided via Nix instead. `buildGradleApplication` takes care of downloading and providing the Maven dependencies. Everything else is specific to your build and must be handled by you.

Let's take the [`gradle-node` plugin](https://github.com/node-gradle/gradle-node-plugin/blob/master/docs/usage.md) as an example. It can be configured to download and install a specific version of Node.js. This will fail for the reason given above. Instead, provide Node.js as `nativeBuildInput` instead:

```nix
buildGradleApplication {
    # ...
    nativeBuildInputs = [pkgs.nodejs];
}
```

### Rule #4: Centralized Repository

Because Nix uses a sandbox which prevents internet access during build time, `buildGradleApplication` needs to pre fetch all required artifacts. These are then made available to the offline build using a local maven repository. The location of this repository depends on [it's contents](https://nixos.org/guides/nix-pills/nix-store-paths) and is provided to the Gradle build via the  `MAVEN_SOURCE_REPOSITORY` Environment Variable.

It's a Gradle best practice to [centralize repositories declarations](https://docs.gradle.org/current/userguide/declaring_repositories.html#sub:centralized-repository-declaration). 

`buildGradleApplication` assumes that all repository declarations are located in your `settings.gradle(.kts)` files. It will then replace these declarations during build time with the location of the offline repository (using a [Gradle init script](./buildGradleApplication/init.gradle.kts))

Here is an example of how your Gradle build should declare it's repositories:

```kotlin
// settings.gradle.kts
pluginManagement {
    repositories {
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        mavenCentral()
    }

    // Highly recommended, see https://docs.gradle.org/current/userguide/declaring_repositories.html#sub:centralized-repository-declaration
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
}
```

Note that repository declarations must be defined for each [included build](https://docs.gradle.org/current/userguide/composite_builds.html) as well.

Also Note that `buildGradleApplication` is (currently) unable to extract the declared repositories from your Gradle build. If you use different or additional repositories, you must provide it to `buildGradleApplication` using the `repositories` parameter:

```nix
buildGradleApplication {
    # ...
    repositories = ["https://plugins.gradle.org/m2/" "https://repo1.maven.org/maven2/" "https://example.com/maven2/"];
}
```

### Rule #4: Using the `application` Plugin

Currently, the focus of this tool is to package Gradle applications. In order to launch a java application, we need both an main class as an entry point and a runtime classpath. The latter must contain both third-party dependencies fetched from a maven repository and project local libraries generated from other projects within the same build.

Gradle provides exactly that (a so called [Distribution](https://docs.gradle.org/current/userguide/distribution_plugin.html#distribution_plugin)) with the built in [`application` plugin](https://docs.gradle.org/current/userguide/application_plugin.html). The required configuration is quite reasonable:

```kotlin
plugins {
    application
    // ...
}

application {
    mainClass.set("org.gradle.sample.Main")
}
// ...

```

Checkout the [`application` plugin documentation](https://docs.gradle.org/current/userguide/application_plugin.html) for any further details.

### Rule #5: Tell gradle to be more reproducible

Gradle has [a few switches to make builds more reproducible](https://docs.gradle.org/current/userguide/working_with_files.html#sec:reproducible_archives). These must be set to ensure proper reproducibility of the genereated `.jar` files.

```kotlin
tasks.withType<AbstractArchiveTask>().configureEach {
    isPreserveFileTimestamps = false
    isReproducibleFileOrder = true
}
```

## Installation (via flakes)

```nix
{
  inputs = {
    build-gradle-application.url = "github:raphiz/buildGradleApplication";
    # ...
  };

  # ...
  outputs = {
    nixpkgs,
    build-gradle-application,
    ...
    }: {
        # ...
        pkgs = import nixpkgs {
          inherit system;
          overlays = [build-gradle-application.overlays.default];
        };
        # ...
    };
}

```

## Usage

The usage of `buildGradleApplication` should be straight forward once your build follows the outlined rules above. Here is a very minimal example:

```nix
# package.nix
{
  lib,
  version,
  buildGradleApplication,
}:
buildGradleApplication {
  pname = "hello-world";
  version = version;
  src = ./.;
  meta = with lib; {
    description = "Hello World Application";
  };
}

```

For further examples, checkout the [example repository](https://github.com/raphiz/buildGradleApplication-examples/)

All available parameters of `buildGradleApplication` are documented in the [source code](https://github.com/raphiz/buildGradleApplication/blob/main/buildGradleApplication/default.nix)

## Additional Information

### Maven Repositories are not Mirrors

Sadly, many Maven repositories contain the same artifacts but with different metadata. One such example is the Kotlin JVM Gradle Plugin ([Maven Central](https://repo1.maven.org/maven2/org/jetbrains/kotlin/jvm/org.jetbrains.kotlin.jvm.gradle.plugin/1.7.10/org.jetbrains.kotlin.jvm.gradle.plugin-1.7.10.pom) vs. [gradle plugin portal](https://plugins.gradle.org/m2/org/jetbrains/kotlin/jvm/org.jetbrains.kotlin.jvm.gradle.plugin/1.7.10/org.jetbrains.kotlin.jvm.gradle.plugin-1.7.10.pom)). To work around this, `buildGradleApplication` uses a special `fetchArtifact` builder instead of the classic [`fetchurl` fetchers](https://ryantm.github.io/nixpkgs/builders/fetchers/). `fetchArtifact` will try to download a given artifact with a given hash from all provided urls. If the checksum of the downloaded artifact differs from the expected one, it is quietly ignored and the next url is tried instead.

### Very slow first build

The first build with `buildGradleApplication` might be very slow. The reason for this is, that each maven artifact is a dedicated derivation and derivations are not built in parallel by default.
You can speed up the first build by enabling concurrent builds, for example:

```bash
nix build -j 15
```

## Contributing

Feel free to [create an issue](https://github.com/raphiz/buildGradleApplication/issues/new) or submit a pull request.

Feedback is also very welcome!

## License

`buildGradleApplication` is licensed under the MIT License.
