import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { handleWorker, memoryStore } from "./worker.mjs";

function call({ method, path, uuid, body, store, apiKey = "xai-test", xaiFetch, now }) {
  const headers = new Headers();
  if (uuid) headers.set("authorization", `Bearer ${uuid}`);
  if (body) headers.set("content-type", "application/json");
  const request = new Request(`https://mint.test${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  return handleWorker(request, { store, apiKey, xaiFetch, now });
}

function okXai() {
  return async () => ({
    ok: true,
    status: 200,
    json: async () => ({ value: "ek_test" }),
    text: async () => "",
  });
}

test("mint returns a short-lived secret and blocks a second one", async () => {
  const store = memoryStore();
  const uuid = randomUUID();
  const now = Date.parse("2026-10-28T12:00:00Z");
  const first = await call({
    method: "POST",
    path: "/v1/conversation/mint",
    uuid,
    body: {},
    store,
    xaiFetch: okXai(),
    now,
  });
  assert.equal(first.status, 200);
  assert.deepEqual(await first.json(), { client_secret: "ek_test", starts_remaining: 20 });
  const second = await call({
    method: "POST",
    path: "/v1/conversation/mint",
    uuid,
    body: {},
    store,
    xaiFetch: okXai(),
    now: now + 1000,
  });
  assert.equal(second.status, 429);
  assert.equal((await second.json()).error, "concurrent");
});

test("ending the conversation allows another mint", async () => {
  const store = memoryStore();
  const uuid = randomUUID();
  const now = Date.parse("2026-10-28T12:00:00Z");
  await call({ method: "POST", path: "/v1/conversation/mint", uuid, body: {}, store, xaiFetch: okXai(), now });
  const ended = await call({ method: "POST", path: "/v1/conversation/ended", uuid, store, now });
  assert.equal(ended.status, 204);
  const again = await call({
    method: "POST",
    path: "/v1/conversation/mint",
    uuid,
    body: {},
    store,
    xaiFetch: okXai(),
    now: now + 1000,
  });
  assert.equal(again.status, 200);
});

test("the same session id does not consume a second start", async () => {
  const store = memoryStore();
  const uuid = randomUUID();
  const session_id = randomUUID();
  const now = Date.parse("2026-10-28T12:00:00Z");
  const first = await call({
    method: "POST",
    path: "/v1/conversation/started",
    uuid,
    body: { session_id },
    store,
    now,
  });
  const second = await call({
    method: "POST",
    path: "/v1/conversation/started",
    uuid,
    body: { session_id },
    store,
    now,
  });
  assert.equal(first.status, 200);
  assert.equal((await first.json()).starts_remaining, 19);
  assert.equal((await second.json()).starts_remaining, 19);
});

test("fourth mint inside ten minutes is refused", async () => {
  const store = memoryStore();
  const uuid = randomUUID();
  let now = Date.parse("2026-10-28T12:00:00Z");
  for (let i = 0; i < 3; i += 1) {
    const minted = await call({
      method: "POST",
      path: "/v1/conversation/mint",
      uuid,
      body: {},
      store,
      xaiFetch: okXai(),
      now,
    });
    assert.equal(minted.status, 200);
    await call({ method: "POST", path: "/v1/conversation/ended", uuid, store, now });
    now += 1000;
  }
  const blocked = await call({
    method: "POST",
    path: "/v1/conversation/mint",
    uuid,
    body: {},
    store,
    xaiFetch: okXai(),
    now,
  });
  assert.equal(blocked.status, 429);
  assert.equal((await blocked.json()).error, "rate");
});

test("a possible-minor flag blocks mint and crisis needs no account", async () => {
  const store = memoryStore();
  const uuid = randomUUID();
  const now = Date.parse("2026-10-28T12:00:00Z");
  const flagged = await call({
    method: "POST",
    path: "/v1/conversation/possible-minor",
    uuid,
    store,
    now,
  });
  assert.equal(flagged.status, 204);
  const minted = await call({
    method: "POST",
    path: "/v1/conversation/mint",
    uuid,
    body: {},
    store,
    xaiFetch: okXai(),
    now,
  });
  assert.equal(minted.status, 403);
  const crisis = await call({ method: "POST", path: "/v1/conversation/crisis", store, now });
  assert.equal(crisis.status, 204);
});

test("speech relay and voice list refuse to run without the server key", async () => {
  const store = memoryStore();
  const uuid = randomUUID();
  const voices = await call({
    method: "GET",
    path: "/v1/tts/voices",
    uuid,
    store,
    apiKey: "",
  });
  assert.equal(voices.status, 503);
  const socket = new Request("https://mint.test/v1/stt", {
    headers: { upgrade: "websocket", authorization: `Bearer ${uuid}` },
  });
  const relay = await handleWorker(socket, { store, apiKey: "" });
  assert.equal(relay.status, 503);
});
