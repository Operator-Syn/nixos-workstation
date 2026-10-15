"""Bridge Mnemosyne's embedding selection from config into the environment.

Why this file exists
--------------------
``mnemosyne.core.embeddings`` reads ``MNEMOSYNE_EMBEDDING_MODEL`` and
``MNEMOSYNE_EMBEDDING_DIM`` **at import time** and freezes them into module
constants (``_DEFAULT_MODEL``, ``EMBEDDING_DIM``). Mnemosyne's own config loader
classifies those two keys as ``REQUIRES_RESTART`` — config.yaml changes "warn but
do not apply" — so the values written to Hermes config
(``memory.mnemosyne.embedding_model``) or to ``mnemosyne/config.yaml`` never reach
an imported module.

The provider then silently runs the package default (``BAAI/bge-small-en-v1.5``,
384-dim) whatever either config file says. When the sqlite-vec tables were built
at another dimension, every dense recall raises a dimension-mismatch error and
degrades to keyword search, and newly stored vectors land at the wrong dimension
— they cannot even be inserted into the vec table.

This module must therefore run **before the first** ``import mnemosyne``. Both
Hermes-side entry points load it by path, because either can be imported without
the other: the memory provider (``__init__.py``) and the CLI (``cli.py``).

Precedence: an already-set ``MNEMOSYNE_*`` env var always wins; otherwise Hermes
config (``memory.mnemosyne.<key>``) wins over ``mnemosyne/config.yaml``. A key
defined in neither source is left alone, so Mnemosyne's own defaults and normal
config precedence still apply.
"""

from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Any, Dict, List, Tuple

_LOGGER = logging.getLogger(__name__)

# config key -> environment variable name. Kept in sync with Mnemosyne's own
# ENV_VAR_MAP for the keys that are frozen at import time.
_BRIDGED_KEYS: Dict[str, str] = {
    "embedding_model": "MNEMOSYNE_EMBEDDING_MODEL",
    "embedding_dim": "MNEMOSYNE_EMBEDDING_DIM",
    "fastembed_cache_dir": "MNEMOSYNE_FASTEMBED_CACHE_DIR",
    "vec_type": "MNEMOSYNE_VEC_TYPE",
}


def _read_yaml_section(path: Path, prefix: Tuple[str, ...]) -> Dict[str, Any]:
    """Return a nested YAML mapping, or ``{}`` when the file/section is unusable."""
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        return {}
    try:
        import yaml

        data: Any = yaml.safe_load(text) or {}
    except Exception:
        return {}
    for part in prefix:
        if not isinstance(data, dict):
            return {}
        data = data.get(part) or {}
    return data if isinstance(data, dict) else {}


def apply() -> Dict[str, str]:
    """Copy embedding settings from config files into the process environment.

    Idempotent. Returns the environment variables it applied (diagnostics only;
    it never returns or logs a value that is not already operator-visible in a
    config file).
    """
    applied: Dict[str, str] = {}
    pending = {
        env_var: key
        for key, env_var in _BRIDGED_KEYS.items()
        if not os.environ.get(env_var)
    }
    if not pending:
        return applied

    home = Path(os.environ.get("HERMES_HOME") or (Path.home() / ".hermes"))
    sources: List[Tuple[Path, Tuple[str, ...]]] = [
        # Most specific first: the profile's own config, then the machine-wide
        # managed base that new profiles inherit from, then Mnemosyne's own
        # config (which may not exist until Mnemosyne first seeds it).
        (home / "config.yaml", ("memory", "mnemosyne")),
        (Path("/etc/hermes/config.yaml"), ("memory", "mnemosyne")),
        (home / "mnemosyne" / "config.yaml", ()),
    ]
    data_dir = os.environ.get("MNEMOSYNE_DATA_DIR")
    if data_dir:
        sources.append((Path(data_dir) / "config.yaml", ()))

    for path, prefix in sources:
        if not pending:
            break
        section = _read_yaml_section(path, prefix)
        for env_var, key in list(pending.items()):
            value = section.get(key)
            if value is None or value == "":
                continue
            os.environ[env_var] = str(value)
            applied[env_var] = str(value)
            pending.pop(env_var)

    if applied:
        _LOGGER.debug(
            "Mnemosyne: bridged embedding settings into the environment: %s",
            ", ".join(sorted(applied)),
        )
    return applied
