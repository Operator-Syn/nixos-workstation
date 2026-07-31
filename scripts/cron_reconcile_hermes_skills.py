#!/usr/bin/env python3
"""Cron entrypoint for the Hermes skill-vault reconciler."""

from __future__ import annotations

from reconcile_hermes_skills import main


if __name__ == "__main__":
    raise SystemExit(main(["--reconcile", "--apply"]))
