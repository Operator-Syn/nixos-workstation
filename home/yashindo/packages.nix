{
  pkgs,
  lib,
  ...
}: let
  # nixpkgs' `codex` builds from source and lags behind upstream's rapid
  # release cadence (needs newer librusty_v8/webrtc pins to bump). OpenAI
  # publishes prebuilt static musl binaries on npm under the main package
  # name with a platform-suffixed version, which is what editor extensions
  # (e.g. VS Code's ChatGPT extension) bundle. Use that directly instead.
  codex-bin = pkgs.stdenv.mkDerivation rec {
    pname = "codex";
    version = "0.144.1";

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@openai/codex/-/codex-${version}-linux-x64.tgz";
      hash = "sha256-4qZNQhwQqvC348DovXG3Hkl9dYIwAzGLZ0onjXGt0Mc=";
    };

    nativeBuildInputs = [pkgs.makeBinaryWrapper];

    unpackPhase = ''
      tar xzf $src
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 package/vendor/x86_64-unknown-linux-musl/bin/codex $out/bin/codex
      runHook postInstall
    '';

    postFixup = ''
      wrapProgram $out/bin/codex --prefix PATH : ${lib.makeBinPath [pkgs.ripgrep pkgs.bubblewrap]}
    '';

    meta = {
      description = "OpenAI Codex CLI (prebuilt static binary)";
      homepage = "https://github.com/openai/codex";
      license = lib.licenses.asl20;
      platforms = ["x86_64-linux"];
      mainProgram = "codex";
    };
  };
in {
  home.packages = with pkgs; [
    bat
    biome
    btop
    cudaPackages.cudatoolkit
    exfat
    fzf
    inkscape
    inter
    inter-nerdfont
    kdePackages.kdegraphics-thumbnailers
    kdePackages.kirigami
    kdePackages.kirigami-addons
    kdePackages.qwt
    lsd
    miracode
    nerd-fonts.fira-code
    nerd-fonts.fira-mono
    openmpi
    (python3.withPackages (pythonPackages: [
      pythonPackages.pytest
    ]))
    # pipenv
    claude-code
    codex-bin
    ripgrep
    vlc
    zoxide
    zoom-us
  ];
}
