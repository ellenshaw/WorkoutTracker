# WorkoutTracker

An iOS app (SwiftUI, iOS 17+) for logging workouts and seeing which muscles you hit.

- **Strength logging, Hevy-style:** pick exercises from a searchable directory (filter by muscle, add your own), log sets of weight × reps, see what you did last time, tick sets off, and finish. kg or lb.
- **Tap-to-pick activities** for cardio, climbing, sport and mobility: no dropdowns, just blocks to tap.
- **3D muscle map** appears right after you save: a rotatable anatomical figure (SceneKit, generated in code) with each muscle colored yellow / orange / red by how hard it was used (from your sets, or from the muscles you tap). Drag to rotate, or tap Flip for the back.
- **Pin favorites:** swipe a workout to pin it; pinned workouts sit on the home screen as one-tap templates.
- **Body tab** combines the last 7 days into one heat map.
- **Dark mode** follows the system, with a System / Light / Dark switch in Settings.
- Workouts are saved on-device (JSON in Documents). Settings has Log out and Delete account and data.

Open `WorkoutTracker/WorkoutTracker.xcodeproj` in Xcode 15.4+ and run.
