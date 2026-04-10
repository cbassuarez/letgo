import type { LightingStatePayload } from "@conductor/protocol";
import type { FastifyInstance } from "fastify";

interface LightingRouteDependencies {
  field: {
    snapshot(): LightingStatePayload;
    subscribe(listener: (payload: LightingStatePayload) => void): () => void;
  };
}

export const registerLightingRoutes = async (
  app: FastifyInstance,
  deps: LightingRouteDependencies
): Promise<void> => {
  app.get("/lighting/state", async () => ({
    state: deps.field.snapshot()
  }));

  app.get("/lighting/stream", async (request, reply) => {
    reply.hijack();
    reply.raw.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no"
    });

    const writeEvent = (event: string, payload: unknown): void => {
      reply.raw.write(`event: ${event}\n`);
      reply.raw.write(`data: ${JSON.stringify(payload)}\n\n`);
    };

    writeEvent("state", deps.field.snapshot());
    const unsubscribe = deps.field.subscribe((payload) => {
      writeEvent("state", payload);
    });

    const heartbeat = setInterval(() => {
      reply.raw.write(": ping\n\n");
    }, 15_000);

    request.raw.on("close", () => {
      clearInterval(heartbeat);
      unsubscribe();
      reply.raw.end();
    });

    request.raw.on("error", () => {
      clearInterval(heartbeat);
      unsubscribe();
      reply.raw.end();
    });
  });

  app.get("/lighting/engineer", async (_request, reply) => {
    reply.type("text/html").send(engineerPageHTML);
  });
};

const engineerPageHTML = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>LetGo Lighting Engineer Feed</title>
    <style>
      :root {
        --bg: #060f1d;
        --panel: #0d1c31;
        --line: #2d4868;
        --ink: #d8e9ff;
        --muted: #8ea5c2;
        --go: #8af4a2;
        --caution: #ffda84;
        --hold: #ff9191;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        background: radial-gradient(circle at 15% 12%, #153253 0%, var(--bg) 50%);
        color: var(--ink);
        font-family: "Public Sans", "Inter", system-ui, sans-serif;
      }
      .wrap { max-width: 1200px; margin: 24px auto; padding: 0 18px 28px; }
      h1 { margin: 0; font-size: 28px; letter-spacing: 0.06em; text-transform: uppercase; }
      .sub { margin-top: 6px; color: var(--muted); font-size: 13px; letter-spacing: 0.08em; text-transform: uppercase; }
      .status-strip {
        margin-top: 18px;
        display: flex;
        gap: 14px;
        flex-wrap: wrap;
      }
      .pill {
        border: 1px solid var(--line);
        background: rgba(11, 27, 47, 0.7);
        padding: 7px 12px;
        border-radius: 999px;
        font-size: 12px;
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }
      .grid {
        margin-top: 16px;
        display: grid;
        grid-template-columns: 1.1fr 1fr;
        gap: 14px;
      }
      .panel {
        border: 1px solid var(--line);
        background: rgba(9, 21, 37, 0.76);
        border-radius: 10px;
        padding: 14px;
      }
      .kicker {
        color: var(--muted);
        font-size: 11px;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        margin-bottom: 8px;
      }
      .swatch {
        height: 220px;
        border-radius: 8px;
        border: 1px solid rgba(222, 242, 255, 0.35);
        box-shadow: inset 0 0 0 1px rgba(255,255,255,0.08);
      }
      .directive {
        margin-top: 10px;
        font-size: 32px;
        font-weight: 800;
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }
      .directive.go { color: var(--go); }
      .directive.caution { color: var(--caution); }
      .directive.hold { color: var(--hold); }
      .meta-row {
        display: grid;
        grid-template-columns: 130px 1fr;
        gap: 8px;
        margin: 6px 0;
        font-size: 13px;
      }
      .meta-row .label { color: var(--muted); text-transform: uppercase; letter-spacing: 0.07em; }
      .zone-grid {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        gap: 8px;
      }
      .zone-cell {
        border: 1px solid rgba(215, 236, 255, 0.18);
        border-radius: 8px;
        overflow: hidden;
        background: rgba(12, 29, 48, 0.9);
      }
      .zone-color {
        height: 54px;
        border-bottom: 1px solid rgba(222, 242, 255, 0.15);
      }
      .zone-meta {
        padding: 6px 7px 7px;
        font-size: 11px;
        line-height: 1.35;
        color: #bdd8ef;
      }
      .trend-line {
        height: 86px;
        border: 1px solid rgba(215, 236, 255, 0.18);
        border-radius: 8px;
        padding: 8px;
        overflow: hidden;
      }
      .trend-track {
        display: flex;
        align-items: flex-end;
        gap: 3px;
        height: 100%;
      }
      .trend-bar {
        width: 8px;
        border-radius: 3px 3px 0 0;
        background: linear-gradient(180deg, #7fd6ff, #2f88be);
      }
      @media (max-width: 980px) {
        .grid { grid-template-columns: 1fr; }
      }
    </style>
  </head>
  <body>
    <div class="wrap">
      <h1>Lighting Engineer Feed</h1>
      <div class="sub">Crowd color consensus map · manual-follow output</div>

      <div class="status-strip">
        <div class="pill">stream <span id="stream-state">connecting</span></div>
        <div class="pill">participants <span id="participants">0</span></div>
        <div class="pill">confidence <span id="confidence">0.00</span></div>
        <div class="pill">entropy <span id="entropy">0.00</span></div>
        <div class="pill">stability <span id="stability">0.00</span></div>
      </div>

      <div class="grid">
        <section class="panel">
          <div class="kicker">Target Color Now</div>
          <div class="swatch" id="swatch"></div>
          <div id="directive" class="directive hold">HOLD</div>
          <div class="meta-row"><div class="label">HEX</div><div id="meta-hex">#000000</div></div>
          <div class="meta-row"><div class="label">OKLCH</div><div id="meta-oklch">L0.00 C0.00 H0</div></div>
        </section>

        <section class="panel">
          <div class="kicker">Hall Map</div>
          <div class="zone-grid" id="zone-grid"></div>
          <div class="kicker" style="margin-top: 12px;">Confidence Trend</div>
          <div class="trend-line"><div id="trend-track" class="trend-track"></div></div>
        </section>
      </div>
    </div>

    <script>
      const stateUrl = "/lighting/state";
      const streamUrl = "/lighting/stream";
      const trend = [];

      const streamStateEl = document.getElementById("stream-state");
      const participantsEl = document.getElementById("participants");
      const confidenceEl = document.getElementById("confidence");
      const entropyEl = document.getElementById("entropy");
      const stabilityEl = document.getElementById("stability");
      const swatchEl = document.getElementById("swatch");
      const directiveEl = document.getElementById("directive");
      const hexEl = document.getElementById("meta-hex");
      const oklchEl = document.getElementById("meta-oklch");
      const zoneGridEl = document.getElementById("zone-grid");
      const trendTrackEl = document.getElementById("trend-track");

      function setStreamState(value) {
        streamStateEl.textContent = value;
      }

      function renderTrend(confidence) {
        trend.push(confidence);
        while (trend.length > 90) trend.shift();
        trendTrackEl.innerHTML = "";
        trend.forEach((value) => {
          const bar = document.createElement("div");
          bar.className = "trend-bar";
          bar.style.height = Math.max(6, Math.round(value * 68)) + "px";
          trendTrackEl.appendChild(bar);
        });
      }

      function renderState(payload) {
        participantsEl.textContent = String(payload.participantCount ?? 0);
        confidenceEl.textContent = Number(payload.confidence ?? 0).toFixed(2);
        entropyEl.textContent = Number(payload.entropy ?? 0).toFixed(2);
        stabilityEl.textContent = Number(payload.stability ?? 0).toFixed(2);

        const target = payload.targetColor || { hex: "#000000", oklch: { l: 0, c: 0, h: 0 } };
        swatchEl.style.background = target.hex;
        hexEl.textContent = target.hex;
        oklchEl.textContent = "L" + Number(target.oklch?.l ?? 0).toFixed(2)
          + " C" + Number(target.oklch?.c ?? 0).toFixed(2)
          + " H" + Math.round(Number(target.oklch?.h ?? 0));

        const trend = String(payload.trend || "hold").toLowerCase();
        directiveEl.textContent = trend.toUpperCase();
        directiveEl.className = "directive " + (trend === "go" ? "go" : trend === "caution" ? "caution" : "hold");

        zoneGridEl.innerHTML = "";
        const zones = Array.isArray(payload.zoneField) ? payload.zoneField : [];
        zones.forEach((zone) => {
          const cell = document.createElement("div");
          cell.className = "zone-cell";

          const color = document.createElement("div");
          color.className = "zone-color";
          color.style.background = zone.targetColor?.hex || "#223344";
          cell.appendChild(color);

          const meta = document.createElement("div");
          meta.className = "zone-meta";
          meta.textContent =
            (zone.id || "zone")
            + " · dens " + Number(zone.participantDensity ?? 0).toFixed(2)
            + " · conf " + Number(zone.confidence ?? 0).toFixed(2);
          cell.appendChild(meta);

          zoneGridEl.appendChild(cell);
        });

        renderTrend(Number(payload.confidence ?? 0));
      }

      async function loadInitial() {
        try {
          const res = await fetch(stateUrl, { cache: "no-store" });
          const json = await res.json();
          renderState(json.state || {});
        } catch {
          setStreamState("error");
        }
      }

      function connectStream() {
        const es = new EventSource(streamUrl);
        setStreamState("connecting");

        es.onopen = () => setStreamState("online");
        es.onerror = () => setStreamState("reconnecting");
        es.addEventListener("state", (event) => {
          try {
            const payload = JSON.parse(event.data);
            renderState(payload);
          } catch {
            // ignore malformed packet
          }
        });
      }

      loadInitial();
      connectStream();
    </script>
  </body>
</html>`;
