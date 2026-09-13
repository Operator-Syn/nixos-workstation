# VPS documentation

Public-safe operational notes for services hosted outside the NixOS `Hiraeth`
machine. These notes describe procedures and trust boundaries; they do not
contain private keys, tokens, generated passwords, or decrypted environment
files.

## Documents

| Document | Scope |
| --- | --- |
| [`infisical-sops-age.md`](infisical-sops-age.md) | SOPS/age-protected Infisical Compose deployment on `node1` |
| [`web-research-stack.md`](web-research-stack.md) | VPN-only SearXNG, Firecrawl, and Hermes MCP integration |

## Public-repository boundary

This repository is public. Never add any of the following here:

- an age private key or SSH private key;
- a plaintext `.env`, decrypted SOPS output, machine identity token, or
  Infisical bootstrap credential;
- a database dump, backup containing secrets, or copied `/etc` configuration;
- live host credentials or private authentication state.

It is safe to document variable names, file locations, permissions, redacted
examples, and commands that keep plaintext in a short-lived protected
temporary file. Encrypted material is still operationally sensitive: keep a
host-specific encrypted file outside this public checkout unless its recipient
set and recovery plan have been deliberately reviewed.
