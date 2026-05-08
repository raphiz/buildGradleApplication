# `buildGradleApplication`

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

**`buildGradleApplication`** is a [Nix](https://nixos.org/nix/) builder function for packaging [Gradle](https://gradle.org/) applications.

`buildGradleApplication` drastically simplifies the integration of Gradle projects in the Nix ecosystem by defining a set of rules/constraints that a Gradle project must follow.

## Goals

- For now, the focus is on packaging Gradle applications, not libraries.
- Using the builder function should feel idiomatic to Nix. It should provide the same experience as `buildPythonPackage` or `buildPerlPackage` but with fewer options.
- The rules imposed on the Gradle build should be idiomatic to Gradle and ideally promote Gradle best practices.
- Support automatic updates with tools such as renovate.
- All dependencies (jars) should be packaged into discrete derivations (and linked in the final result) to facilitate efficient deployments and [layered OIC images](https://ryantm.github.io/nixpkgs/builders/images/dockertools/#ssec-pkgs-dockerTools-buildLayeredImage).
- This project should be small and simple.

## Non-Goals

- `buildGradleApplication` is _not_ a general purpose solution for building arbitrary Gradle projects. If you want to do that, check out [gradle2nix](https://github.com/tadfisher/gradle2nix) instead.
- Do not try to replicate Gradle's behaviour, e.g. to construct a runtime classpath. Instead, use the Gradle built-ins to produce these results.
- Android. But if you have experience in Android, talk to me! It might not be that hard to support android instead (by breaking/adopting Rule #5).

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

The usage of `buildGradleApplication` should be straight forward once your build follows the outlined rules below. Here is a very minimal example:

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

For further examples, checkout the [examples directory](./examples)

All available parameters of `buildGradleApplication` are documented in the [source code](https://github.com/raphiz/buildGradleApplication/blob/main/buildGradle/buildGradleApplication.nix)

For more control over the installation phase, you may use `buildGradleArtifact`, and extra arguments will be passed to mkDerivation, so you can tweak preBuild, postBuild, etc. You can use script `$linkToJars folder` from `buildPhase` or other phases in order to change every jar inside a folder with a link to nix store as an usual nix build would normally do.

## Rules

### Rule #1: Requires Checksum Verification (`verification-metadata.xml`)

Using Gradle's built-in Mechanism for [dependency verification](https://docs.gradle.org/current/userguide/dependency_verification.html) is not only a security best practice, but also allows `buildGradleApplication` to fetch an fixed version (as a [fixed-output derivations](https://nixos.org/manual/nix/stable/language/advanced-attributes.html#adv-attr-outputHash)) of a dependency and its metadata.

While it should be straight forward to generate a `verification-metadata.xml` file by following the [documentation](https://docs.gradle.org/current/userguide/dependency_verification.html), take extra care that Gradle version and JDK version align! This should not be a problem when using Nix for your development environment.

Here is an example command to let Gradle add all dependency artifacts to your `verification-metadata.xml`:

```bash
gradle --refresh-dependencies --write-verification-metadata sha256 --write-locks dependencies
```

Gradle does not remove any artefacts from the `verification-metadata.xml` even if they are not used anymore. This can lead to a unnecessary large  file. The `updateVerificationMetadata` package from this flake can be used to re-generate the file while keeping the `<configuration>` section. Again: You must ensure that the Gradle version and JDK version align.

```bash
update-verification-metadata
```

**Tip**: [Renovate can and will append updated dependencies to this file](https://docs.renovatebot.com/modules/manager/gradle/#dependency-verification) - Yay 🎉

#### Dependency Verification and IntelliJ IDEA

Gradle's `verification-metadata.xml` file enforces that only explicitly listed artifacts are downloaded during builds. However, this can lead to issues when using IDEs like IntelliJ IDEA, [which will download additional artifacts (Javadoc, source files and more) that are not included in the verification metadata](https://youtrack.jetbrains.com/issue/IDEA-258328).

To handle this issue, you have two options. The one you choose depends on how important dependency verification is to you compared to the effort required to maintain it:

#### Option 1: Disable Dependency Verification for Development (low effort)

Simplify the development process by disabling Gradle's dependency verification. Add the following line to your `gradle.properties` file:

```properties
org.gradle.dependency.verification=off
```

**Note**: You still need the `verification-metadata.xml` file to download the required artifacts and build the Nix package. However, disabling dependency verification prevents you from having to deal with these quirks during development.

#### 2. Manually Add Missing Dependencies (more secure when done properly)

Manually identify and add additional dependencies required by IntelliJ IDEA into the verification-metadata.xml file. I use a [script to simplify that](https://gist.github.com/raphiz/3e03f54cf2b81047e8cdcdd264b56010).

##### 2b. Automatically Trust Javadoc and Source Artifacts

Update your `verification-metadata.xml` file to automatically trust Javadoc and source files, allowing IntelliJ IDEA to fetch them without verification errors. Here's an example configuration:

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
       <!-- Define other dependencies here -->
   </components>
</verification-metadata>
```

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

### Rule #5: Using the `application` Plugin

The main focus of this tool is to package Gradle applications with `buildGradleApplication`. In order to launch a java application, we need both an main class as an entry point and a runtime classpath. The latter must contain both third-party dependencies fetched from a maven repository and project local libraries generated from other projects within the same build.

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

### Rule #6: Tell gradle to be more reproducible (Gradle Versions 8 and lower)

Gradle has [a few switches to make builds more reproducible](https://docs.gradle.org/current/userguide/working_with_files.html#sec:reproducible_archives). These must be set in Gradle Versions < 9 to ensure proper reproducibility of the genereated `.jar` files.
[Gradle 9 and onwards produces reproducible archives by default](https://gradle.org/whats-new/gradle-9/#reproducible-archives-by-default)

```kotlin
// Important: This configuration is probably not complete for your project! 
tasks.withType<AbstractArchiveTask>().configureEach {
    isPreserveFileTimestamps = false
    isReproducibleFileOrder = true
    dirPermissions { unix("755") }
    filePermissions { unix("644") }
}
```

Alternatively, you might use [the Reproducible Builds plugin](https://github.com/gradlex-org/reproducible-builds/) to achive the same.

### Rule #7: Making sure dependency resolution is reproducible

Gradle's dependency resolution _can_ be unstable in the following cases:

- [dynamic dependency versions](https://docs.gradle.org/current/userguide/rich_versions.html) are used (version ranges, latest.release, 1.+, ...)
- Changing versions (SNAPSHOTs, fixed version with changing contents, ...)

The recommended way to use `buildGradleApplication` is to prevent the use of non reproducible dependencies:

```kotlin
configurations.all {
    resolutionStrategy {
        failOnNonReproducibleResolution()
    }
}

```

If you _must_ use these features (please, don't!), use [dependency locking](https://docs.gradle.org/current/userguide/dependency_locking.html#dependency-locking).

For more details, see the ["Making sure resolution is reproducible" section in the Gradle Docs](https://docs.gradle.org/current/userguide/resolution_strategy_tuning.html#reproducible-resolution).

## How it works

![Flow diagram of buildGradleApplication internals](docs/buildGradleApplication-flow.drawio.svg)

## Additional Information

### Maven Repositories are not Mirrors

Sadly, many Maven repositories contain the same artifacts but with different metadata. One such example is the Kotlin JVM Gradle Plugin ([Maven Central](https://repo1.maven.org/maven2/org/jetbrains/kotlin/jvm/org.jetbrains.kotlin.jvm.gradle.plugin/1.7.10/org.jetbrains.kotlin.jvm.gradle.plugin-1.7.10.pom) vs. [gradle plugin portal](https://plugins.gradle.org/m2/org/jetbrains/kotlin/jvm/org.jetbrains.kotlin.jvm.gradle.plugin/1.7.10/org.jetbrains.kotlin.jvm.gradle.plugin-1.7.10.pom)). To work around this, `buildGradleApplication` uses a special `fetchArtifact` builder instead of the classic [`fetchurl` fetchers](https://ryantm.github.io/nixpkgs/builders/fetchers/). `fetchArtifact` will try to download a given artifact with a given hash from all provided urls. If the checksum of the downloaded artifact differs from the expected one, it is quietly ignored and the next url is tried instead.

### Very slow first build

The first build with `buildGradleApplication` might be very slow. The reason for this is, that each maven artifact is a dedicated derivation and derivations are not built in parallel by default.
You can speed up the first build by enabling concurrent builds, for example:

```bash
nix build -j 15
```

## Other useful tools

### `gradleFromWrapper`

The [recommended way to execute any Gradle build is with the help of the Gradle Wrapper](https://docs.gradle.org/current/userguide/gradle_wrapper.html).
It's main motivations are to have a standardised version per project and to make it easy to deploy in different execution environments.
When using Nix, these motivations are largely obsolete.

There may still be reasons to use the wrapper even when using Nix.
In these cases, it's inconvenient to keep both versions (nix and wrapper) in sync.

To simplify this case, you can use the url and checksum from the `gradle-wrapper.properties` file to build exactly the same gradle package with the `gradleFromWrapper` builder function:

```nix
gradle = pkgs.gradleFromWrapper {
    wrapperPropertiesPath = ./gradle/wrapper/gradle-wrapper.properties;
    defaultJava = pkgs.jdk21;
};
```

NOTE: This utility _only_ works with nixpkgs 25.11 and above, since it is based on changes made to `gradle-packages.mkGradle`.

## Contributing

Feel free to [create an issue](https://github.com/raphiz/buildGradleApplication/issues/new) or submit a pull request.

Feedback is also very welcome!

## License

`buildGradleApplication` is licensed under the MIT License.
