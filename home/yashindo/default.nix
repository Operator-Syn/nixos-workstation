{
  inputs,
  pkgs,
  ...
}: let
  # The locked sops-nix source requires Go 1.26 while stable nixpkgs keeps
  # its default Go/buildGoModule at 1.25. Keep the newer builder local to sops.
  sopsPkgs = pkgs.extend (_: prev: {
    buildGoModule = prev.buildGo126Module;
    go = prev.go_1_26;
  });
  sopsPackage = (sopsPkgs.callPackage inputs.sops-nix {pkgs = sopsPkgs;}).sops-install-secrets;
in {
  imports = [
    inputs.hermes-agent.homeManagerModules.default
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

  sops.package = sopsPackage;

  # Nix places Buildx in the Docker plugin closure, while this pinned
  # docker-compose release still searches the user plugin directory directly.
  # Keep the plugin visible there so Compose's Bake path can discover it.
  home.file.".docker/cli-plugins/docker-buildx".source = "${pkgs.docker-buildx}/libexec/docker/cli-plugins/docker-buildx";

  programs.home-manager.enable = true;
}
