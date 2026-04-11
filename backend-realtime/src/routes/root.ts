import type { FastifyInstance } from "fastify";

export const registerRootRoute = async (app: FastifyInstance): Promise<void> => {
  app.get("/", async (request, reply) => {
    const acceptHeader = request.headers.accept ?? "";
    const prefersHtml = typeof acceptHeader === "string" && acceptHeader.includes("text/html");

    const payload = {
      ok: true,
      service: "conductor-backend",
      status: "online",
      endpoints: {
        health: "/health",
        wsHarness: "/ws/harness",
        wsDevice: "/ws/device/:hashedId",
        lightingState: "/lighting/state",
        lightingStream: "/lighting/stream",
        lightingEngineer: "/lighting/engineer",
        audioState: "/audio/state",
        audioStream: "/audio/stream"
      }
    };

    if (!prefersHtml) {
      return payload;
    }

    reply.type("text/html; charset=utf-8");
    return `
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Conductor Backend</title>
    <style>
      :root { color-scheme: dark; }
      body {
        margin: 0;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
        background: #0a1220;
        color: #d4e7ff;
      }
      main {
        max-width: 840px;
        margin: 0 auto;
        padding: 40px 24px;
      }
      h1 {
        margin: 0 0 8px;
        font-size: 24px;
      }
      p {
        margin: 0 0 20px;
        color: #9db5d4;
      }
      ul {
        margin: 0;
        padding-left: 18px;
      }
      li {
        margin: 8px 0;
      }
      a {
        color: #7dd3fc;
        text-decoration: none;
      }
      a:hover {
        text-decoration: underline;
      }
      code {
        color: #f0f6ff;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>Conductor Backend Online</h1>
      <p>Use one of these endpoints for health, websocket, and operator telemetry.</p>
      <ul>
        <li><a href="/health"><code>/health</code></a></li>
        <li><a href="/lighting/engineer"><code>/lighting/engineer</code></a></li>
        <li><a href="/lighting/state"><code>/lighting/state</code></a></li>
        <li><a href="/audio/state"><code>/audio/state</code></a></li>
        <li><a href="/audio/stream"><code>/audio/stream</code></a></li>
      </ul>
    </main>
  </body>
</html>`;
  });
};
