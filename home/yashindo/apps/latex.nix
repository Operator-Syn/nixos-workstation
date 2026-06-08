{
  pkgs,
  lib,
  config,
  ...
}: {
  options.modules.latex.enable = lib.mkEnableOption "LaTeX";
  config = lib.mkIf config.modules.latex.enable {
    home.packages = with pkgs; [
      texlive.combined.scheme-full
    ];
  };
}
