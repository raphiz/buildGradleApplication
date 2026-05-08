{
  description = "A Nix builder function for packaging Gradle applications";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    systems.url = "github:nix-systems/default";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        ./examples
      ];

      flake = {
        overlays = {
          default = final: prev: {
            fetchArtifact = prev.callPackage ./fetchArtefact/default.nix {};
            mkM2Repository = prev.callPackage ./buildGradle/mkM2Repository.nix {};
            buildGradleArtifact = prev.callPackage ./buildGradle/buildGradleArtifact.nix {};
            buildGradleApplication = prev.callPackage ./buildGradle/buildGradleApplication.nix {};
            updateVerificationMetadata = prev.callPackage ./update-verification-metadata/default.nix {};
            gradleFromWrapper = import ./gradleFromWrapper final;
          };
        };
      };

      systems = import inputs.systems;

      perSystem = {
        config,
        system,
        ...
      }: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        formatter = pkgs.alejandra;
        legacyPackages = rec {
          fetchArtifact = pkgs.callPackage ./fetchArtefact/default.nix {};
          mkM2Repository = pkgs.callPackage ./buildGradle/mkM2Repository.nix {
            inherit fetchArtifact;
          };
          updateVerificationMetadata = pkgs.callPackage ./update-verification-metadata/default.nix {};
          buildGradleArtifact = pkgs.callPackage ./buildGradle/buildGradleArtifact.nix {
            inherit mkM2Repository updateVerificationMetadata;
          };
          buildGradleApplication = pkgs.callPackage ./buildGradle/buildGradleApplication.nix {
            inherit mkM2Repository updateVerificationMetadata buildGradleArtifact;
          };
          gradleFromWrapper = import ./gradleFromWrapper pkgs;
        };
      };
    };
}
