{lib, config, ...}: {
  options.modules.gh.enable = lib.mkEnableOption "GitHub CLI";

  config = lib.mkIf config.modules.gh.enable {
    programs.gh = {
      enable = true;
      settings = {
        git_protocol = "https";
        prompt = "enabled";
      };
    };
  };
}
