import { WebSocketServer, WebSocket } from "ws";

const STT_MODEL = "grok-voice-transcribe-2.0";

/**
 * Upstream URL is built here so the phone cannot pick the model or the host.
 * `keyterm` values are copied through, capped at 100 terms of 50 characters.
 */
export function buildSttUpstreamURL(incomingSearch = "") {
  const incoming = new URLSearchParams(incomingSearch);
  const query = new URLSearchParams({
    model: STT_MODEL,
    sample_rate: "16000",
    encoding: "pcm",
    interim_results: "true",
    smart_turn: "0.7",
    smart_turn_timeout: "3000",
    // Keep uh/um/er in text and words so review markers can timestamp them.
    filler_words: "true",
  });
  const terms = incoming
    .getAll("keyterm")
    .map((term) => term.trim().slice(0, 50))
    .filter(Boolean)
    .slice(0, 100);
  for (const term of terms) query.append("keyterm", term);
  return `wss://api.x.ai/v1/stt?${query}`;
}

export function attachSttRelay(server, { apiKey = process.env.XAI_API_KEY } = {}) {
  const wss = new WebSocketServer({ noServer: true });

  server.on("upgrade", (req, socket, head) => {
    let url;
    try {
      url = new URL(req.url, "http://localhost");
    } catch {
      socket.destroy();
      return;
    }
    if (url.pathname !== "/v1/stt") {
      socket.destroy();
      return;
    }
    const uuid = (req.headers.authorization || "").replace(/^Bearer\s+/i, "");
    if (!uuid) {
      socket.write("HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n");
      socket.destroy();
      return;
    }
    if (!apiKey) {
      socket.write("HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\n\r\n");
      socket.destroy();
      return;
    }

    wss.handleUpgrade(req, socket, head, (client) => {
      const upstream = new WebSocket(buildSttUpstreamURL(url.search), {
        headers: { Authorization: `Bearer ${apiKey}` },
      });
      let closed = false;
      const end = () => {
        if (closed) return;
        closed = true;
        client.close();
        upstream.close();
      };
      upstream.on("message", (data, isBinary) => {
        if (client.readyState !== WebSocket.OPEN) return;
        client.send(isBinary ? data : data.toString());
      });
      client.on("message", (data, isBinary) => {
        if (upstream.readyState === WebSocket.OPEN) {
          upstream.send(data, { binary: isBinary });
        }
      });
      upstream.on("close", end);
      upstream.on("error", end);
      client.on("close", end);
      client.on("error", end);
    });
  });
}
