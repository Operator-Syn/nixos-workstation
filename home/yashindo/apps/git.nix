{
  lib,
  config,
  ...
}: {
  options.modules.git.enable = lib.mkEnableOption "Git configuration";

  config = lib.mkIf config.modules.git.enable {
    programs.git = {
      enable = true;

      settings = {
        init.defaultBranch = "main";
      };
    };
  };
}
