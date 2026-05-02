{ lib, config, ... }:
let
  inherit (lib) optionalAttrs mkEnableOption mkOption types mkIf escapeShellArg;
  secretsConfig = config.secrets;
  dotenvConfig = secretsConfig.dotenv;
in
{
  options.secrets = {
    enable = mkOption {
      default = true;
      example = true;
      description = "Whether to enable the loading of secrets.";
      type = types.bool;
    };

    dotenv = {
      enable = mkEnableOption "dotenv support";

      path = mkOption {
        type = types.str;
        description = "Path to `.env` file, relative to `$PRJ_ROOT`";
        default = ".env";
        apply = value: ''"$PRJ_ROOT"/${escapeShellArg value}'';
      };
    };
  };

  config = mkIf secretsConfig.enable {
    devshell.startup = optionalAttrs dotenvConfig.enable {
      secretsDotenv.text = ''
        if [[ -e ${dotenvConfig.path} ]]; then
          # Export any variables that are modified/created
          set -a
          source ${dotenvConfig.path}
          set +a
        fi
      '';
    };
  };
}
