{pkgs}: let
  common = import ./common.nix {inherit pkgs;};
in
  pkgs.mkShell {
    shellHook = common.shellHook;
    packages = common.nodePackages;
  }
