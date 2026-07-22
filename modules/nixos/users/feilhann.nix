{pkgs, ...}: {
  users.groups.feilhann = {};

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

  users.groups."hermes-projects-write" = {
    members = ["feilhann"];
  };

  users.groups."feilhann-home-admin" = {
    members = ["yashindo"];
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
    "d /home/feilhann 0770 feilhann feilhann - -"
    "L+ /home/feilhann/.gitconfig - - - - ${pkgs.writeText "gitconfig" ''
      [safe]
        directory = /home/yashindo/Git/Github/arithmetic-server-assignment
        directory = /home/yashindo/Git/Github/Bai-Group-of-Companies---Landing-Page
        directory = /home/yashindo/Git/Github/Bai-HR
        directory = /home/yashindo/Git/Github/BAI-Website
        directory = /home/yashindo/Git/Github/camping-tweaks
        directory = /home/yashindo/Git/Github/cert-manager
        directory = /home/yashindo/Git/Github/copies
        directory = /home/yashindo/Git/Github/csc133-research-paper
        directory = /home/yashindo/Git/Github/Dalanpad
        directory = /home/yashindo/Git/Github/drafts
        directory = /home/yashindo/Git/Github/featquantum
        directory = /home/yashindo/Git/Github/icehrm
        directory = /home/yashindo/Git/Github/Jupyter-notebook-template
        directory = /home/yashindo/Git/Github/operator-eury-dashboard
        directory = /home/yashindo/Git/Github/operator-synaciel
        directory = /home/yashindo/Git/Github/operator-syn-latex
        directory = /home/yashindo/Git/Github/sblc-lms
        directory = /home/yashindo/Git/Github/sir-alquine-notebook
        directory = /home/yashindo/Git/Github/syngrid
        directory = /home/yashindo/Git/Github/workers-ai
        directory = /home/yashindo/Git/Github/xqubit-project
        directory = /home/yashindo/Git/Automation
        directory = /home/yashindo/nix-config
    ''}"
    "Z /home/yashindo/Git - - hermes-projects-write - -"
  ];
}
