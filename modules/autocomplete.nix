{ lib, config, pkgs, ... }:
let
  inherit (lib) optionalAttrs mkOption types;
  bashCompletionShare = "${pkgs.bash-completion}/share";
in
{
  options.autocomplete.enable = mkOption {
    default = true;
    example = true;
    description = "Whether to enable autocomplete in the interactive Bash shell.";
    type = types.bool;
  };

  config.devshell.interactive = optionalAttrs config.autocomplete.enable {
    autocomplete.text = ''
      export XDG_DATA_DIRS="${bashCompletionShare}''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
      source ${bashCompletionShare}/bash-completion/bash_completion
    '';
  };
}
