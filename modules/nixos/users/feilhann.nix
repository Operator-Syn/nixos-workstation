{ pkgs, ... }:
{
  users.groups.feilhann = { };

  users.groups."hermes-audit-readonly" = {
    members = [
      "feilhann"
      "yashindo"
    ];
  };

  users.groups."hermes-desktop" = {
    members = [
      "feilhann"
      "yashindo"
    ];
  };

  users.users.feilhann = {
    isNormalUser = true;
    description = "Feilhann";
    group = "feilhann";
    home = "/home/feilhann";
    createHome = true;
    shell = pkgs.bashInteractive;
    hashedPassword = "!";
  };

  systemd.tmpfiles.rules = [
    "d /home/feilhann 0700 feilhann feilhann - -"
  ];

}
