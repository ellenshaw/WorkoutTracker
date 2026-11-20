# Publishing Workout Tracker to the App Store

Work through this top to bottom. Items marked **(done)** are already handled in the repo.

## 1. Already handled in the code

- **(done)** No fake login. First launch shows a welcome screen; there are no accounts. "Delete all my data" in Settings erases everything.
- **(done)** Privacy manifest (`PrivacyInfo.xcprivacy`) declaring what the app collects and its use of UserDefaults. Apple requires this.
- **(done)** Consent screen before the AI coach sends anything, plus a switch to stop sharing training info (Apple requires disclosure and permission before personal data goes to a third-party AI).
- **(done)** Location permission text, export-compliance answer (`ITSAppUsesNonExemptEncryption = NO`), iPhone-only for version 1 (less to test and screenshot; add iPad later).
- **(done)** Medical disclaimers in the coach and cycle tracking. Cycle data never leaves the phone.

## 2. Accounts and money (you)

1. **Apple Developer Program**: developers.apple.com/programs, about $99 a year. An individual account works. Approval can take a day or two.
2. **Anthropic API** (for the coach): console.anthropic.com, add billing, create a key, **set a monthly spending limit**.
3. **Hosting** for the coach server: follow `backend/README.md` (Render blueprint is in `render.yaml`). Keep it running while Apple reviews the app: if the coach is down, reviewers will reject it.

## 3. In Xcode (you)

1. Target **WorkoutTracker → Signing & Capabilities**: pick your Team. Check the bundle ID (`ellen.WorkoutTracker`) is available; if Apple says it's taken, change it.
2. **Info tab**: add two String rows, `CoachBaseURL` (your server URL) and `CoachAppKey` (the `APP_KEY` you set on the server).
3. **App icon**: the one in the repo is a placeholder. Replace `Assets.xcassets/AppIcon` with a 1024×1024 PNG (no transparency, no rounded corners; Apple rounds it).
4. Set **Version** (1.0) and **Build** (1). Raise Build by one for every upload.
5. Optional but recommended: Signing & Capabilities → **Background Modes → Location updates**, so GPS tracking keeps working with the screen locked. Then mention it in the review notes.

## 4. Test on a real iPhone before submitting (you)

Use **TestFlight** (Product → Archive → Distribute → App Store Connect, then add yourself as an internal tester). Check:

- A strength workout end to end, including the Previous column and the progress chart.
- An outdoor GPS run (walk around the block): distance, pace, route map, pause/resume.
- The AI coach: ask for a plan, start it from the Plans tab, log a session from it.
- Cycle tracking on/off, and the reminder notification.
- Dark mode, a small phone (iPhone SE size) and a large one, large text sizes.
- "Delete all my data" returns you to the welcome screen.

## 5. App Store Connect (you)

1. appstoreconnect.apple.com → **My Apps → +** → New App. The name must be unique across the whole store; if "Workout Tracker" is taken, see the alternatives in `app-store-listing.md`.
2. Paste the text from `docs/app-store-listing.md`.
3. **Privacy policy URL** (required): host `docs/privacy-policy.md` somewhere public (GitHub Pages is free), after filling in the `[brackets]` and having it checked. **Support URL** (required): a page or even a mailto-style contact page with your email.
4. **App Privacy** answers: copy from `app-store-listing.md` ("Privacy nutrition label").
5. **Age rating** questionnaire: answer honestly. The app has health and fitness content and an AI chatbot.
6. **Screenshots**: at least the 6.9" iPhone size (1320×2868). Ideas are in the listing file. Take them in the Simulator (iPhone 16 Pro Max) with some sample workouts logged.
7. **App Review information**: paste the review notes, and keep the coach server up.
8. If you distribute in the EU, App Store Connect asks you to declare whether you're a **trader** (you are, if you do this as a business or for income).
9. Upload the build (from Xcode), select it, **Submit for Review**. First reviews usually take a day or two, sometimes longer.

## 6. Likely review questions, and the answers

- *Health claims:* the app doesn't diagnose or treat anything; it says so in the app. Don't add claims about curing, preventing or predicting medical conditions or fertility.
- *AI content:* the coach is clearly labelled as AI, has a disclaimer, and asks permission first.
- *Why location?* Only during a tracked outdoor session, for distance and a route map. Stays on the device.
- *Crashes:* the most common rejection. TestFlight on a real device first.

## 7. After launch

- Watch the Anthropic dashboard for spend and your server logs for errors.
- Answer reviews. Consider a monthly cap per user, then a subscription, if the AI costs add up.
- Next big items: real accounts (Sign in with Apple), then sharing and a community, then Apple Health or Strava import.
