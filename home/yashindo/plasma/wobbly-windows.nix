{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.programs.wobbly-windows;
  kwriteconfig = "${pkgs.kdePackages.kconfig}/bin/kwriteconfig6";
in {
  options.programs.wobbly-windows = {
    enable = mkEnableOption "Enable Mac-like Wobbly Windows effect for KWin";
  };

  config = mkIf cfg.enable {
    home.activation.wobbleKwin = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${kwriteconfig} --file kwinrc --group Plugins --key wobblywindowsEnabled true
      ${kwriteconfig} --file kwinrc --group Effect-wobblywindows --key Stiffness 60
      ${kwriteconfig} --file kwinrc --group Effect-wobblywindows --key Drag 90
      ${kwriteconfig} --file kwinrc --group Effect-wobblywindows --key MoveFactor 10
    '';
  };
}
