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
      # Keep package-install browser downloads disabled so project-local setup
      # can explicitly install/select a matching browser revision and location.
      # The Nix browser bundle remains available as a package for workflows that
      # intentionally use it; no browser path is exported globally.
      PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    };
  };
}
