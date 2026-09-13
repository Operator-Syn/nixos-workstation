#!/usr/bin/env node

import { appendFileSync, mkdirSync } from "node:fs";
import { createHash } from "node:crypto";

const mcpUrl = process.env.FIRECRAWL_MCP_URL ?? "https://crawl-mcp.yashindo.syn-forge.com/mcp";
const searxUrl = process.env.SEARXNG_URL ?? "https://search.yashindo.syn-forge.com";
const revision = process.env.DEPLOYMENT_REVISION ?? "unknown";
const output = process.env.AUDIT_OUTPUT ?? `/tmp/web-research-audit-${Date.now()}.jsonl`;
mkdirSync("/tmp", { recursive: true });

function queryHash(query) {
  return createHash("sha256").update(query).digest("hex").slice(0, 16);
}

function ssePayload(text) {
  const line = text.split("\n").find((entry) => entry.startsWith("data: "));
  if (!line) return null;
  try {
    return JSON.parse(line.slice(6));
  } catch {
    return null;
  }
}

async function callMcp(name, args) {
  const started = Date.now();
  const response = await fetch(mcpUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
    body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method: "tools/call", params: { name, arguments: args } }),
  });
  const raw = await response.text();
  const payload = ssePayload(raw);
  const text = payload?.result?.content?.find((item) => item.type === "text")?.text ?? "";
  let parsed = null;
  try { parsed = JSON.parse(text); } catch { /* retain non-JSON tool output */ }
  const diagnostics = parsed?.diagnostics;
  const resultCount = diagnostics?.result_count ?? parsed?.web?.length ?? 0;
  return {
    endpoint: "firecrawl-mcp",
    tool: name,
    http_status: response.status,
    ok: response.ok && !payload?.result?.isError,
    elapsed_ms: Date.now() - started,
    result_count: resultCount,
    diagnostics: diagnostics ?? null,
    error: payload?.result?.isError ? text.slice(0, 500) : null,
  };
}

async function callSearx(query) {
  const started = Date.now();
  const url = new URL("/search", searxUrl);
  url.searchParams.set("q", query);
  url.searchParams.set("format", "json");
  const response = await fetch(url, { headers: { Accept: "application/json" } });
  const body = await response.json().catch(() => ({}));
  const unresponsive = Array.isArray(body.unresponsive_engines)
    ? body.unresponsive_engines.map(([provider, message]) => ({
        provider,
        status: /captcha|blocked|suspend|bot/i.test(String(message)) ? "anti_bot_blocked" : "provider_error",
        message: String(message).slice(0, 240),
      }))
    : [];
  return {
    endpoint: "searxng",
    http_status: response.status,
    ok: response.ok,
    elapsed_ms: Date.now() - started,
    result_count: Array.isArray(body.results) ? body.results.length : 0,
    provider_warnings: unresponsive,
    error: response.ok ? null : String(body.message ?? "request failed").slice(0, 500),
  };
}

const cases = [
  ["minimal", "Filipino NLP research gaps Tagalog Cebuano datasets", { query: "Filipino NLP research gaps Tagalog Cebuano datasets" }],
  ["explicit-source", "Filipino NLP research gaps Tagalog Cebuano datasets", { query: "Filipino NLP research gaps Tagalog Cebuano datasets", sources: [{ type: "web" }] }],
  ["limited", "ACL Anthology Filipino Tagalog Cebuano NLP", { query: "ACL Anthology Filipino Tagalog Cebuano NLP", limit: 5, sources: [{ type: "web" }] }],
  ["scrape-options", "Filipino NLP research gaps Tagalog Cebuano datasets", { query: "Filipino NLP research gaps Tagalog Cebuano datasets", limit: 3, sources: [{ type: "web" }], scrapeOptions: { formats: ["markdown"], onlyMainContent: true } }],
];

const records = [];
for (const [shape, query, args] of cases) {
  const result = await callMcp("firecrawl_search", args);
  records.push({ timestamp: new Date().toISOString(), revision, shape, query_hash: queryHash(query), ...result });
}
for (const query of ["Filipino NLP research gaps Tagalog Cebuano datasets", "OpenAI research"]) {
  records.push({ timestamp: new Date().toISOString(), revision, shape: "native-searxng", query_hash: queryHash(query), ...(await callSearx(query)) });
}
records.push({ timestamp: new Date().toISOString(), revision, shape: "known-url", ...(await callMcp("firecrawl_scrape", { url: "https://example.com", formats: ["markdown"] })) });
records.push({ timestamp: new Date().toISOString(), revision, shape: "acl-map", ...(await callMcp("firecrawl_map", { url: "https://aclanthology.org", limit: 20 })) });
records.push({ timestamp: new Date().toISOString(), revision, shape: "arxiv-map", ...(await callMcp("firecrawl_map", { url: "https://arxiv.org", search: "Filipino Tagalog Cebuano NLP", limit: 20 })) });

for (const record of records) appendFileSync(output, `${JSON.stringify(record)}\n`);
console.log(JSON.stringify({ output, records: records.length, revision }));
