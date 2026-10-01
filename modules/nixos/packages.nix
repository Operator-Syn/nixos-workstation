{pkgs, ...}: let
  playwrightRuntimePackages = with pkgs; [
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
    libx11
    libxi
    libxtst
    libxdamage
    libxcomposite
    libxfixes
    libxrandr
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

  # Hermes Bot Screen detects host prerequisites by executable on PATH. The
  # gateway's distro installer does not support NixOS, so declare them here.
  hermesBotScreenPackages = with pkgs; [
    tigervnc
    xfwm4
    xfce4-panel
    xfdesktop
    xfce4-settings
    xfce4-terminal
    xauth
    xdpyinfo
    setxkbmap
    xprop
    xsetroot
    xset
  ];
in {
  imports = [
    ./scripts.nix
  ];

  environment.systemPackages = with pkgs;
    [
      docker-compose
      ffmpeg-full
      krita
      lmstudio
      git
      gnused
      nix
      ripgrep
      nil
      uv
      nodejs_24
      bun
      at-spi2-core
      pavucontrol
      qbittorrent
      kdePackages.kamoso
      zbar
      tcpdump
      tree
      openssl
      sqlite
      dmidecode
      wl-clipboard
      rustc
      cargo
      clippy
      rustfmt
      rust-analyzer

      kdePackages.partitionmanager
      kdePackages.kdecoration
    ]
    ++ playwrightRuntimePackages
    ++ hermesBotScreenPackages;
}
