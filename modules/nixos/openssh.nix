{lib, config, ...}: {
  options.modules.openssh.enable = lib.mkEnableOption "the OpenSSH server";

  config = lib.mkIf config.modules.openssh.enable {
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        PubkeyAuthentication = true;
      };
    };
  };
}
