# Dev Shells

Reusable project environments exposed through `flake.nix` as `devShells`.

These shells let projects opt into the tools they need without making every project carry every language runtime, compiler, browser bundle, or CUDA package. The Playwright shells provide native runtime libraries and keep the Nix `playwright-driver.browsers` package available for explicit/manual workflows, but they do not set `PLAYWRIGHT_BROWSERS_PATH`; each project owns browser installation and location so it can select a matching Playwright revision.

---

## Shell Catalog

| Shell | Use For | Includes |
| --- | --- | --- |
| `default` | Nix config work | `git`, `nil`, formatters, basic tools |
| `python` | Python projects | Python, Pipenv, compiler/native build support |
| `node` | npm/pnpm/bun projects | Node.js, pnpm, bun |
| `python-node` | Node projects with native builds | Node plus Python/compiler tooling |
| `playwright` | Browser automation only | Playwright runtime libraries and Nix browser bundle |
| `python-playwright` | Python projects using Playwright | Python shell, runtime libraries, and Nix browser bundle |
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

## Browser Ownership

The `playwright` and `python-playwright` shells keep `playwright-driver.browsers` in their package sets for Nix-managed workflows, but intentionally leave `PLAYWRIGHT_BROWSERS_PATH` unset. They retain `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` so dependency installation does not implicitly download a browser. Project-local setup must explicitly install/select the browser revision and location matching its Playwright package. This configuration change does not install a browser.

## Composition Model

The shells are built from shared package groups in `devshells/default.nix`.

```text
nativeLibraries
pythonPackages
nodePackages
playwrightEnv
```

`playwrightEnv` provides the native library path, GStreamer plugin path, and explicit browser-download policy used by both Playwright shells. It deliberately does not choose a browser path.

That means shells can be combined without copying long package lists everywhere.

## Editing Guidelines

- Add shared groups when several shells need the same tools.
- Add named shells for common project shapes.
- Prefer `python-playwright` for shared native Playwright runtime dependencies; let each project choose its matching browser location.
- Keep Dalanpad's GTK/WebKitGTK native build shell in the Dalanpad repository rather than adding those development packages globally.
- Prefer dev shells over adding project-specific tools to global Home Manager packages.
- Use the Debian Distrobox for dirty dependency experiments that should persist outside a single project shell.
