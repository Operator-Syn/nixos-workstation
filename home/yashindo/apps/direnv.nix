{
  config,
  lib,
  ...
}: {
  options.modules.direnv.enable = lib.mkEnableOption "direnv shell integration";

  config = lib.mkIf config.modules.direnv.enable {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };
}
