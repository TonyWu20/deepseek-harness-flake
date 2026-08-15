{ self }:
{
  config,
  lib,
  ...
}:

let
  cfg = config.programs.dsh;
in
{
  imports = [
    (import ./options.nix {
      inherit self;
      optionPath = [
        "programs"
        "dsh"
      ];
    })
  ];

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = [ cfg.finalPackage ];
      }
    ]
  );
}
