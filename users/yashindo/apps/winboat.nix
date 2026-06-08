{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  unstable = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
in {
  options.modules.winboat.enable = lib.mkEnableOption "WinBoat Windows app runner";

  config = lib.mkIf config.modules.winboat.enable {
    home.packages = [unstable.winboat];
  };
}
