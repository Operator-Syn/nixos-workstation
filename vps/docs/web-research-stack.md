# VPN-only SearXNG and Firecrawl

The VPS web-research stack lives at `/home/yashindo/docker-compose/web-research/` on `node1`.

## Services

- SearXNG (`search.yashindo.syn-forge.com`) provides JSON search for Hermes.
- Firecrawl (`crawl.yashindo.syn-forge.com`) provides markdown/HTML scraping and crawling.
- Firecrawl MCP (`crawl-mcp.yashindo.syn-forge.com`) provides MCP crawl, map, scrape, and extraction tools.

All names resolve through the NetBird Custom Zone to node1's VPN addresses. Nginx allows only the NetBird IPv4/IPv6 ranges; dependency containers have no published host ports.

## Secrets and structured extraction

The real environment is the SOPS/age-encrypted file on node1, `.env.sops.env`. It is not committed to this public repository. Use the existing node-local age identity to run Compose through `sops exec-env`; never print the decrypted environment.

Markdown/HTML scraping works without a model provider. Structured JSON extraction is intentionally inactive while `OPENAI_BASE_URL`, `OPENAI_API_KEY`, and `MODEL_NAME` (or a local compatible provider such as `OLLAMA_BASE_URL`) are unset. Configure those values only through the encrypted environment and test against a non-sensitive page. Native Hermes extraction remains markdown/HTML; structured JSON is exposed through Firecrawl MCP.

Self-hosting removes vendor API quotas, but upstream search engines and target websites can still throttle, CAPTCHA, or block requests. Keep the SearXNG limiter and the low concurrency defaults enabled.

## Transparent failures and research diagnostics

Firecrawl search responses retain the existing `web`, `images`, and `news` fields and add `diagnostics`. The diagnostic status is one of `success`, `partial`, `empty`, or `failed`; each provider attempt records a safe classification such as `rate_limited`, `anti_bot_blocked`, `timeout`, `network_error`, `provider_error`, or `empty`, plus HTTP status, retryability, retry count, result count, and latency where available. Provider errors are no longer collapsed to `{}`. The MCP search tool forwards this object and marks an all-provider failure as an MCP tool error.

The internal SearXNG limiter trusts only loopback forwarding proxies and pass-lists the exact Compose subnet (`172.28.0.0/16`) alongside the NetBird IPv4/IPv6 ranges. This avoids treating Firecrawl's header-less internal request as an untrusted forwarded client while retaining the VPN boundary at Nginx.

The default SearXNG profile prioritizes `arxiv`, `crossref`, `openalex`, `semantic scholar`, `pubmed`, `github`, `bing`, `brave`, and `duckduckgo`. Academic APIs and domain-restricted searches are preferred for paper-novelty work; general engines remain subject to their own throttling and CAPTCHA policies.

Run the dependency-free audit harness only while connected to NetBird:

```sh
DEPLOYMENT_REVISION=ef12eb3 AUDIT_OUTPUT=/tmp/web-research-audit.jsonl node /home/yashindo/docker-compose/web-research/audit-search.mjs
```

It stores hashed queries (not raw query text), response classifications, attempts, fallback use, errors, result counts, latency, and revision in a local JSONL file. Keep raw responses and sensitive research questions outside this public repository.

CAPTCHA bypass, stealth/fingerprint spoofing, and unauthorized proxy evasion are not enabled. A blocked provider is reported explicitly; compliant alternatives are bounded retries, official academic APIs/public mirrors, normal browser behavior, and an intentionally configured licensed proxy. `PROXY_SERVER`, `PROXY_USERNAME`, and `PROXY_PASSWORD` are encrypted optional settings and remain unset initially.

## Hermes configuration

Hermes' provider and MCP settings remain imperative in `~/.hermes/config.yaml` and its private environment:

```yaml
web:
  search_backend: searxng
  extract_backend: firecrawl
```

Set `SEARXNG_URL` and `FIRECRAWL_API_URL` to the VPN HTTPS names, add the Firecrawl MCP HTTP endpoint, then restart Hermes. Confirm tools with `hermes tools list`.

## Maintenance and rollback

Run `docker compose config` and health checks through SOPS before starting or updating the stack. Back up the Compose file before changing Infisical networks or Nginx. To roll back web search/extraction, remove the imperative backend overrides and return Hermes to its managed `nous` backend; keep the persistent volumes until the rollback is verified.

The initial workload guardrails are two workers, two concurrent crawl requests/jobs, browser pool size two, API limit 3 CPU/4 GiB, Playwright limit 2 CPU/2 GiB, and `MAX_CPU`/`MAX_RAM` admission thresholds of 0.75. RabbitMQ now has a persistent volume. The public helper `vps/web-research/backup-web-research.sh` backs up Firecrawl PostgreSQL, Redis RDB state, and RabbitMQ definitions to a mode-700 directory and retains 14 days; node1 runs it from a user systemd timer. `monitor-web-research.sh` runs every 15 minutes, logging low disk, restart, and OOM conditions to the journal; inspect with `journalctl --user -u web-research-monitor.service`. Per-client authentication remains a separate operator follow-up; VPN ACLs are the active outer authentication boundary. Do not enable Firecrawl database authentication by setting one variable alone.

The Nginx helper is `vps/web-research/install-nginx.sh`; run it on node1 from a sudo-capable shell so the password is entered locally. Add A and AAAA records for `search`, `crawl`, and `crawl-mcp` in the NetBird Custom Zone, pointing to node1's VPN addresses, before testing the HTTPS names.
