{ self, lib }:

{
  mkDsh =
    {
      pkgs,
      modules ? [ ],
      extraSpecialArgs ? { },
    }:
    let
      evaluated = lib.evalModules {
        specialArgs = {
          inherit self pkgs;
        }
        // extraSpecialArgs;

        modules = [ (import ./options.nix { inherit self; }) ] ++ modules;
      };

      inherit (evaluated.config.programs.dsh) finalPackage finalArgs;
    in
    {
      inherit (evaluated) config options;
      dsh = finalPackage;
      package = finalPackage;
      args = finalArgs;
    };
}
