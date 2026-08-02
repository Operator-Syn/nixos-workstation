{pkgs, ...}: {
  programs.fish.enable = true;

  users.users.yashindo = {
    isNormalUser = true;
    uid = 1000;
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
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIBVknzlufRF7BJlPaATjBMyahWIWabgSsIVBkb6ElJq yashindo@hiraeth"
    ];
  };
}
