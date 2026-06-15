{pkgs}: let
  common = import ./common.nix {inherit pkgs;};
in
  pkgs.mkShell {
    name = "dalanpad";
    shellHook = common.makeShellHook "dalanpad";

    nativeBuildInputs = with pkgs; [
      bun
      nodejs_24
      pkg-config
      cargo
      rustc
      rustfmt
      clippy
    ];

    buildInputs = with pkgs; [
      zlib
      glib
      cairo
      pango
      harfbuzz
      fribidi
      atk
      gdk-pixbuf
      gtk3
      webkitgtk_4_1
      libsoup_3
      libappindicator-gtk3
      librsvg
      openssl
    ] ++ (with pkgs.gst_all_1; [
      gstreamer
      gst-plugins-base
      gst-plugins-good
      gst-plugins-bad
      gst-plugins-ugly
      gst-libav
      gst-vaapi
    ]);
  }
