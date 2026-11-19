//
//  OutdoorTracker.swift
//  WorkoutTracker
//
//  Outdoor mode: records a session with the phone's GPS (distance, time, pace, route map) for
//  runs, walks, hikes, rides and outdoor rowing. The distance maths lives in `OutdoorSession`
//  (Distance.swift); this file only wraps CoreLocation and the screen.
//

import SwiftUI
import MapKit
import CoreLocation

/// What a finished outdoor session hands back to the logging screen.
struct OutdoorResult {
    var distanceKm: Double
    var seconds: Int
    var route: [RoutePoint]

    var averageKmh: Double {
        seconds > 0 ? distanceKm / (Double(seconds) / 3600) : 0
    }
}

@MainActor
final class OutdoorTracker: NSObject, ObservableObject {
    enum State { case idle, running, paused, finished }

    @Published private(set) var state: State = .idle
    @Published private(set) var session = OutdoorSession()
    @Published private(set) var authorization: CLAuthorizationStatus
    /// The path so far, for drawing.
    @Published private(set) var coordinates: [CLLocationCoordinate2D] = []

    private let manager: CLLocationManager
    private var startedAt: Date?
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 5
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Seconds spent moving or standing, not counting time paused.
    func elapsed(at now: Date = Date()) -> TimeInterval {
        guard let startedAt else { return 0 }
        let end = (state == .paused ? pausedAt : nil) ?? now
        return max(end.timeIntervalSince(startedAt) - pausedTotal, 0)
    }

    func start() {
        guard isAuthorized, state == .idle else { return }
        session = OutdoorSession()
        coordinates = []
        startedAt = Date()
        pausedTotal = 0

        // Tracking with the screen off needs the "Location updates" background mode in the app's
        // capabilities. Only switch it on when it's there; asking without it crashes.
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        if modes.contains("location") {
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            manager.showsBackgroundLocationIndicator = true
        }

        state = .running
        UIApplication.shared.isIdleTimerDisabled = true   // keep the screen on while tracking
        manager.startUpdatingLocation()
    }

    func pause() {
        guard state == .running else { return }
        pausedAt = Date()
        state = .paused
        manager.stopUpdatingLocation()
    }

    func resume() {
        guard state == .paused else { return }
        if let pausedAt { pausedTotal += Date().timeIntervalSince(pausedAt) }
        pausedAt = nil
        session.startNewSegment()
        state = .running
        manager.startUpdatingLocation()
    }

    /// Stops tracking and returns what was recorded.
    func finish() -> OutdoorResult {
        if state == .paused, let pausedAt { pausedTotal += Date().timeIntervalSince(pausedAt) }
        let seconds = Int(elapsed().rounded())
        manager.stopUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = false
        state = .finished
        return OutdoorResult(distanceKm: session.distanceKm, seconds: seconds, route: session.route())
    }

    /// Leaves without keeping anything.
    func cancel() {
        manager.stopUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    fileprivate func handle(_ samples: [GPSSample]) {
        guard state == .running else { return }
        for sample in samples {
            let before = session.points.count
            session.add(sample)
            if session.points.count > before {
                coordinates.append(CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude))
            }
        }
    }
}

extension OutdoorTracker: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let samples = locations.map {
            GPSSample(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                      timestamp: $0.timestamp, horizontalAccuracy: $0.horizontalAccuracy)
        }
        Task { @MainActor in self.handle(samples) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorization = status }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A temporary lack of signal is normal outdoors; readings simply resume.
    }
}

// MARK: - Screen

struct OutdoorTrackerView: View {
    let activity: String
    let onFinish: (OutdoorResult) -> Void
    let onCancel: () -> Void

    @StateObject private var tracker = OutdoorTracker()
    @AppStorage(StorageKey.distanceUnit) private var unitRaw = DistanceUnit.km.rawValue
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var confirmingDiscard = false

    private var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .km }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $position) {
                    UserAnnotation()
                    if tracker.coordinates.count > 1 {
                        MapPolyline(coordinates: tracker.coordinates)
                            .stroke(Theme.accent, lineWidth: 5)
                    }
                }
                .ignoresSafeArea(edges: .bottom)

                panel
            }
            .navigationTitle(activity)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if tracker.state == .idle { close() } else { confirmingDiscard = true }
                    }
                }
            }
            .confirmationDialog("Discard this session?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { close() }
                Button("Keep going", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            if tracker.authorization == .notDetermined { tracker.requestPermission() }
        }
    }

    private func close() {
        tracker.cancel()
        onCancel()
    }

    // MARK: Panel

    @ViewBuilder
    private var panel: some View {
        VStack(spacing: 14) {
            if !tracker.isAuthorized && tracker.authorization != .notDetermined {
                VStack(spacing: 8) {
                    Text("Location is off for this app")
                        .font(.headline)
                    Text("Allow location access in Settings to track outdoors.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            } else {
                stats
                controls
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding()
    }

    private var stats: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = tracker.elapsed(at: context.date)
            let km = tracker.session.distanceKm
            let style = ActivityMetrics.paceStyle(for: activity)

            HStack {
                stat(PaceFormat.clock(seconds), "Time")
                Divider().frame(height: 34)
                stat(ActivityMetrics.usesShortDistance(activity)
                     ? "\(Int(unit.fromKmShort(km).rounded())) \(unit.shortSymbol)"
                     : "\(unit.format(km: km)) \(unit.symbol)", "Distance")
                Divider().frame(height: 34)
                stat(km > 0.02 && seconds > 5
                     ? PaceFormat.format(secondsPerKm: seconds / km, style: style, unit: unit)
                     : "–", "Pace")
            }
        }
    }

    private func stat(_ value: String, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var controls: some View {
        switch tracker.state {
        case .idle:
            Button {
                if tracker.authorization == .notDetermined {
                    tracker.requestPermission()
                } else {
                    tracker.start()
                }
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
        case .running:
            HStack(spacing: 12) {
                Button { tracker.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                finishButton
            }
        case .paused:
            HStack(spacing: 12) {
                Button { tracker.resume() } label: { Label("Resume", systemImage: "play.fill") }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                finishButton
            }
        case .finished:
            EmptyView()
        }
    }

    private var finishButton: some View {
        Button {
            onFinish(tracker.finish())
        } label: {
            Label("Finish", systemImage: "flag.checkered")
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}

// MARK: - Route map on a finished workout

struct RouteMapView: View {
    let route: [RoutePoint]

    private var coordinates: [CLLocationCoordinate2D] {
        route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// The area covering the whole route, with some breathing room.
    private var region: MKMapRect {
        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }
        let margin = max(rect.size.width, rect.size.height) * 0.25 + 300
        return rect.insetBy(dx: -margin, dy: -margin)
    }

    var body: some View {
        let path = coordinates
        Map(initialPosition: .rect(region)) {
            MapPolyline(coordinates: path)
                .stroke(Theme.accent, lineWidth: 4)
            if let first = path.first {
                Marker("Start", systemImage: "flag.fill", coordinate: first)
                    .tint(.green)
            }
            if let last = path.last, path.count > 1 {
                Marker("Finish", systemImage: "flag.checkered", coordinate: last)
                    .tint(.red)
            }
        }
        .accessibilityLabel("Route map")
    }
}
