{pkgs}: let
  common = import ./common.nix {inherit pkgs;};
in
  pkgs.mkShell (common.playwrightEnv
    // {
      shellHook = common.shellHook;
      packages = [pkgs.playwright-driver.browsers];
    })
