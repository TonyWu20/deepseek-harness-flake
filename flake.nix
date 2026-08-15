{
  description = "Nix flake for deepseek-harness, the DeepSeek Harness agent CLI (dsh)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
    }:
    let
      current = builtins.fromJSON (builtins.readFile ./VERSION.json);
      inherit (current) rev hash pnpmDepsHash;

      forEachSystem = nixpkgs.lib.genAttrs (import systems);
    in
    rec {
      packages = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };

          src = pkgs.fetchFromGitHub {
            owner = "deepseek-ai";
            repo = "deepseek-harness";
            inherit rev hash;
          };

  # The version is read from the upstream package.json by the update app and
  # recorded here, so flake evaluation does not require fetching the source.
  version = current.version;
        in
        rec {
          default = dsh;

          dsh = pkgs.callPackage ./dsh/package.nix {
            inherit src version pnpmDepsHash;
          };
        }
      );

      lib =
        let
          dsh = import ./dsh/lib.nix {
            inherit self;
            inherit (nixpkgs) lib;
          };
        in
        {
          inherit (dsh) mkDsh;
        };

      nixosModules = rec {
        default = dsh;
        dsh = import ./dsh/module.nix { inherit self; };
      };

      homeModules = rec {
        default = dsh;
        dsh = import ./dsh/home-manager.nix { inherit self; };
      };
      homeManagerModules = homeModules;

      overlays = {
        default =
          _final: prev:
          let
            inherit (prev.stdenv.hostPlatform) system;
          in
          {
            deepseek-harness = self.packages.${system}.dsh;
          };
      };

      formatter = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.nixfmt
      );

      apps = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };

          update = import ./update.nix {
            inherit pkgs;
          };
        in
        {
          update = {
            type = "app";
            program = "${update}/bin/dsh-update";
            meta = {
              description = "Update VERSION.json to the latest upstream master";
            };
          };
        }
      );
    };
}
