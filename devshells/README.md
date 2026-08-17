# Dev Shells

Reusable project environments exposed through `flake.nix` as `devShells`.

These shells let projects opt into the tools they need without making the whole system carry every language runtime, compiler, browser bundle, or CUDA package globally.

---

## Shell Catalog

| Shell | Use For | Includes |
| --- | --- | --- |
| `default` | Nix config work | `git`, `nil`, formatters, basic tools |
| `python` | Python projects | Python, Pipenv, compiler/native build support |
| `node` | npm/pnpm/bun projects | Node.js, pnpm, bun |
| `python-node` | Node projects with native builds | Node plus Python/compiler tooling |
| `playwright` | Browser automation only | Playwright browser bundle and env vars |
| `python-playwright` | Python projects using Playwright | Python shell plus Playwright browser setup |
| `cuda` | CUDA/ML experiments | Python, CUDA toolkit, OpenMPI |
| `latex` | TeX documents | Full TeX Live scheme |

Node and Python are intentionally project-scoped here instead of being installed as global Home Manager packages.

## Quick Start

Enter a shell manually:

```sh
nix develop ~/nix-config#node
```

Use a combined shell when dependencies overlap:

```sh
nix develop ~/nix-config#python-playwright
```

For Dalanpad's native Tauri dependencies, use Dalanpad's project-local flake
from the Dalanpad repository:

```sh
cd /path/to/Dalanpad
direnv allow
nix develop .#dalanpad
```

Noninteractive commands can use the same environment directly:

```sh
nix develop .#dalanpad --command cargo check --manifest-path src-tauri/Cargo.toml
```

## direnv Recipes

For automatic activation in an npm project:

```sh
use flake ~/nix-config#node
```

For a Python project that imports Playwright:

```sh
use flake ~/nix-config#python-playwright
```

Then allow it once from the project directory:

```sh
direnv allow
```

## Composition Model

The shells are built from shared package groups in `devshells/default.nix`.

```text
nativeLibraries
pythonPackages
nodePackages
playwrightEnv
```

That means shells can be combined without copying long package lists everywhere.

## Editing Guidelines

- Add shared groups when several shells need the same tools.
- Add named shells for common project shapes.
- Prefer `python-playwright` over asking each Python project to discover browser paths manually.
- Keep Dalanpad's GTK/WebKitGTK native build shell in the Dalanpad repository rather than adding those development packages globally.
- Prefer dev shells over adding project-specific tools to global Home Manager packages.
- Use the Debian Distrobox for dirty dependency experiments that should persist outside a single project shell.
