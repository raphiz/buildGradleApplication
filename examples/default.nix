{config, ...}: let
  overlay = config.flake.overlays.default;
in {
  perSystem = {
    lib,
    pkgs,
    self',
    ...
  }: let
    pkgs' = pkgs.extend overlay;
    exampleApps =
      lib.attrNames (lib.filterAttrs (name: pathType: pathType == "directory") (builtins.readDir ./.));
    examplePkgFor = name:
      pkgs'.callPackage ./${name}/package.nix {};
  in {
    checks = lib.listToAttrs (map
      (name: {
        name = "example-${name}";
        value = examplePkgFor name;
      })
      exampleApps);
  };
}
