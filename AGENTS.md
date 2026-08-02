## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

Nix-config rules:
- Use Graphify for read-only discovery and relationship questions only.
- Treat the Nix source, `nix flake check`, and the project Nix-config MCP as authoritative over graph results.
- Use the project Nix-config MCP for patches, flake validation, and one-file commits; Graphify must not be used for mutations.
- Never index or disclose `secrets/`, `.sops.yaml`, `.codex/`, or other paths excluded by `.graphifyignore`.
- Run Graphify through Pipenv so the project lockfile, not a global Python installation, controls its version.

Documentation rules:
- Treat live Nix source, flake outputs, package scripts, and the Project MCP implementation as authoritative over README and guide text.
- When a change adds, removes, renames, or changes the behavior of a module, helper, service, dev shell, MCP tool, or protected boundary, update the nearest relevant Markdown documentation in the same change.
- Before a documentation maintenance change, run the repository documentation audit and inspect the affected source files; do not rely on filenames or old documentation alone.
- Keep operational claims specific about whether an action is read-only, preparatory, approval-gated, user-owned, or live-system verification.
- Do not document secrets, private keys, credential values, or protected vault contents. Refer to their declared paths and authority boundaries only.
- After documentation changes, rerun the documentation audit and the relevant repository checks. A documentation audit passing does not replace flake or test verification when source files were also changed.
