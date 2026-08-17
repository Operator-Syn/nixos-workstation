{pkgs}: {
  default = import ./default-shell.nix {inherit pkgs;};
  python = import ./python.nix {inherit pkgs;};
  node = import ./node.nix {inherit pkgs;};
  python-node = import ./python-node.nix {inherit pkgs;};
  playwright = import ./playwright.nix {inherit pkgs;};
  python-playwright = import ./python-playwright.nix {inherit pkgs;};
  cuda = import ./cuda.nix {inherit pkgs;};
  latex = import ./latex.nix {inherit pkgs;};
}
