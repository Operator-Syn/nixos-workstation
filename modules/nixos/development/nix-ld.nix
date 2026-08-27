{pkgs, ...}: let
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
in {
  # Allows vendor Linux binaries, such as the Claude Code VS Code extension,
  # to run on NixOS via the standard dynamic linker path.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs;
      [
        stdenv.cc.cc.lib
        zlib
        openssl
        curl
        libffi
        sqlite
      ]
      ++ playwrightLibraries;
  };
}
