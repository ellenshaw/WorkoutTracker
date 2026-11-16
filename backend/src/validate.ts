import { CATEGORIES, INTENSITIES, MUSCLES } from "./prompt.js";

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

export interface ChatRequest {
  messages: ChatMessage[];
  context: Record<string, unknown>;
}

export class RequestError extends Error {
  constructor(message: string, public status = 400) {
    super(message);
  }
}

export const LIMITS = {
  maxMessages: 30,
  maxMessageChars: 6000,
  maxContextChars: 14000,
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Checks the shape and size of what the app sent. Throws RequestError (400) when it's wrong. */
export function parseChatRequest(body: unknown): ChatRequest {
  if (!isRecord(body)) throw new RequestError("Body must be a JSON object.");

  const rawMessages = body.messages;
  if (!Array.isArray(rawMessages) || rawMessages.length === 0) {
    throw new RequestError("messages must be a non-empty array.");
  }

  const messages: ChatMessage[] = [];
  for (const item of rawMessages.slice(-LIMITS.maxMessages)) {
    if (!isRecord(item) || (item.role !== "user" && item.role !== "assistant") || typeof item.content !== "string") {
      throw new RequestError("Each message needs a role (user or assistant) and string content.");
    }
    const content = item.content.trim();
    if (content.length === 0) continue;
    if (content.length > LIMITS.maxMessageChars) {
      throw new RequestError(`A message is longer than ${LIMITS.maxMessageChars} characters.`);
    }
    messages.push({ role: item.role, content });
  }

  // The conversation has to start with, and end on, something the user said.
  while (messages.length > 0 && messages[0]!.role !== "user") messages.shift();
  if (messages.length === 0 || messages[messages.length - 1]!.role !== "user") {
    throw new RequestError("The last message must be from the user.");
  }

  let context: Record<string, unknown> = {};
  if (body.context !== undefined && body.context !== null) {
    if (!isRecord(body.context)) throw new RequestError("context must be an object.");
    if (JSON.stringify(body.context).length > LIMITS.maxContextChars) {
      throw new RequestError("context is too large.");
    }
    context = body.context;
  }

  return { messages, context };
}

// ---- Plans -----------------------------------------------------------------

export interface PlanExercise {
  name: string;
  sets: number;
  reps: string;
  percentOfOneRepMax?: number;
  weightKg?: number;
  muscles?: string[];
  notes?: string;
}

export interface PlanSession {
  week: number;
  day: number;
  title: string;
  type: (typeof CATEGORIES)[number];
  activity?: string;
  durationMinutes: number;
  notes?: string;
  exercises?: PlanExercise[];
  targetDistanceKm?: number;
  intensity?: (typeof INTENSITIES)[number];
}

export interface Plan {
  title: string;
  goal: string;
  summary: string;
  weeks: number;
  sessions: PlanSession[];
}

const clampInt = (value: unknown, min: number, max: number): number | undefined => {
  const n = typeof value === "string" ? Number(value) : value;
  if (typeof n !== "number" || !Number.isFinite(n)) return undefined;
  return Math.min(Math.max(Math.round(n), min), max);
};

const clampNumber = (value: unknown, min: number, max: number): number | undefined => {
  const n = typeof value === "string" ? Number(value) : value;
  if (typeof n !== "number" || !Number.isFinite(n)) return undefined;
  return Math.min(Math.max(n, min), max);
};

const text = (value: unknown, max: number): string | undefined => {
  if (typeof value === "number") value = String(value);
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length === 0 ? undefined : trimmed.slice(0, max);
};

/**
 * The model's tool input is untrusted: clamp every field into a sane range, drop what doesn't fit
 * and return null if nothing usable is left. The app can then decode the result without surprises.
 */
export function sanitizePlan(input: unknown): Plan | null {
  if (!isRecord(input)) return null;

  const weeks = clampInt(input.weeks, 1, 24);
  const title = text(input.title, 100);
  if (weeks === undefined || title === undefined || !Array.isArray(input.sessions)) return null;

  const sessions: PlanSession[] = [];
  for (const raw of input.sessions.slice(0, 200)) {
    if (!isRecord(raw)) continue;

    const week = clampInt(raw.week, 1, weeks);
    const day = clampInt(raw.day, 1, 7);
    const sessionTitle = text(raw.title, 80);
    const duration = clampInt(raw.durationMinutes, 5, 300);
    if (week === undefined || day === undefined || sessionTitle === undefined || duration === undefined) continue;

    const type = CATEGORIES.includes(raw.type as never) ? (raw.type as PlanSession["type"]) : "strength";

    const exercises: PlanExercise[] = [];
    if (Array.isArray(raw.exercises)) {
      for (const e of raw.exercises.slice(0, 12)) {
        if (!isRecord(e)) continue;
        const name = text(e.name, 80);
        const sets = clampInt(e.sets, 1, 20);
        const reps = text(e.reps, 20);
        if (name === undefined || sets === undefined || reps === undefined) continue;

        const muscles = Array.isArray(e.muscles)
          ? e.muscles.filter((m): m is string => typeof m === "string" && MUSCLES.includes(m as never))
          : [];
        exercises.push({
          name,
          sets,
          reps,
          percentOfOneRepMax: clampNumber(e.percentOfOneRepMax, 10, 110),
          weightKg: clampNumber(e.weightKg, 0, 1000),
          muscles: muscles.length > 0 ? muscles : undefined,
          notes: text(e.notes, 200),
        });
      }
    }

    sessions.push({
      week,
      day,
      title: sessionTitle,
      type,
      activity: text(raw.activity, 60),
      durationMinutes: duration,
      notes: text(raw.notes, 500),
      exercises: exercises.length > 0 ? exercises : undefined,
      targetDistanceKm: clampNumber(raw.targetDistanceKm, 0, 300),
      intensity: INTENSITIES.includes(raw.intensity as never) ? (raw.intensity as PlanSession["intensity"]) : undefined,
    });
  }

  if (sessions.length === 0) return null;
  sessions.sort((a, b) => a.week - b.week || a.day - b.day);

  return {
    title,
    goal: text(input.goal, 200) ?? title,
    summary: text(input.summary, 600) ?? "",
    weeks,
    sessions,
  };
}
