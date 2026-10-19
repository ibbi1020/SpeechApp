import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { decideStart, handleRequest } from "./mint.mjs";

function mockReq({ method, path, uuid, body = {} }) {
  const payload = JSON.stringify(body);
  return {
    method,
    url: path,
    headers: { authorization: `Bearer ${uuid}` },
    on(ev, fn) {
      if (ev === "data") queueMicrotask(() => fn(payload));
      if (ev === "end") queueMicrotask(() => fn());
      return this;
    },
  };
}

function mockRes() {
  return {
    statusCode: 0,
    body: "",
    writeHead(code) { this.statusCode = code; },
    end(s = "") { this.body = s; },
  };
}

async function request(opts, { now = Date.now(), openaiFetch } = {}) {
  const req = mockReq(opts);
  const res = mockRes();
  await handleRequest(req, res, now, openaiFetch);
  return { status: res.statusCode, json: res.body ? JSON.parse(res.body) : null };
}

function okOpenAI() {
  return async () => ({ ok: true, json: async () => ({ value: "ek_test" }) });
}

function failOpenAI() {
  return async () => ({ ok: false, json: async () => ({ error: "upstream" }) });
}

test("20th start in a calendar month is allowed, 21st is not", () => {
  const month = "2026-09";
  const st = { month, count: 19, concurrent: 0 };
  const ok = decideStart(st, month, Date.parse("2026-09-21T12:00:00Z"));
  assert.equal(ok.allow, true);
  assert.equal(ok.nextCount, 20);
  const no = decideStart({ month, count: 20, concurrent: 0 }, month);
  assert.equal(no.allow, false);
  assert.equal(no.reason, "budget");
});

test("new calendar month resets", () => {
  const st = { month: "2026-08", count: 20, concurrent: 0 };
  const ok = decideStart(st, "2026-09");
  assert.equal(ok.allow, true);
  assert.equal(ok.nextCount, 1);
});

test("concurrent session blocked", async () => {
  const uuid = randomUUID();
  const now = Date.parse("2026-09-21T12:00:00Z");
  const first = await request(
    { method: "POST", path: "/v1/conversation/mint", uuid },
    { now, openaiFetch: okOpenAI() },
  );
  assert.equal(first.status, 200);
  const second = await request(
    { method: "POST", path: "/v1/conversation/mint", uuid },
    { now: now + 1000, openaiFetch: okOpenAI() },
  );
  assert.equal(second.status, 429);
  assert.equal(second.json.error, "concurrent");
});

test("mint then started with same session increments count", async () => {
  const uuid = randomUUID();
  const session_id = randomUUID();
  const now = Date.parse("2026-09-21T12:00:00Z");
  const minted = await request(
    { method: "POST", path: "/v1/conversation/mint", uuid },
    { now, openaiFetch: okOpenAI() },
  );
  assert.equal(minted.status, 200);
  const started = await request(
    { method: "POST", path: "/v1/conversation/started", uuid, body: { session_id } },
    { now },
  );
  assert.equal(started.status, 200);
  assert.equal(started.json.starts_remaining, 19);
});

test("second mint while first session concurrent is 429", async () => {
  const uuid = randomUUID();
  const now = Date.parse("2026-09-21T12:00:00Z");
  const first = await request(
    { method: "POST", path: "/v1/conversation/mint", uuid },
    { now, openaiFetch: okOpenAI() },
  );
  assert.equal(first.status, 200);
  const second = await request(
    { method: "POST", path: "/v1/conversation/mint", uuid },
    { now: now + 1000, openaiFetch: okOpenAI() },
  );
  assert.equal(second.status, 429);
  assert.equal(second.json.error, "concurrent");
});

test("mint requests a Grok ephemeral secret, not a GPT realtime session", async () => {
  const uuid = randomUUID();
  const now = Date.parse("2026-09-21T12:00:00Z");
  const previous = process.env.XAI_API_KEY;
  process.env.XAI_API_KEY = "xai-test-key";
  let called;
  try {
    const minted = await request(
      { method: "POST", path: "/v1/conversation/mint", uuid },
      {
        now,
        openaiFetch: async (url, init) => {
          called = { url, init };
          return { ok: true, json: async () => ({ value: "xai-realtime-client-secret-test" }) };
        },
      },
    );
    assert.equal(minted.status, 200);
    assert.equal(minted.json.client_secret, "xai-realtime-client-secret-test");
  } finally {
    if (previous === undefined) delete process.env.XAI_API_KEY;
    else process.env.XAI_API_KEY = previous;
  }
  assert.equal(called.url, "https://api.x.ai/v1/realtime/client_secrets");
  assert.equal(called.init.headers.Authorization, "Bearer xai-test-key");
  const body = JSON.parse(called.init.body);
  assert.deepEqual(body, { expires_after: { seconds: 120 } });
  assert.equal(body.session, undefined);
});

test("failed grok mint does not stick concurrent", async () => {
  const uuid = randomUUID();
  const now = Date.parse("2026-09-21T12:00:00Z");
  const failed = await request(
    { method: "POST", path: "/v1/conversation/mint", uuid },
    { now, openaiFetch: failOpenAI() },
  );
  assert.equal(failed.status, 502);
  const retry = await request(
    { method: "POST", path: "/v1/conversation/mint", uuid },
    { now: now + 1000, openaiFetch: okOpenAI() },
  );
  assert.equal(retry.status, 200);
});

test("thrown grok mint fetch returns 502 and does not stick concurrent", async () => {
  const uuid = randomUUID();
  const now = Date.parse("2026-09-21T12:00:00Z");
  const thrown = await request(
    { method: "POST", path: "/v1/conversation/mint", uuid },
    {
      now,
      openaiFetch: async () => {
        throw new Error("network");
      },
    },
  );
  assert.equal(thrown.status, 502);
  const retry = await request(
    { method: "POST", path: "/v1/conversation/mint", uuid },
    { now: now + 1000, openaiFetch: okOpenAI() },
  );
  assert.equal(retry.status, 200);
});

test("budget GET reports the count and mint does not consume a start", async () => {
  const uuid = randomUUID();
  const now = Date.parse("2026-09-21T12:00:00Z");
  const before = await request(
    { method: "GET", path: "/v1/conversation/budget", uuid },
    { now },
  );
  assert.equal(before.status, 200);
  assert.equal(before.json.used, 0);
  assert.equal(before.json.limit, 20);
  assert.equal(before.json.starts_remaining, 20);
  assert.equal(before.json.month, "2026-09");

  const minted = await request(
    { method: "POST", path: "/v1/conversation/mint", uuid },
    { now, openaiFetch: okOpenAI() },
  );
  assert.equal(minted.status, 200);
  const afterMint = await request(
    { method: "GET", path: "/v1/conversation/budget", uuid },
    { now },
  );
  assert.equal(afterMint.json.used, 0);

  const started = await request(
    {
      method: "POST",
      path: "/v1/conversation/started",
      uuid,
      body: { session_id: randomUUID() },
    },
    { now },
  );
  assert.equal(started.status, 200);
  const after = await request(
    { method: "GET", path: "/v1/conversation/budget", uuid },
    { now },
  );
  assert.equal(after.json.used, 1);
  assert.equal(after.json.starts_remaining, 19);
});

test("possible minor blocks the next mint and does not call xAI", async () => {
  const uuid = randomUUID();
  const now = Date.parse("2026-09-21T12:00:00Z");
  const flagged = await request(
    { method: "POST", path: "/v1/conversation/possible-minor", uuid },
    { now },
  );
  assert.equal(flagged.status, 204);
  const minted = await request(
    { method: "POST", path: "/v1/conversation/mint", uuid },
    {
      now: now + 1000,
      openaiFetch: async () => {
        throw new Error("xAI should not be called");
      },
    },
  );
  assert.equal(minted.status, 403);
  assert.equal(minted.json.error, "possible_minor");
});
