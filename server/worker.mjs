import { decideStart, freshMintTimes, monthKey } from "./mint-logic.mjs";
import { buildSttUpstreamURL } from "./stt-url.mjs";

function bearer(request) {
  return (request.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
}

function json(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function empty(status) {
  return new Response(null, { status });
}

function remaining(row, month) {
  const count = row.month === month ? row.count : 0;
  return 20 - count;
}

export function memoryStore() {
  const accounts = new Map();
  const started = new Set();
  let crisis = 0;

  function row(id) {
    if (!accounts.has(id)) {
      accounts.set(id, {
        month: "",
        count: 0,
        concurrent: 0,
        possibleMinor: null,
        mintTimes: [],
      });
    }
    return accounts.get(id);
  }

  return {
    async ensure(id) {
      const st = row(id);
      return {
        month: st.month,
        count: st.count,
        concurrent: st.concurrent,
        possibleMinor: st.possibleMinor,
        mintTimes: st.mintTimes.slice(),
      };
    },
    async setPossibleMinor(id, day) {
      row(id).possibleMinor = day;
    },
    async claimMint(id, expected, mintTimes) {
      const st = row(id);
      if (
        st.concurrent !== expected.concurrent
        || st.count !== expected.count
        || st.month !== expected.month
        || st.possibleMinor
        || st.concurrent >= 1
      ) {
        return false;
      }
      st.mintTimes = mintTimes;
      st.concurrent += 1;
      return true;
    },
    async releaseMint(id) {
      const st = row(id);
      st.concurrent = Math.max(0, st.concurrent - 1);
    },
    async hasStarted(id, sessionId) {
      return started.has(`${id}\0${sessionId}`);
    },
    async markStarted(id, sessionId, expected, next) {
      const key = `${id}\0${sessionId}`;
      if (started.has(key)) return { already: true };
      const st = row(id);
      if (st.month !== expected.month || st.count !== expected.count) return { conflict: true };
      st.month = next.month;
      st.count = next.count;
      started.add(key);
      return { ok: true };
    },
    async bumpCrisis() {
      crisis += 1;
    },
  };
}

export function d1Store(db) {
  return {
    async ensure(id) {
      await db
        .prepare("INSERT INTO prototype_accounts (id) VALUES (?) ON CONFLICT(id) DO NOTHING")
        .bind(id)
        .run();
      const row = await db
        .prepare(
          "SELECT month, count, concurrent, possible_minor, mint_times FROM prototype_accounts WHERE id = ?",
        )
        .bind(id)
        .first();
      return {
        month: row.month,
        count: row.count,
        concurrent: row.concurrent,
        possibleMinor: row.possible_minor,
        mintTimes: JSON.parse(row.mint_times || "[]"),
      };
    },
    async setPossibleMinor(id, day) {
      await db
        .prepare("INSERT INTO prototype_accounts (id) VALUES (?) ON CONFLICT(id) DO NOTHING")
        .bind(id)
        .run();
      await db
        .prepare("UPDATE prototype_accounts SET possible_minor = ? WHERE id = ?")
        .bind(day, id)
        .run();
    },
    async claimMint(id, expected, mintTimes) {
      const result = await db
        .prepare(
          `UPDATE prototype_accounts
           SET concurrent = concurrent + 1, mint_times = ?1
           WHERE id = ?2
             AND concurrent = ?3
             AND count = ?4
             AND month = ?5
             AND possible_minor IS NULL
             AND concurrent < 1`,
        )
        .bind(JSON.stringify(mintTimes), id, expected.concurrent, expected.count, expected.month)
        .run();
      return result.meta.changes === 1;
    },
    async releaseMint(id) {
      await db
        .prepare(
          "UPDATE prototype_accounts SET concurrent = CASE WHEN concurrent > 0 THEN concurrent - 1 ELSE 0 END WHERE id = ?",
        )
        .bind(id)
        .run();
    },
    async hasStarted(id, sessionId) {
      const row = await db
        .prepare(
          "SELECT 1 AS hit FROM prototype_started WHERE account_id = ? AND session_id = ?",
        )
        .bind(id, sessionId)
        .first();
      return Boolean(row);
    },
    async markStarted(id, sessionId, expected, next) {
      const inserted = await db
        .prepare(
          "INSERT INTO prototype_started (account_id, session_id) VALUES (?, ?) ON CONFLICT DO NOTHING",
        )
        .bind(id, sessionId)
        .run();
      if (inserted.meta.changes === 0) return { already: true };
      const updated = await db
        .prepare(
          "UPDATE prototype_accounts SET month = ?1, count = ?2 WHERE id = ?3 AND month = ?4 AND count = ?5",
        )
        .bind(next.month, next.count, id, expected.month, expected.count)
        .run();
      if (updated.meta.changes === 0) {
        await db
          .prepare("DELETE FROM prototype_started WHERE account_id = ? AND session_id = ?")
          .bind(id, sessionId)
          .run();
        return { conflict: true };
      }
      return { ok: true };
    },
    async bumpCrisis() {
      await db
        .prepare("UPDATE prototype_crisis SET count = count + 1 WHERE id = 1")
        .run();
    },
  };
}

async function readJson(request) {
  try {
    return await request.json();
  } catch {
    return {};
  }
}

export async function handleWorker(request, { store, apiKey, xaiFetch = fetch, now = Date.now() }) {
  const url = new URL(request.url);
  if (url.pathname === "/v1/stt") {
    return relayStt(request, url, apiKey);
  }
  if (url.pathname === "/v1/conversation/crisis" && request.method === "POST") {
    await store.bumpCrisis();
    return empty(204);
  }

  const uuid = bearer(request);
  if (!uuid) return json({ error: "auth" }, 401);

  if (url.pathname === "/v1/tts/voices" && request.method === "GET") {
    return proxyVoices(apiKey, xaiFetch);
  }

  const month = monthKey(now);
  if (url.pathname === "/v1/conversation/budget" && request.method === "GET") {
    const row = await store.ensure(uuid);
    const count = row.month === month ? row.count : 0;
    return json({ used: count, limit: 20, starts_remaining: 20 - count, month }, 200);
  }
  if (url.pathname === "/v1/conversation/possible-minor" && request.method === "POST") {
    await store.setPossibleMinor(uuid, new Date(now).toISOString().slice(0, 10));
    return empty(204);
  }
  if (url.pathname === "/v1/conversation/ended" && request.method === "POST") {
    await store.ensure(uuid);
    await store.releaseMint(uuid);
    return empty(204);
  }
  if (url.pathname === "/v1/conversation/started" && request.method === "POST") {
    const body = await readJson(request);
    const sessionId = String(body.session_id ?? "");
    const row = await store.ensure(uuid);
    if (await store.hasStarted(uuid, sessionId)) {
      return json({ starts_remaining: remaining(row, month) }, 200);
    }
    const decision = decideStart(row, month);
    if (!decision.allow) return json({ error: decision.reason }, 429);
    const marked = await store.markStarted(
      uuid,
      sessionId,
      { month: row.month, count: row.count },
      { month, count: decision.nextCount },
    );
    if (marked.conflict) return json({ error: "budget" }, 429);
    const after = marked.already ? row : { ...row, month, count: decision.nextCount };
    return json({ starts_remaining: remaining(after, month) }, 200);
  }
  if (url.pathname === "/v1/conversation/mint" && request.method === "POST") {
    const row = await store.ensure(uuid);
    if (row.possibleMinor) return json({ error: "possible_minor" }, 403);
    if (row.concurrent >= 1) return json({ error: "concurrent" }, 429);
    const times = freshMintTimes(row.mintTimes, now);
    if (times.length >= 3) return json({ error: "rate" }, 429);
    const decision = decideStart({ ...row, mintTimes: times }, month);
    if (!decision.allow) return json({ error: decision.reason }, 429);
    if (!apiKey) return json({ starts_remaining: remaining(row, month) }, 502);
    const claimed = await store.claimMint(
      uuid,
      { month: row.month, count: row.count, concurrent: row.concurrent },
      times.concat(now),
    );
    if (!claimed) return json({ error: "concurrent" }, 429);
    let upstream;
    let body;
    try {
      upstream = await xaiFetch("https://api.x.ai/v1/realtime/client_secrets", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ expires_after: { seconds: 120 } }),
      });
      body = await upstream.json();
    } catch {
      await store.releaseMint(uuid);
      return json({ starts_remaining: remaining(row, month) }, 502);
    }
    if (!upstream.ok) {
      await store.releaseMint(uuid);
      return json({ starts_remaining: remaining(row, month) }, 502);
    }
    return json({
      client_secret: body.value ?? body.client_secret ?? body,
      starts_remaining: remaining(row, month),
    }, 200);
  }
  return empty(404);
}

async function proxyVoices(apiKey, xaiFetch) {
  if (!apiKey) return empty(503);
  const upstream = await xaiFetch("https://api.x.ai/v1/tts/voices", {
    headers: { Authorization: `Bearer ${apiKey}` },
  });
  const text = await upstream.text();
  return new Response(text, {
    status: upstream.status,
    headers: { "content-type": "application/json" },
  });
}

async function relayStt(request, url, apiKey) {
  if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
    return empty(426);
  }
  if (!bearer(request)) return empty(401);
  if (!apiKey) return empty(503);
  if (typeof WebSocketPair !== "function") return empty(501);

  const upstreamResponse = await fetch(buildSttUpstreamURL(url.search), {
    headers: {
      Upgrade: "websocket",
      Authorization: `Bearer ${apiKey}`,
    },
  });
  const upstream = upstreamResponse.webSocket;
  if (!upstream) return empty(502);
  upstream.accept();

  const pair = new WebSocketPair();
  const client = pair[0];
  const server = pair[1];
  server.accept();

  const closeBoth = () => {
    try { server.close(); } catch { /* already closed */ }
    try { upstream.close(); } catch { /* already closed */ }
  };
  server.addEventListener("message", (event) => {
    upstream.send(event.data);
  });
  upstream.addEventListener("message", (event) => {
    server.send(event.data);
  });
  server.addEventListener("close", closeBoth);
  upstream.addEventListener("close", closeBoth);
  server.addEventListener("error", closeBoth);
  upstream.addEventListener("error", closeBoth);

  return new Response(null, { status: 101, webSocket: client });
}

export default {
  async fetch(request, env) {
    return handleWorker(request, {
      store: d1Store(env.DB),
      apiKey: env.XAI_API_KEY,
    });
  },
};
