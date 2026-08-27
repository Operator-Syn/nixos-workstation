{pkgs}: let
  lib = pkgs.lib;
in rec {
  shellHook = ''
    if [[ $- == *i* ]]; then
      exec ${pkgs.fish}/bin/fish
    fi
  '';

  playwrightLibraries = with pkgs; [
    gtk3
    gtk4
    glib
    gdk-pixbuf
    pango
    cairo
    harfbuzz
    icu
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    mesa
    libdrm
    libxcb
    xorg.libX11
    xorg.libXdamage
    xorg.libXcomposite
    xorg.libXfixes
    xorg.libXrandr
    wayland
    libxkbcommon
    nss
    nspr
    alsa-lib
    cups
    dbus
    expat
    fontconfig
    freetype
    woff2
    lcms2
    libsecret
    libnotify
    libproxy
    libmanette
    libjpeg
    libpng
    libwebp
    libavif
    dav1d
  ];

  gstreamerPlugins = with pkgs; [
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
  ];

  nativeLibraries = with pkgs;
    [
      atk
      libffi
      libxml2
      libxslt
      openssl
      readline
      sqlite
      stdenv.cc.cc.lib
      zlib
    ]
    ++ playwrightLibraries;

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
    GST_PLUGIN_SYSTEM_PATH_1_0 =
      lib.makeSearchPath "lib/gstreamer-1.0" gstreamerPlugins;
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
