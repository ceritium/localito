{
  description = "Browse and edit a Rails app's i18n YAML files in the browser";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      release = builtins.fromJSON (builtins.readFile ./nix/release.json);
      platforms = {
        aarch64-darwin = "macos-arm64";
        x86_64-linux = "linux-x86_64";
        aarch64-linux = "linux-arm64";
      };
      forAll = f: nixpkgs.lib.genAttrs (builtins.attrNames platforms) (system: f system nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAll (
        system: pkgs: {
          default = pkgs.callPackage ./nix/package.nix {
            inherit release;
            platform = platforms.${system};
          };
        }
      );
      apps = forAll (
        system: pkgs: {
          default = {
            type = "app";
            program = "${self.packages.${system}.default}/bin/localito";
          };
        }
      );
    };
}
