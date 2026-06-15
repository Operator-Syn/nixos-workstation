{pkgs}: let
  common = import ./common.nix {inherit pkgs;};
in
  common.mkPythonShell (with pkgs; [
    cudaPackages.cudatoolkit
    openmpi
  ]) {}
