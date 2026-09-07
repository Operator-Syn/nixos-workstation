{
  config,
  lib,
  ...
}: {
  options.modules.hermes-desktop.enable = lib.mkEnableOption "Hermes Desktop";

  config = lib.mkIf config.modules.hermes-desktop.enable {
    programs.hermes-agent.desktop.enable = true;
  };
}
