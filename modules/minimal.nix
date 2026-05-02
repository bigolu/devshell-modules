{ lib, config, ... }:
let
  inherit (lib) optionals mkOption types;
in
{
  options.minimal.enable = mkOption {
    default = true;
    example = true;
    description = "Whether to enable the removal of certain defaults from the environment.";
    type = types.bool;
  };

  config.env = optionals config.minimal.enable [
    {
      name = "DEVSHELL_NO_MOTD";
      value = 1;
    }
    {
      name = "NIXPKGS_PATH";
      unset = true;
    }
  ];
}
