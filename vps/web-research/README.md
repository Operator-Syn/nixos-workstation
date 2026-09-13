# VPN-only web research stack

This directory contains the public, secret-free Compose and SearXNG configuration for the node1 web-research stack.

- SearXNG provides JSON search for Hermes.
- Firecrawl provides markdown/HTML extraction and crawl APIs.
- Firecrawl MCP provides crawl, map, scrape, and optional structured JSON tools.
- The real `.env` is SOPS/age-encrypted on node1 and is never committed.

Node1 uses the Firecrawl source checkout at `v2.11.0` (`ef12eb3`) and MCP
checkout at `v3.2.1` (`d22f144`). The checkouts carry the small diagnostics
patch described in [`vps/docs/web-research-stack.md`](../docs/web-research-stack.md);
keep those revisions and local diffs together when upgrading.

Structured extraction is intentionally unavailable until an OpenAI-compatible or local model endpoint is explicitly configured in the encrypted environment. Self-hosting avoids vendor API quotas, but search engines and target websites can still throttle or block requests.

Run `DEPLOYMENT_REVISION=ef12eb3 node audit-search.mjs` from a VPN-connected machine to create a local JSONL evidence artifact. It records response shapes, statuses, provider attempts, result counts, diagnostics, fallback state, errors, and latency without writing secrets or raw query text. Set `AUDIT_OUTPUT` to a protected temporary path when retaining evidence.

Search diagnostics are additive and backward-compatible. An all-provider failure is an MCP tool error with an attempt summary; a SearXNG failure followed by a usable fallback is `partial`; no result is `empty`. Structured extraction is advertised by MCP but fails closed with `MODEL_PROVIDER_NOT_CONFIGURED` until `MODEL_NAME` and an OpenAI-compatible or local provider are intentionally configured in the encrypted environment.

The stack detects and reports upstream rate limits, CAPTCHA/anti-bot blocks, timeouts, network errors, and provider errors. It does not bypass CAPTCHA, spoof fingerprints, or use stealth scraping. Optional proxy variables are present for a later, explicitly approved and terms-compliant licensed proxy, but are unset by default.
