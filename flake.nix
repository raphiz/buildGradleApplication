{
  description = "A Nix builder function for packaging Gradle applications";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-24.05";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    ...
  }: let
    version = self.shortRev or "dirty";
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      flake = {
        overlays = {
          default = final: prev: {
            fetchArtifact = prev.callPackage ./fetchArtefact/default.nix {};
            mkM2Repository = prev.callPackage ./buildGradleApplication/mkM2Repository.nix {};
            buildGradleApplication = prev.callPackage ./buildGradleApplication/default.nix {};
            updateVerificationMetadata = prev.callPackage ./update-verification-metadata/default.nix {};
            updateGradleVersion = prev.callPackage ./update-gradle-version/default.nix {};
          };
        };
      };

      systems = ["x86_64-linux" "x86_64-darwin" "aarch64-darwin" "aarch64-linux"];

      perSystem = {
        config,
        system,
        ...
      }: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [self.overlays.default];
        };
      in {
        formatter = pkgs.alejandra;
      };
    };
}
