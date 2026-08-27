{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.modules.python-shell;
in {
  options.modules.python-shell.enable =
    lib.mkEnableOption "Python development shell";

  config = lib.mkIf cfg.enable {
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc.lib
        zlib
        openssl
        libffi
        libxml2
        libxslt
        sqlite
        readline
        openmpi
        glib
        nss
        nspr
        dbus
        atk
        cups
        libdrm
        mesa
        expat
        libxcb
        libxkbcommon
        alsa-lib
      ];
    };

    environment.systemPackages = with pkgs; [
      (python314.withPackages (ps: [
        ps.tkinter
      ]))
      pipenv
      gcc
      gnumake
      git
      pkg-config
      playwright-driver.browsers
    ];

    environment.variables = {
      # Native browser libraries and GStreamer plugins are supplied by the
      # project-scoped `python-playwright` dev shell. Keep only the browser
      # bundle location globally available for projects that opt into it.
      PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
      PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    };
  };
}
