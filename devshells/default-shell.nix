{pkgs}: let
  common = import ./common.nix {inherit pkgs;};
in
  pkgs.mkShell {
    shellHook = common.shellHook;
    packages = with pkgs; [
      alejandra
      cmake
      git
      libopenmpt
      nil
      ninja
      nixfmt
      pkg-config
      SDL2
      tree
    ];
  }
