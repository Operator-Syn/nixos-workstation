{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.modules.debian-container;
  homeDir = config.users.users.yashindo.home;

  debianImage = pkgs.dockerTools.pullImage {
    imageName = "debian";
    imageDigest = "sha256:85019db29298555fd1a5f4bb57673ae989414a9884117c75d7a3e1a6cce21688";
    sha256 = "sha256-xIHuI5031GdI7Wt9y9JTWdrx8ZeC4SFRjhjZrBqopdk=";
    finalImageName = "debian";
    finalImageTag = "bookworm";
  };

  dockerfile = pkgs.writeText "Dockerfile" ''
    FROM debian:bookworm
    RUN apt-get update && apt-get install -y \
      git \
      curl \
      wget \
      vim \
      build-essential \
      ca-certificates \
      libssl-dev \
      libffi-dev \
      libbz2-dev \
      libreadline-dev \
      libsqlite3-dev \
      zlib1g-dev \
      && apt-get clean \
      && rm -rf /var/lib/apt/lists/*

    RUN curl https://pyenv.run | bash
    ENV PYENV_ROOT="/root/.pyenv"
    ENV PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
    RUN pyenv install 3.14.0 && pyenv global 3.14.0

    RUN pip install pipenv
  '';

  # Run this manually once: build-debian-dev
  buildScript = pkgs.writeShellScriptBin "build-debian-dev" ''
    echo "Loading base image..."
    docker load < ${debianImage}
    echo "Building dev image..."
    docker build -t debian-dev:latest -f ${dockerfile} /
    echo "Done."
  '';
in {
  options.modules.debian-container.enable =
    lib.mkEnableOption "Debian dev container";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [buildScript];

    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers.debian-dev = {
      image = "debian-dev:latest";
      autoStart = true;

      volumes = [
        "${homeDir}:${homeDir}"
      ];

      cmd = ["sleep" "infinity"];

      environment = {
        TERM = "xterm-256color";
        LANG = "en_US.UTF-8";
      };
    };
  };
}
