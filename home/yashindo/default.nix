{inputs, ...}: {
  imports = [
    inputs.plasma-manager.homeModules.plasma-manager
    inputs.sops-nix.homeManagerModules.sops
    ./apps
    ./packages.nix
    ./plasma
  ];

  home = {
    username = "yashindo";
    homeDirectory = "/home/yashindo";
    stateVersion = "25.11";
  };

  programs.home-manager.enable = true;
}
