{
  config,
  lib,
  pkgs,
  ...
}: {
  options.modules.layan.enable = lib.mkEnableOption "Layan Window Decorations";

  config = lib.mkIf config.modules.layan.enable {
    # No package needed — Aurorae is part of KWin

    # Install the theme files (read-only symlinks are fine here,
    # KDE only reads theme dirs, it doesn't write back to them)
    home.file.".local/share/aurorae/themes/Layan".source = ./Layan/themes/Layan;
    home.file.".local/share/aurorae/themes/Layan-light".source = ./Layan/themes/Layan-light;
    home.file.".local/share/aurorae/themes/Layan-solid".source = ./Layan/themes/Layan-solid;

    # Tell KWin to actually use the Layan theme
    home.activation.setLayanDecoration = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 \
        --file kwinrc \
        --group org.kde.kdecoration2 \
        --key library "org.kde.kwin.aurorae"
      ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 \
        --file kwinrc \
        --group org.kde.kdecoration2 \
        --key theme "__aurorae__svg__Layan"
    '';
  };
}
