import assert from "node:assert/strict";
import { AddressInfo } from "node:net";
import { describe, it } from "node:test";
import { Config, Deps, ModelCall, ModelResult, handleChat } from "../src/chat.js";
import { RateLimiter } from "../src/rateLimit.js";
import { createApp } from "../src/server.js";
import { RequestError, parseChatRequest, sanitizePlan } from "../src/validate.js";

const INSTALL = "3f2504e0-4f89-11d3-9a0c-0305e82c3301";
const config: Config = { appKey: "secret", perInstallPerHour: 3, perInstallPerDay: 10, perIpPerHour: 100 };

function deps(result: Partial<ModelResult> = {}, calls: ModelCall[] = []): Deps {
  return {
    config,
    limiter: new RateLimiter(),
    callModel: async (call) => {
      calls.push(call);
      return { stopReason: "end_turn", text: "Hello!", planInput: null, usage: { inputTokens: 1, outputTokens: 1 }, ...result };
    },
  };
}

const goodBody = { messages: [{ role: "user", content: "Build me a bench plan" }], context: { units: { weight: "kg" } } };
const input = (body: unknown = goodBody, extra = {}) => ({ body, installId: INSTALL, appKey: "secret", ip: "1.2.3.4", ...extra });

const validPlan = {
  title: "8-week bench builder",
  goal: "Add 10 kg to bench",
  summary: "Heavy and light days.",
  weeks: 8,
  sessions: [
    { week: 1, day: 1, title: "Heavy bench", type: "strength", durationMinutes: 60,
      exercises: [{ name: "Bench Press (Barbell)", sets: 5, reps: "5", percentOfOneRepMax: 80 }] },
  ],
};

describe("parseChatRequest", () => {
  it("accepts a normal request", () => {
    const parsed = parseChatRequest(goodBody);
    assert.equal(parsed.messages.length, 1);
    assert.deepEqual(parsed.context, { units: { weight: "kg" } });
  });

  it("rejects bad shapes", () => {
    assert.throws(() => parseChatRequest(null), RequestError);
    assert.throws(() => parseChatRequest({ messages: [] }), RequestError);
    assert.throws(() => parseChatRequest({ messages: [{ role: "system", content: "x" }] }), RequestError);
    assert.throws(() => parseChatRequest({ messages: [{ role: "user", content: 5 }] }), RequestError);
    assert.throws(() => parseChatRequest({ messages: [{ role: "assistant", content: "hi" }] }), RequestError);
    assert.throws(() => parseChatRequest({ messages: [{ role: "user", content: "x".repeat(7000) }] }), RequestError);
    assert.throws(() => parseChatRequest({ ...goodBody, context: "nope" }), RequestError);
    assert.throws(() => parseChatRequest({ ...goodBody, context: { blob: "x".repeat(20000) } }), RequestError);
  });

  it("starts with a user turn and keeps only the latest messages", () => {
    const messages = [{ role: "assistant", content: "stale" }];
    for (let i = 0; i < 40; i++) messages.push({ role: i % 2 === 0 ? "user" : "assistant", content: `m${i}` });
    messages.push({ role: "user", content: "last" });
    const parsed = parseChatRequest({ messages });
    assert.ok(parsed.messages.length <= 30);
    assert.equal(parsed.messages[0]!.role, "user");
    assert.equal(parsed.messages.at(-1)!.content, "last");
  });
});

describe("sanitizePlan", () => {
  it("keeps a valid plan", () => {
    const plan = sanitizePlan(validPlan)!;
    assert.equal(plan.weeks, 8);
    assert.equal(plan.sessions[0]!.exercises![0]!.percentOfOneRepMax, 80);
  });

  it("clamps and drops bad data instead of passing it on", () => {
    const plan = sanitizePlan({
      title: "  Plan  ",
      weeks: 400,
      sessions: [
        { week: 99, day: 9, title: "A", type: "wizardry", durationMinutes: 99999,
          exercises: [
            { name: "Squat (Barbell)", sets: 500, reps: 5, percentOfOneRepMax: 900, muscles: ["quads", "toenails"] },
            { name: "", sets: 3, reps: "5" },
          ] },
        { week: 1, day: 1, title: "", type: "cardio", durationMinutes: 30 },
        "garbage",
      ],
    })!;
    assert.equal(plan.title, "Plan");
    assert.equal(plan.weeks, 24);
    assert.equal(plan.sessions.length, 1);
    const session = plan.sessions[0]!;
    assert.equal(session.week, 24);
    assert.equal(session.day, 7);
    assert.equal(session.type, "strength");
    assert.equal(session.durationMinutes, 300);
    assert.equal(session.exercises!.length, 1);
    const exercise = session.exercises![0]!;
    assert.equal(exercise.sets, 20);
    assert.equal(exercise.reps, "5");
    assert.equal(exercise.percentOfOneRepMax, 110);
    assert.deepEqual(exercise.muscles, ["quads"]);
  });

  it("returns null when nothing usable is left", () => {
    assert.equal(sanitizePlan(null), null);
    assert.equal(sanitizePlan({ title: "x", weeks: 4, sessions: [] }), null);
    assert.equal(sanitizePlan({ weeks: 4, sessions: [{}] }), null);
  });

  it("sorts sessions by week then day", () => {
    const plan = sanitizePlan({
      title: "t", weeks: 2,
      sessions: [
        { week: 2, day: 1, title: "c", type: "cardio", durationMinutes: 20 },
        { week: 1, day: 5, title: "b", type: "cardio", durationMinutes: 20 },
        { week: 1, day: 2, title: "a", type: "cardio", durationMinutes: 20 },
      ],
    })!;
    assert.deepEqual(plan.sessions.map((s) => s.title), ["a", "b", "c"]);
  });
});

describe("handleChat", () => {
  it("passes the system prompt, context and messages to the model", async () => {
    const calls: ModelCall[] = [];
    const out = await handleChat(input(), deps({}, calls));
    assert.equal(out.status, 200);
    assert.equal(out.json.text, "Hello!");
    assert.equal(calls.length, 1);
    assert.match(calls[0]!.system, /training coach/);
    assert.deepEqual(calls[0]!.context, { units: { weight: "kg" } });
  });

  it("requires the app key and an install id", async () => {
    assert.equal((await handleChat(input(goodBody, { appKey: "wrong" }), deps())).status, 401);
    assert.equal((await handleChat(input(goodBody, { installId: undefined }), deps())).status, 400);
    assert.equal((await handleChat(input(goodBody, { installId: "not-a-uuid" }), deps())).status, 400);
  });

  it("doesn't require a key when none is configured", async () => {
    const open = { ...deps(), config: { ...config, appKey: null } };
    assert.equal((await handleChat(input(goodBody, { appKey: undefined }), open)).status, 200);
  });

  it("rate limits per install and says when to retry", async () => {
    const d = deps();
    for (let i = 0; i < 3; i++) assert.equal((await handleChat(input(), d)).status, 200);
    const limited = await handleChat(input(), d);
    assert.equal(limited.status, 429);
    assert.ok(Number(limited.headers?.["retry-after"]) > 0);
    // A different install is unaffected.
    const other = await handleChat(input(goodBody, { installId: "11111111-1111-4111-8111-111111111111" }), d);
    assert.equal(other.status, 200);
  });

  it("returns a sanitised plan alongside the text", async () => {
    const out = await handleChat(input(), deps({ text: "Here you go.", planInput: validPlan }));
    assert.equal(out.status, 200);
    assert.equal(out.json.text, "Here you go.");
    assert.equal(out.json.plan?.title, "8-week bench builder");
  });

  it("gives a default message when the model only calls the tool", async () => {
    const out = await handleChat(input(), deps({ text: "", planInput: validPlan }));
    assert.match(out.json.text!, /plan/i);
  });

  it("fails cleanly when the plan is unusable", async () => {
    const out = await handleChat(input(), deps({ planInput: { title: "x", weeks: 2, sessions: [] } }));
    assert.equal(out.status, 502);
  });

  it("handles refusals and truncation", async () => {
    const refused = await handleChat(input(), deps({ stopReason: "refusal", text: "" }));
    assert.equal(refused.status, 200);
    assert.equal(refused.json.refused, true);
    const cut = await handleChat(input(), deps({ stopReason: "max_tokens", text: "" }));
    assert.equal(cut.status, 502);
  });

  it("rejects malformed bodies with 400", async () => {
    assert.equal((await handleChat(input({ messages: [] }), deps())).status, 400);
  });
});

describe("HTTP server", () => {
  async function withServer(run: (base: string) => Promise<void>, d = deps({ planInput: validPlan, text: "ok" })) {
    const server = createApp(d);
    await new Promise<void>((resolve) => server.listen(0, resolve));
    const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
    try {
      await run(base);
    } finally {
      await new Promise((resolve) => server.close(resolve));
    }
  }

  const headers = { "content-type": "application/json", "x-install-id": INSTALL, "x-app-key": "secret" };

  it("serves health, chat, and rejects everything else", async () => {
    await withServer(async (base) => {
      assert.equal((await fetch(`${base}/health`)).status, 200);
      assert.equal((await fetch(`${base}/nope`)).status, 404);

      const ok = await fetch(`${base}/chat`, { method: "POST", headers, body: JSON.stringify(goodBody) });
      assert.equal(ok.status, 200);
      const json = (await ok.json()) as { plan?: { title: string } };
      assert.equal(json.plan?.title, "8-week bench builder");

      const noKey = await fetch(`${base}/chat`, { method: "POST", headers: { ...headers, "x-app-key": "bad" }, body: JSON.stringify(goodBody) });
      assert.equal(noKey.status, 401);

      const badJson = await fetch(`${base}/chat`, { method: "POST", headers, body: "{not json" });
      assert.equal(badJson.status, 400);

      // An oversized body is refused: either a clean 413/400, or the connection is closed on us.
      const status = await fetch(`${base}/chat`, {
        method: "POST", headers, body: JSON.stringify({ messages: [{ role: "user", content: "x".repeat(100_000) }] }),
      }).then((r) => r.status, () => "closed");
      assert.ok([400, 413, "closed"].includes(status as never), `unexpected: ${status}`);
    });
  });

  it("turns unexpected model errors into a safe 500", async () => {
    const failing: Deps = { ...deps(), callModel: async () => { throw new Error("boom with secret details"); } };
    await withServer(async (base) => {
      const res = await fetch(`${base}/chat`, { method: "POST", headers, body: JSON.stringify(goodBody) });
      assert.equal(res.status, 500);
      assert.doesNotMatch(await res.text(), /secret details/);
    }, failing);
  });
});
