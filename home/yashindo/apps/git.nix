{
  lib,
  config,
  pkgs,
  ...
}: {
  options.modules.git.enable = lib.mkEnableOption "Git configuration";

  config = lib.mkIf config.modules.git.enable {
    home.packages = [pkgs.git-credential-manager];

    programs.git = {
      enable = true;

      settings = {
        init.defaultBranch = "main";
        credential.helper = "manager";
        credential.credentialStore = "secretservice";
      };
    };
  };
}
