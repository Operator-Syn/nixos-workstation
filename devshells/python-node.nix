{pkgs}: let
  common = import ./common.nix {inherit pkgs;};
in
  common.mkPythonShell common.nodePackages {}
