{pkgs, ...}: {
  programs.fish.enable = true;

  users.users.yashindo = {
    isNormalUser = true;
    description = "John-Ronan";
    shell = pkgs.fish;
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
      "gamemode"
      "kvm"
      "libvirtd"
    ];
  };
}
