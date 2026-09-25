import { createServer } from "node:http";

export function monthKey(ms = Date.now()) {
  const d = new Date(ms);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}

export function decideStart(st, month) {
  const count = st.month === month ? st.count : 0;
  if (count >= 20) return { allow: false, reason: "budget" };
  return { allow: true, nextCount: count + 1 };
}

const accounts = new Map(); // uuid -> { month, count, concurrent, mintTimes: number[], started: Set, possibleMinor: string|null }
let crisisCount = 0;
const RATE_WINDOW_MS = 10 * 60 * 1000;

function account(id) {
  if (!accounts.has(id)) accounts.set(id, { month: "", count: 0, concurrent: 0, mintTimes: [], started: new Set(), possibleMinor: null });
  return accounts.get(id);
}

export async function handleRequest(req, res, now = Date.now(), openaiFetch = fetch) {
  const url = new URL(req.url, "http://localhost");
  const uuid = (req.headers.authorization || "").replace(/^Bearer\s+/i, "");
  if (url.pathname === "/v1/conversation/crisis" && req.method === "POST") {
    crisisCount += 1;
    res.writeHead(204);
    res.end();
    return;
  }
  if (!uuid) {
    res.writeHead(401);
    res.end(JSON.stringify({ error: "auth" }));
    return;
  }
  const st = account(uuid);
  const month = monthKey(now);
  if (url.pathname === "/v1/conversation/possible-minor" && req.method === "POST") {
    st.possibleMinor = new Date(now).toISOString().slice(0, 10);
    res.writeHead(204);
    res.end();
    return;
  }
  if (url.pathname === "/v1/conversation/ended" && req.method === "POST") {
    st.concurrent = Math.max(0, st.concurrent - 1);
    res.writeHead(204);
    res.end();
    return;
  }
  if (url.pathname === "/v1/conversation/started" && req.method === "POST") {
    const body = await readJson(req);
    const sid = body.session_id;
    if (!st.started.has(sid)) {
      const d = decideStart(st, month);
      if (!d.allow) {
        res.writeHead(429);
        res.end(JSON.stringify({ error: d.reason }));
        return;
      }
      st.month = month;
      st.count = d.nextCount;
      st.started.add(sid);
    }
    res.writeHead(200);
    res.end(JSON.stringify({ starts_remaining: 20 - st.count }));
    return;
  }
  if (url.pathname === "/v1/conversation/mint" && req.method === "POST") {
    if ((st.concurrent ?? 0) >= 1) {
      res.writeHead(429);
      res.end(JSON.stringify({ error: "concurrent" }));
      return;
    }
    st.mintTimes = st.mintTimes.filter((t) => now - t < RATE_WINDOW_MS);
    if (st.mintTimes.length >= 3) {
      res.writeHead(429);
      res.end(JSON.stringify({ error: "rate" }));
      return;
    }
    const d = decideStart(st, month);
    if (!d.allow) {
      res.writeHead(429);
      res.end(JSON.stringify({ error: d.reason }));
      return;
    }
    st.mintTimes.push(now);
    let r;
    let json;
    try {
      r = await openaiFetch("https://api.openai.com/v1/realtime/client_secrets", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          session: {
            type: "realtime",
            model: "gpt-realtime-2.1-mini",
            tools: [],
            tracing: null,
            audio: {
              input: {
                transcription: null,
                turn_detection: {
                  type: "semantic_vad",
                  eagerness: "low",
                  create_response: false,
                  interrupt_response: false,
                },
                noise_reduction: { type: "near_field" },
              },
            },
          },
          expires_after: { anchor: "created_at", seconds: 120 },
        }),
      });
      json = await r.json();
    } catch {
      res.writeHead(502);
      res.end(JSON.stringify({
        starts_remaining: 20 - (st.month === month ? st.count : 0),
      }));
      return;
    }
    if (r.ok) st.concurrent += 1;
    res.writeHead(r.ok ? 200 : 502);
    res.end(JSON.stringify({
      client_secret: json.value ?? json.client_secret ?? json,
      starts_remaining: 20 - (st.month === month ? st.count : 0),
    }));
    return;
  }
  res.writeHead(404);
  res.end();
}

function readJson(req) {
  return new Promise((resolve) => {
    let b = "";
    req.on("data", (c) => { b += c; });
    req.on("end", () => {
      try { resolve(JSON.parse(b || "{}")); } catch { resolve({}); }
    });
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  createServer((req, res) => handleRequest(req, res)).listen(process.env.PORT || 8787);
}
