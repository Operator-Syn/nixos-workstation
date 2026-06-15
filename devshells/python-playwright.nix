{pkgs}: let
  common = import ./common.nix {inherit pkgs;};
in
  common.mkPythonShell [pkgs.playwright-driver.browsers] common.playwrightEnv
