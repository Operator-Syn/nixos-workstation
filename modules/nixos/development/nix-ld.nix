{pkgs, ...}: {
  # Allows vendor Linux binaries, such as the Claude Code VS Code extension,
  # to run on NixOS via the standard dynamic linker path.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      openssl
      curl
      libffi
      sqlite
      xorg.libX11
    ];
  };
}
