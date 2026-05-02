{ lib, config, pkgs, ... }:
let
  inherit (lib) optionalAttrs mkOption types getExe';
  stateConfig = config.state;
  mkdir = getExe' pkgs.coreutils "mkdir";
in
{
  options.state = {
    enable = mkOption {
      default = true;
      example = true;
      description = "Whether to enable the management of the project state directory";
      type = types.bool;
    };

    autoCreate = mkOption {
      default = true;
      example = true;
      description = "Whether to automatically create the state directory";
      type = types.bool;
    };
  };

  config = optionalAttrs stateConfig.enable {
    devshell.startup = optionalAttrs stateConfig.autoCreate {
      # HACK: This should run before other startup scripts, but there's no way to
      # control the order. I noticed that they're sorted so I'm prefixing it with
      # 'AAA' in hopes that it gets put first.
      AAAstateDirectory.text = ''
        if [[ ! -e $PRJ_DATA_DIR ]]; then
          ${mkdir} --parents "$PRJ_DATA_DIR"
          echo '*' >"$PRJ_DATA_DIR/.gitignore"
        fi
      '';
    };
  };
}
