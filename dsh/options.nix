{
  self,
  optionPath ? [
    "programs"
    "dsh"
  ],
}:
{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (pkgs.stdenv.hostPlatform) system;
  inherit (self.packages.${system}) dsh;
  cfg = lib.attrByPath optionPath { } config;
in
{
  options = lib.setAttrByPath optionPath {
    enable = lib.mkEnableOption "the DeepSeek Harness CLI (dsh)";

    package = lib.mkOption {
      type = lib.types.package;
      default = dsh;
      description = "The dsh package to install.";
    };

    profile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Profile name passed to `dsh --profile <name>` when the command line
        does not contain an explicit `--profile`.  dsh requires a profile, so
        this option makes a plain `dsh` invocation boot a fixed profile, for
        example `web` or `headless`.  The `dsh web` and `dsh plugin`
        subcommands are exempt: they reject a parent `--profile`.
      '';
      example = "headless";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Declarative contents of `$DSH_HOME/settings.yaml`.  The file is
        written on every invocation: declarative values win over existing
        local values, and local settings not present in the declaration are
        preserved.
      '';
      example = lib.literalExpression ''
        {
          profile = "headless";
          model = {
            provider = "deepseek";
            name = "deepseek-v4";
          };
        }
      '';
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Extra environment variables to export before launching dsh.  Use this
        for `DSH_HOME` or API keys.
      '';
      example = lib.literalExpression ''
        {
          DSH_HOME = "/home/user/.dsh";
          DEEPSEEK_API_KEY = "sk-...";
        }
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Extra raw CLI arguments to append to every dsh invocation.
      '';
      example = lib.literalExpression ''
        [ "--patch" "/etc/dsh/cordis.patch.yml" ]
      '';
    };

    finalArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      internal = true;
      readOnly = true;
    };

    finalPackage = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
    };
  };

  config = lib.setAttrByPath optionPath (
    let
      inherit (cfg)
        package
        profile
        settings
        environment
        extraArgs
        ;

      settingsPath =
        if settings == { } then null else pkgs.writeText "dsh-settings.yaml" (builtins.toJSON settings);

      settingsPrelude = lib.optionalString (settingsPath != null) # bash
        ''
          dsh_home="''${DSH_HOME:-$HOME/.dsh}"

          if [ -L "$dsh_home/settings.yaml" ]; then
            rm "$dsh_home/settings.yaml"
          fi

          mkdir -p "$dsh_home"
          tmp="$(mktemp "$dsh_home/settings.yaml.XXXXXX")"

          if [ -f "$dsh_home/settings.yaml" ]; then
            ${lib.getExe pkgs.yq-go} '. * load("${settingsPath}")' \
              "$dsh_home/settings.yaml" > "$tmp"
          else
            cp ${lib.escapeShellArg settingsPath} "$tmp"
          fi

          chmod 0600 "$tmp"

          if [ ! -f "$dsh_home/settings.yaml" ] || ! cmp -s "$tmp" "$dsh_home/settings.yaml"; then
            mv "$tmp" "$dsh_home/settings.yaml"
          else
            rm "$tmp"
          fi
        '';

      envPrelude = lib.concatLines (
        lib.mapAttrsToList (name: value: # bash
          ''
            export ${lib.escapeShellArg name}=${lib.escapeShellArg value}
          ''
        ) environment
      );

      # Prepend `--profile <name>` when the invocation has no explicit
      # `--profile` flag and is not a dsh subcommand (`web`, `plugin`) that
      # rejects parent `--profile`.
      profileArgs = lib.optionalString (profile != null) # bash
        ''
          wants_profile=0
          is_subcommand=0
          for arg in "$@"; do
            case "$arg" in
              --) break ;;
              --profile) wants_profile=1 ;;
              --profile=*) wants_profile=1 ;;
              web|plugin) is_subcommand=1 ;;
            esac
          done

          if [ "$wants_profile" -eq 0 ] && [ "$is_subcommand" -eq 0 ]; then
            set -- --profile ${lib.escapeShellArg profile} "$@"
          fi
        '';

      argsStr = lib.concatMapStringsSep " " lib.escapeShellArg extraArgs;

      wrapped =
        if
          profile == null
          && settingsPath == null
          && environment == { }
          && extraArgs == [ ]
        then
          package
        else
          pkgs.writeShellScriptBin "dsh" # bash
            ''
              set -euo pipefail
              ${envPrelude}
              ${settingsPrelude}
              ${profileArgs}
              exec ${lib.escapeShellArg (lib.getExe package)} ${argsStr} "$@"
            '';
    in
    {
      finalArgs =
        (lib.optionals (profile != null) [
          "--profile"
          profile
        ])
        ++ extraArgs;
      finalPackage = wrapped;
    }
  );
}
