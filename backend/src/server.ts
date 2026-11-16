import { createServer, IncomingMessage, ServerResponse } from "node:http";
import Anthropic from "@anthropic-ai/sdk";
import { Config, Deps, handleChat, makeAnthropicCaller } from "./chat.js";
import { RateLimiter } from "./rateLimit.js";

const MAX_BODY_BYTES = 64 * 1024;

function number(name: string, fallback: number): number {
  const value = Number(process.env[name]);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

export function loadConfig(): Config {
  return {
    appKey: process.env.APP_KEY?.trim() || null,
    perInstallPerHour: number("LIMIT_PER_INSTALL_HOUR", 12),
    perInstallPerDay: number("LIMIT_PER_INSTALL_DAY", 60),
    perIpPerHour: number("LIMIT_PER_IP_HOUR", 120),
  };
}

function send(res: ServerResponse, status: number, json: unknown, headers: Record<string, string> = {}) {
  res.writeHead(status, { "content-type": "application/json", "cache-control": "no-store", ...headers });
  res.end(JSON.stringify(json));
}

function readBody(req: IncomingMessage): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    req.on("data", (chunk: Buffer) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        // Stop buffering; the 413 is sent by the caller, which then closes the connection.
        if (chunks.length > 0) {
          chunks.length = 0;
          reject(Object.assign(new Error("Request too large."), { status: 413 }));
        }
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
      } catch {
        reject(Object.assign(new Error("Body must be valid JSON."), { status: 400 }));
      }
    });
    req.on("error", reject);
  });
}

export function createApp(deps: Deps) {
  return createServer(async (req, res) => {
    try {
      const url = new URL(req.url ?? "/", "http://localhost");

      if (req.method === "GET" && url.pathname === "/health") {
        return send(res, 200, { ok: true });
      }
      if (req.method !== "POST" || url.pathname !== "/chat") {
        return send(res, 404, { error: "Not found." });
      }

      const body = await readBody(req);
      const forwarded = req.headers["x-forwarded-for"];
      const ip = (typeof forwarded === "string" ? forwarded.split(",")[0]!.trim() : undefined) ?? req.socket.remoteAddress ?? "unknown";

      const output = await handleChat(
        {
          body,
          installId: header(req, "x-install-id"),
          appKey: header(req, "x-app-key"),
          ip,
        },
        deps,
      );
      return send(res, output.status, output.json, output.headers);
    } catch (error) {
      const status = (error as { status?: number }).status;
      if (status === 413) {
        res.once("finish", () => req.destroy());
        return send(res, 413, { error: (error as Error).message }, { connection: "close" });
      }
      if (status === 400) {
        return send(res, 400, { error: (error as Error).message });
      }
      // Don't log message contents, only what went wrong.
      if (error instanceof Anthropic.RateLimitError) {
        return send(res, 503, { error: "The coach is busy right now. Please try again in a minute." });
      }
      if (error instanceof Anthropic.AuthenticationError) {
        console.error("Anthropic authentication failed: check ANTHROPIC_API_KEY.");
        return send(res, 500, { error: "The coach isn't set up correctly on the server." });
      }
      if (error instanceof Anthropic.APIError) {
        console.error(`Anthropic API error ${error.status}: ${error.message}`);
        return send(res, 502, { error: "The coach couldn't answer right now. Please try again." });
      }
      console.error("Unexpected error:", error instanceof Error ? error.message : error);
      return send(res, 500, { error: "Something went wrong." });
    }
  });
}

function header(req: IncomingMessage, name: string): string | undefined {
  const value = req.headers[name];
  return typeof value === "string" ? value : undefined;
}

// Start listening when run directly (not when imported by tests).
if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  const model = process.env.MODEL?.trim() || "claude-opus-5-5";
  const config = loadConfig();
  const limiter = new RateLimiter();
  setInterval(() => limiter.sweep(24 * 60 * 60 * 1000), 60 * 60 * 1000).unref();

  if (!process.env.ANTHROPIC_API_KEY) console.warn("ANTHROPIC_API_KEY is not set; chat requests will fail.");
  if (!config.appKey) console.warn("APP_KEY is not set; anyone who finds this URL can use your coach.");

  const app = createApp({ callModel: makeAnthropicCaller(model), limiter, config });
  app.requestTimeout = 180_000;
  const port = Number(process.env.PORT) || 8787;
  app.listen(port, () => console.log(`Coach backend listening on :${port} using ${model}`));
}
