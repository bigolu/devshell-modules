{ lib, config, ... }:
let
  inherit (lib) optionals mkEnableOption;
in
{
  options.minimal.enable = mkEnableOption "the removal of certain defaults from the environment";

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
