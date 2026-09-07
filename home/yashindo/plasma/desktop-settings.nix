{pkgs, ...}: {
  programs.plasma = {
    # Disable KWin's blur effect while investigating offscreen framebuffer errors.
    kwin.effects.blur.enable = false;

    hotkeys.commands.open-alacritty = {
      name = "Open Alacritty";
      comment = "Open Alacritty";
      key = "Ctrl+Shift+X";
      command = "${pkgs.alacritty-graphics}/bin/alacritty";
    };
  };
}
