{pkgs, ...}: {
  programs.plasma = {
    hotkeys.commands.open-alacritty = {
      name = "Open Alacritty";
      comment = "Open Alacritty";
      key = "Ctrl+Shift+T";
      command = "${pkgs.alacritty-graphics}/bin/alacritty";
    };
  };
}
