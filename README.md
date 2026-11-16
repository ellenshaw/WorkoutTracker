# WorkoutTracker

An iOS app (SwiftUI, iOS 17+) for logging workouts and seeing which muscles you hit.

- **Log a workout** with a category, duration, date, notes, and the muscles you worked (tap a muscle to cycle light → moderate → heavy).
- **3D muscle map** appears right after you save: a rotatable 3D figure (SceneKit) with each muscle colored yellow / orange / red by how hard it was used. Drag to rotate, or tap Flip for the back.
- **Body tab** combines the last 7 days into one heat map.
- **Dark mode** follows the system, with a System / Light / Dark switch in Settings.
- Workouts are saved on-device (JSON in Documents). Settings has Log out and Delete account and data.

Open `WorkoutTracker/WorkoutTracker.xcodeproj` in Xcode 15.4+ and run.
