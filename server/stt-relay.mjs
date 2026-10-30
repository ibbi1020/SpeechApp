import { WebSocketServer, WebSocket } from "ws";
import { buildSttUpstreamURL } from "./stt-url.mjs";

export { buildSttUpstreamURL };

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
