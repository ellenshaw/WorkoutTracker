# Coach backend

A small server between the Workout Tracker app and Claude. **The app never contains your Anthropic API key**:
anything inside an app can be extracted, and a leaked key means someone else runs up your bill. Instead the app
sends the conversation here, and this server holds the key, enforces usage limits, calls Claude, and returns
the reply (and a training plan when the coach creates one).

```
iOS app  --HTTPS-->  this server  --API key-->  Claude
```

## What it does

- `POST /chat` takes `{ messages, context }` and returns `{ text, plan? }`.
- The coach's instructions and the plan tool live in `src/prompt.ts`, so you can improve the coach without an app update.
- Every plan the model produces is validated and clamped (`src/validate.ts`) before the app sees it.
- Limits: per install and per IP (`src/rateLimit.ts`), request size caps, no message contents in logs.
- If Claude's safety system declines a request, the API automatically retries on a fallback model.

## Run it locally

```bash
cd backend
npm install
cp .env.example .env      # then fill in ANTHROPIC_API_KEY and APP_KEY
export $(grep -v '^#' .env | xargs)
npm run dev               # listens on http://localhost:8787
```

Quick check:

```bash
curl http://localhost:8787/health
curl -X POST http://localhost:8787/chat \
  -H 'content-type: application/json' \
  -H "x-app-key: $APP_KEY" \
  -H 'x-install-id: 3f2504e0-4f89-11d3-9a0c-0305e82c3301' \
  -d '{"messages":[{"role":"user","content":"Give me a 4 week plan to add 5 kg to my bench"}],"context":{}}'
```

The iOS simulator blocks plain `http://` addresses. To test the app against your laptop, expose it over HTTPS with
a tunnel (for example `cloudflared tunnel --url http://localhost:8787`) and use that URL in the app.

## Deploy it

Any host that runs a Docker image or Node works (Render, Fly.io, Railway, Google Cloud Run). The steps are the same:

1. Create a new web service from this `backend/` folder (it has a `Dockerfile`).
2. Set the environment variables from `.env.example`. `ANTHROPIC_API_KEY` and `APP_KEY` are the important ones.
3. Deploy. You get an HTTPS URL such as `https://your-coach.onrender.com`.
4. In the app: Settings → AI coach → paste the server URL and the same `APP_KEY`.

For a published app, put the URL and key in the app's Info.plist (`CoachBaseURL`, `CoachAppKey`) so users don't type them.

## Before you publish

- **`APP_KEY` is only a speed bump.** It stops casual abuse, but anyone can pull it out of the app. The real protection
  is the per-install and per-IP limits plus a spending limit on your Anthropic account (set one in the Console).
  For stronger protection, add Sign in with Apple or Apple App Attest and verify it here.
- **Limits are in memory.** Fine for one server. If you run several instances, move `RateLimiter` to Redis.
- **Cost.** Each reply is a model call; building a plan produces several thousand output tokens. `MODEL` defaults to
  `claude-opus-5-5`. If cost matters more than the very best answers, try `claude-sonnet-5-5` or `claude-haiku-5-5`
  and compare plan quality.
- **Privacy.** The app sends the user's messages and, if they allow it, a summary of their body stats, records and
  recent workouts. Disclose that in your privacy policy and App Store privacy answers, and tell your Anthropic
  account's data-retention settings what you need.
- **Not medical advice.** The coach is instructed to be conservative and to point people to a professional for pain
  or medical conditions. Keep the in-app disclaimer.

## Tests

```bash
npm test          # validation, plan sanitising, rate limits, HTTP behaviour (uses a fake model; no API calls)
npm run typecheck
```
