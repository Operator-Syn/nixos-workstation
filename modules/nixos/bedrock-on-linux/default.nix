{
  config,
  lib,
  pkgs,
  bedrockOnLinux,
  ...
}: let
  cfg = config.modules.bedrock-on-linux;
in {
  options.modules.bedrock-on-linux.enable =
    lib.mkEnableOption "BedrockOnLinux";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "BedrockOnLinux currently supports x86_64-linux only.";
      }
    ];

    environment.systemPackages = [bedrockOnLinux];
  };
}
