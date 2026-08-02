{
  config,
  lib,
  pkgs,
  ...
}: {
  home.activation.hermesTerminalShell = lib.hm.dag.entryAfter ["writeBoundary"] ''
    config_file="${config.home.homeDirectory}/.hermes/config.yaml"
    ${pkgs.coreutils}/bin/mkdir -p "${config.home.homeDirectory}/.hermes"

    ${pkgs.python3}/bin/python3 - "$config_file" <<'PY'
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text() if path.exists() else ""
text = original
lines = text.splitlines(keepends=True)
newline = chr(10)
indent_chars = " " + chr(9)

terminal_index = next(
    (
        index
        for index, line in enumerate(lines)
        if line == line.lstrip(indent_chars) and line.startswith("terminal:")
    ),
    None,
)

if terminal_index is None:
    if text and not text.endswith((chr(10), chr(13))):
        text += newline
    updated = text + f"terminal:{newline}  backend: local{newline}  shell: /bin/bash{newline}"
else:
    def block_end_for(items, start):
        for index in range(start + 1, len(items)):
            line = items[index]
            if line.strip() and line[:1] not in indent_chars + "#":
                return index
        return len(items)

    def set_terminal_key(items, start, key, value):
        end = block_end_for(items, start)
        key_index = next(
            (
                index
                for index in range(start + 1, end)
                if items[index].lstrip(indent_chars).startswith(f"{key}:")
            ),
            None,
        )

        if key_index is None:
            items.insert(start + 1, f"  {key}: {value}{newline}")
        else:
            line = items[key_index]
            line_indent = line[: len(line) - len(line.lstrip(indent_chars))]
            line_newline = newline if line.endswith(newline) else ""
            items[key_index] = f"{line_indent}{key}: {value}{line_newline}"

    set_terminal_key(lines, terminal_index, "backend", "local")
    set_terminal_key(lines, terminal_index, "shell", "/bin/bash")
    updated = "".join(lines)

if updated != original:
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(
        dir=path.parent,
        prefix=".config.yaml.",
        text=True,
    )
    try:
        with os.fdopen(descriptor, "w") as handle:
            handle.write(updated)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
PY
  '';
}
