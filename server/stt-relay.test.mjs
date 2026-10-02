import { test } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { WebSocket } from "ws";
import { attachSttRelay, buildSttUpstreamURL } from "./stt-relay.mjs";

test("upstream pins the current STT model and copies keyterms", () => {
  const url = new URL(buildSttUpstreamURL("?model=evil&keyterm=ship&keyterm=sheep"));
  assert.equal(url.origin + url.pathname, "wss://api.x.ai/v1/stt");
  assert.equal(url.searchParams.get("model"), "grok-voice-transcribe-2.0");
  assert.deepEqual(url.searchParams.getAll("keyterm"), ["ship", "sheep"]);
  assert.equal(url.searchParams.get("sample_rate"), "16000");
  assert.equal(url.searchParams.get("encoding"), "pcm");
  assert.equal(url.searchParams.get("interim_results"), "true");
  assert.equal(url.searchParams.get("smart_turn"), "0.7");
});

test("keyterms are trimmed, capped, and blank ones dropped", () => {
  const long = "a".repeat(80);
  const params = new URLSearchParams();
  params.append("keyterm", `  ${long}  `);
  params.append("keyterm", "   ");
  for (let i = 0; i < 120; i += 1) params.append("keyterm", `w${i}`);
  const url = new URL(buildSttUpstreamURL(`?${params}`));
  const terms = url.searchParams.getAll("keyterm");
  assert.equal(terms[0].length, 50);
  assert.equal(terms.length, 100);
  assert.equal(terms.includes(""), false);
});

test("relay rejects a socket with no account or no API key", async () => {
  const server = createServer();
  attachSttRelay(server, { apiKey: "" });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  try {
    await expectUpgradeStatus(port, undefined, 401);
    await expectUpgradeStatus(port, "Bearer account-1", 503);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

function expectUpgradeStatus(port, authorization, status) {
  return new Promise((resolve, reject) => {
    const headers = authorization ? { Authorization: authorization } : undefined;
    const ws = new WebSocket(`ws://127.0.0.1:${port}/v1/stt`, { headers });
    ws.on("unexpected-response", (_req, res) => {
      assert.equal(res.statusCode, status);
      res.resume();
      resolve();
    });
    ws.on("open", () => reject(new Error("socket opened")));
    ws.on("error", () => {});
  });
}
