{pkgs}: let
  common = import ./common.nix {inherit pkgs;};
in
  pkgs.mkShell {
    shellHook = common.shellHook;
    packages = with pkgs; [
      alejandra
      git
      nil
      nixfmt
      pkg-config
      tree
    ];
  }
