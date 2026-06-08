{pkgs, ...}: {
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs;
    [
      #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
      #  wget
      kdePackages.plasma-browser-integration
      kdePackages.kconfig # provides kwriteconfig6
      kdePackages.kcoreaddons # often needed for KDE CLI utils
      kdePackages.qttools # provides qdbus (sometimes qdbus6)
      kdePackages.breeze
      kdePackages.aurorae
      kdePackages.kdecoration
      docker-compose
      nil
      easyeffects
      pavucontrol
      alejandra
      gamemode
      kdePackages.polkit-kde-agent-1
      nixfmt-rfc-style
      git
      tree
    ]
    ++ (import ../modules/scripts.nix {inherit pkgs;});
}
