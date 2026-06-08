{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.programs.magic-lamp;
  kwriteconfig = "${pkgs.kdePackages.kconfig}/bin/kwriteconfig6";
in {
  options.programs.magic-lamp = {
    enable = mkEnableOption "Enable Magic Lamp minimize effect for KWin";
  };

  config = mkIf cfg.enable {
    home.activation.magicLampKwin = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${kwriteconfig} --file kwinrc --group Plugins --key magiclampEnabled true
    '';
  };
}
