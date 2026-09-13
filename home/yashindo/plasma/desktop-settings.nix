{pkgs, ...}: {
  programs.plasma = {
    # Disable KWin's blur effect while investigating offscreen framebuffer errors.
    kwin.effects.blur.enable = false;

    # Keep the CLI bridge available without hiding it from the taskbar. This
    # applies to the initial normal Obsidian window, including manual launches.
    window-rules = [
      {
        description = "Obsidian CLI bridge";
        match = {
          window-class = {
            value = "md.Obsidian";
            type = "exact";
          };
          window-types = ["normal"];
        };
        apply = {
          minimize = {
            value = true;
            apply = "initially";
          };
        };
      }
    ];

    hotkeys.commands.open-alacritty = {
      name = "Open Alacritty";
      comment = "Open Alacritty";
      key = "Ctrl+Shift+X";
      command = "${pkgs.alacritty-graphics}/bin/alacritty";
    };
  };
}
