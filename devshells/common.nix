{pkgs}: let
  lib = pkgs.lib;
in rec {
  shellHook = ''exec ${pkgs.fish}/bin/fish'';

  makeShellHook = name: ''
    export name="${name}"
    exec ${pkgs.fish}/bin/fish
  '';

  nativeLibraries = with pkgs; [
    alsa-lib
    atk
    cups
    dbus
    expat
    glib
    libdrm
    libffi
    libxcb
    xorg.libX11
    libxkbcommon
    libxml2
    libxslt
    mesa
    nspr
    nss
    openssl
    readline
    sqlite
    stdenv.cc.cc.lib
    zlib
  ];

  pythonPackages = with pkgs; [
    gcc
    git
    gnumake
    pipenv
    pkg-config
    python314
  ];

  nodePackages = with pkgs; [
    bun
    nodejs_24
    pnpm
  ];

  playwrightEnv = {
    LD_LIBRARY_PATH = lib.makeLibraryPath nativeLibraries;
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
  };

  mkPythonShell = extraPackages: extraAttrs:
    pkgs.mkShell (extraAttrs
      // {
        packages = pythonPackages ++ extraPackages;
        LD_LIBRARY_PATH = lib.makeLibraryPath nativeLibraries;
        PIPENV_VENV_IN_PROJECT = "1";
        shellHook = shellHook;
      });
}
