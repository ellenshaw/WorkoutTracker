//
//  BodyModelView.swift
//  WorkoutTracker
//
//  A holographic 3D anatomy figure. Three looks: Crystal (a faceted glass body with glowing
//  nodes), Lines (scan-lines) and Grid. Worked muscles glow on the
//  blue-to-red heat scale and get a name label. Tap any muscle to identify it.
//

import SwiftUI
import SceneKit

/// Colors shared by the 3D scene and the card around it.
enum Hologram {
    static let background = UIColor(red: 0.03, green: 0.05, blue: 0.10, alpha: 1)
    static let glow = UIColor(red: 0.25, green: 0.60, blue: 1.0, alpha: 1)

    /// Deep navy that brightens to blue behind the figure, like a lit chamber.
    static let crystalBackdrop: UIImage = {
        let size = CGSize(width: 512, height: 512)
        return UIGraphicsImageRenderer(size: size).image { context in
            let space = CGColorSpaceCreateDeviceRGB()
            let colors = [
                UIColor(red: 0.03, green: 0.17, blue: 0.40, alpha: 1).cgColor,
                UIColor(red: 0.02, green: 0.09, blue: 0.24, alpha: 1).cgColor,
                Hologram.background.cgColor
            ] as CFArray
            guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.5, 1]) else { return }
            let center = CGPoint(x: size.width / 2, y: size.height * 0.4)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                                 endCenter: center, endRadius: size.width * 0.75, options: [.drawsAfterEndLocation])
        }
    }()
}

/// Where a muscle's label should point, in the 3D view's own coordinates.
struct MuscleLabel: Equatable, Identifiable {
    let muscle: MuscleGroup
    let point: CGPoint
    var id: MuscleGroup { muscle }
}

struct BodyModelView: UIViewRepresentable {
    var heat: [MuscleGroup: Double]
    var profile: BodyProfile
    var style: HologramStyle
    /// Increment to spin the figure to its other side.
    var flipToken: Int
    /// A muscle the user tapped; it is labelled even if it wasn't worked.
    var selected: MuscleGroup?
    var onSelect: (MuscleGroup?) -> Void
    var onLabels: ([MuscleLabel]) -> Void

    init(heat: [MuscleGroup: Double],
         profile: BodyProfile,
         style: HologramStyle = .crystal,
         flipToken: Int = 0,
         selected: MuscleGroup? = nil,
         onSelect: @escaping (MuscleGroup?) -> Void = { _ in },
         onLabels: @escaping ([MuscleLabel]) -> Void = { _ in }) {
        self.heat = heat
        self.profile = profile
        self.style = style
        self.flipToken = flipToken
        self.selected = selected
        self.onSelect = onSelect
        self.onLabels = onLabels
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.delegate = context.coordinator
        view.backgroundColor = Hologram.background
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.isPlaying = false
        view.addGestureRecognizer(UIPanGestureRecognizer(target: context.coordinator,
                                                         action: #selector(Coordinator.handlePan(_:))))
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator,
                                                         action: #selector(Coordinator.handleTap(_:))))
        sync(context.coordinator)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        sync(context.coordinator)
        context.coordinator.flip(ifTokenChanged: flipToken)
    }

    private func sync(_ coordinator: Coordinator) {
        coordinator.onSelect = onSelect
        coordinator.onLabels = onLabels
        coordinator.update(profile: profile, style: style, heat: heat, selected: selected)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        typealias Vec = SIMD3<Float>

        let scene = SCNScene()
        var onSelect: (MuscleGroup?) -> Void = { _ in }
        var onLabels: ([MuscleLabel]) -> Void = { _ in }

        private let figure = SCNNode()
        private let cameraNode = SCNNode()
        private let legacyFloor = SCNNode()
        private let fillNode = SCNNode()
        private let lineNode = SCNNode()
        private let haloNode = SCNNode()
        private let crystalFillNode = SCNNode()
        private let crystalEdgeNode = SCNNode()
        private let crystalDotNode = SCNNode()

        private let fillMaterial = Coordinator.litMaterial()
        private let lineMaterial = Coordinator.constantMaterial(.white)
        private let haloMaterial = Coordinator.constantMaterial(Hologram.glow, alpha: 0.14, additive: true)
        private let crystalFillMaterial = Coordinator.glassMaterial(alpha: 0.5)
        private let crystalEdgeMaterial = Coordinator.glassMaterial(alpha: 0.55)
        private let crystalDotMaterial = Coordinator.glassMaterial(alpha: 0.95)

        // Mesh data for the body currently shown.
        private var mesh: BodyMeshData?
        private var lines: BodyLines?
        private var crystal: BodyAsset.CrystalMesh?
        private var vertexSource: SCNGeometrySource?
        private var normalSource: SCNGeometrySource?
        private var fillElement: SCNGeometryElement?
        private var lineVertexSource: SCNGeometrySource?
        private var lineElement: SCNGeometryElement?
        private var crystalFillSources: [SCNGeometrySource] = []
        private var crystalFillElement: SCNGeometryElement?
        private var crystalEdgeSource: SCNGeometrySource?
        private var crystalEdgeElement: SCNGeometryElement?
        private var crystalDotSource: SCNGeometrySource?
        private var crystalDotElement: SCNGeometryElement?

        private var currentProfile: BodyProfile?
        private var currentStyle: HologramStyle?
        private var sceneStyle: HologramStyle?
        private var buildGeneration = 0
        private var wantedHeat: [MuscleGroup: Double] = [:]
        private var shownHeat: [MuscleGroup: Double]?
        private var lastFlipToken = 0

        // Read on the render thread, written on the main thread.
        private let labelLock = NSLock()
        private var anchors: [BodyAnchor] = []
        private var labelTargets: Set<MuscleGroup> = []
        private var lastPublished: [MuscleLabel] = []

        override init() {
            super.init()
            buildScene()
        }

        // MARK: Updating

        func update(profile: BodyProfile, style: HologramStyle, heat: [MuscleGroup: Double], selected: MuscleGroup?) {
            wantedHeat = heat

            labelLock.lock()
            var targets = Set(heat.filter { $0.value > 0 }.keys)
            if let selected { targets.insert(selected) }
            labelTargets = targets
            labelLock.unlock()

            if style != sceneStyle { applySceneStyle(style) }

            if profile != currentProfile || style != currentStyle {
                loadBody(profile, style: style)
            } else {
                applyHeat()
            }
        }

        private func applyHeat() {
            guard let mesh, let lines, let style = currentStyle else { return }
            if shownHeat == wantedHeat { return }
            shownHeat = wantedHeat

            // Muscle outlines (and, outside the crystal style, fibres and skin lines).
            if let lineVertexSource, let lineElement {
                let lineColors = BodyAsset.lineColors(for: lines, heat: wantedHeat)
                let lineGeometry = SCNGeometry(sources: [lineVertexSource, Coordinator.colorSource(lineColors)],
                                               elements: [lineElement])
                lineGeometry.materials = [lineMaterial]
                lineNode.geometry = lineGeometry
            }

            if style == .crystal {
                guard let crystal, !crystalFillSources.isEmpty,
                      let crystalFillElement, let crystalEdgeSource, let crystalEdgeElement,
                      let crystalDotSource, let crystalDotElement else { return }

                let fillColors = BodyAsset.crystalFillColors(for: crystal, mesh: mesh, heat: wantedHeat)
                let fill = SCNGeometry(sources: crystalFillSources + [Coordinator.colorSource(fillColors)],
                                       elements: [crystalFillElement])
                fill.materials = [crystalFillMaterial]
                crystalFillNode.geometry = fill

                let edgeColors = BodyAsset.crystalLineColors(vertices: crystal.edgeVertices, mesh: mesh, heat: wantedHeat, edge: true)
                let edges = SCNGeometry(sources: [crystalEdgeSource, Coordinator.colorSource(edgeColors)],
                                        elements: [crystalEdgeElement])
                edges.materials = [crystalEdgeMaterial]
                crystalEdgeNode.geometry = edges

                let dotColors = BodyAsset.crystalLineColors(vertices: crystal.dotVertices, mesh: mesh, heat: wantedHeat, edge: false)
                let dots = SCNGeometry(sources: [crystalDotSource, Coordinator.colorSource(dotColors)],
                                       elements: [crystalDotElement])
                dots.materials = [crystalDotMaterial]
                crystalDotNode.geometry = dots
            } else {
                guard let vertexSource, let normalSource, let fillElement else { return }
                let fillColors = BodyAsset.fillColors(for: mesh, heat: wantedHeat)
                let fill = SCNGeometry(sources: [vertexSource, normalSource, Coordinator.colorSource(fillColors)],
                                       elements: [fillElement])
                fill.materials = [fillMaterial]
                fillNode.geometry = fill
            }
        }

        func flip(ifTokenChanged token: Int) {
            guard token != lastFlipToken else { return }
            lastFlipToken = token

            let current = figure.eulerAngles.y
            let facingFront = cos(current) >= 0
            let target: Float = facingFront ? .pi : 0
            let turns = ((current - target) / (2 * .pi)).rounded()
            let destination = target + turns * 2 * .pi

            figure.removeAllActions()
            figure.runAction(SCNAction.rotateTo(x: 0, y: CGFloat(destination), z: 0,
                                                duration: 0.6, usesShortestUnitArc: false))
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began {
                figure.removeAllActions()
            }
            let translation = gesture.translation(in: gesture.view)
            figure.eulerAngles.y += Float(translation.x) * 0.012
            gesture.setTranslation(.zero, in: gesture.view)
        }

        /// Tapping the body names the muscle under the finger; tapping elsewhere clears it.
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView, let mesh else { return }
            // In the crystal style the facets are the visible body, in the others the solid mesh.
            let pickable: SCNNode = currentStyle == .crystal ? crystalFillNode : fillNode
            let hits = view.hitTest(gesture.location(in: view), options: nil)
            guard let hit = hits.first(where: { $0.node === pickable }) else {
                onSelect(nil)
                return
            }

            let local = Vec(Float(hit.localCoordinates.x), Float(hit.localCoordinates.y), Float(hit.localCoordinates.z))
            var nearest = 0
            var best = Float.greatestFiniteMagnitude
            for (index, position) in mesh.positions.enumerated() {
                let d = simd_distance_squared(position, local)
                if d < best { best = d; nearest = index }
            }

            var chosen: MuscleGroup?
            var strongest: Float = 0.25
            for (column, muscle) in BodyAsset.muscleOrder.enumerated() {
                let w = mesh.weight(vertex: nearest, column: column)
                if w > strongest { strongest = w; chosen = muscle }
            }
            onSelect(chosen)
        }

        // MARK: Labels

        /// Runs every frame: works out where each label's muscle is on screen.
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            labelLock.lock()
            let targets = labelTargets
            let anchors = self.anchors
            labelLock.unlock()
            guard !targets.isEmpty, !anchors.isEmpty else {
                publish([])
                return
            }

            let camera = cameraNode.presentation.simdWorldPosition
            let node = figure.presentation
            var best: [MuscleGroup: (point: CGPoint, facing: Float)] = [:]

            for anchor in anchors where targets.contains(anchor.muscle) {
                let world = node.simdConvertPosition(anchor.position, to: nil)
                let normal = simd_normalize(node.simdConvertVector(anchor.normal, to: nil))
                let facing = simd_dot(normal, simd_normalize(camera - world))
                if facing < 0.25 { continue }
                if let existing = best[anchor.muscle], existing.facing >= facing { continue }

                let projected = renderer.projectPoint(SCNVector3(world.x, world.y, world.z))
                best[anchor.muscle] = (CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y)), facing)
            }

            let labels = best.map { MuscleLabel(muscle: $0.key, point: $0.value.point) }
                .sorted { $0.muscle.rawValue < $1.muscle.rawValue }
            publish(labels)
        }

        private func publish(_ labels: [MuscleLabel]) {
            guard labels != lastPublished else { return }
            lastPublished = labels
            DispatchQueue.main.async { [weak self] in
                self?.onLabels(labels)
            }
        }

        // MARK: Scene

        private func buildScene() {
            scene.background.contents = Hologram.background
            scene.rootNode.addChildNode(figure)
            for node in [fillNode, lineNode, haloNode, crystalFillNode, crystalEdgeNode, crystalDotNode] {
                figure.addChildNode(node)
            }
            crystalFillNode.renderingOrder = 20
            crystalEdgeNode.renderingOrder = 21
            crystalDotNode.renderingOrder = 22
            lineNode.renderingOrder = 23
            haloNode.renderingOrder = 10
            haloNode.geometry = nil

            cameraNode.camera = SCNCamera()
            cameraNode.camera?.wantsHDR = true            // HDR + bloom is what makes the thin lines glow
            cameraNode.camera?.wantsExposureAdaptation = false
            scene.rootNode.addChildNode(cameraNode)

            // Soft light so the raised muscles show their form (Lines and Grid styles).
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 450
            scene.rootNode.addChildNode(ambient)

            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.intensity = 900
            key.eulerAngles = SCNVector3(-0.5, 0.45, 0)
            scene.rootNode.addChildNode(key)

            let rim = SCNNode()
            rim.light = SCNLight()
            rim.light?.type = .directional
            rim.light?.intensity = 350
            rim.eulerAngles = SCNVector3(-0.2, -0.8, 0)
            scene.rootNode.addChildNode(rim)

            // A faint glowing disc under the feet (Lines and Grid styles).
            let floor = SCNCylinder(radius: 1.9, height: 0.02)
            floor.materials = [Coordinator.constantMaterial(Hologram.glow, alpha: 0.18, additive: true)]
            legacyFloor.geometry = floor
            legacyFloor.position = SCNVector3(0, -0.02, 0)
            scene.rootNode.addChildNode(legacyFloor)

        }

        /// Camera and backdrop for a style. The crystal style looks at the figure from slightly above
        /// with a long lens, against a deep-blue glow.
        private func applySceneStyle(_ style: HologramStyle) {
            sceneStyle = style
            let isCrystal = style == .crystal
            legacyFloor.isHidden = isCrystal

            let camera = cameraNode.camera
            if isCrystal {
                let elevation: Float = 0.17
                let distance: Float = 40
                camera?.fieldOfView = 12.5
                camera?.bloomIntensity = 1.4
                camera?.bloomThreshold = 0.25
                camera?.bloomBlurRadius = 12
                cameraNode.position = SCNVector3(0, 3.6 + distance * sin(elevation), distance * cos(elevation))
                cameraNode.eulerAngles = SCNVector3(-elevation, 0, 0)
                scene.background.contents = Hologram.crystalBackdrop
            } else {
                camera?.fieldOfView = 30
                camera?.bloomIntensity = 1.0
                camera?.bloomThreshold = 0.4
                camera?.bloomBlurRadius = 9
                cameraNode.position = SCNVector3(0, 3.5, 16)
                cameraNode.eulerAngles = SCNVector3(0, 0, 0)
                scene.background.contents = Hologram.background
            }
        }

        private static func litMaterial() -> SCNMaterial {
            let material = SCNMaterial()
            material.lightingModel = .lambert
            material.diffuse.contents = UIColor.white
            return material
        }

        private static func constantMaterial(_ color: UIColor, alpha: CGFloat = 1, additive: Bool = false) -> SCNMaterial {
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = color
            material.transparency = alpha
            if additive {
                material.blendMode = .add
                material.writesToDepthBuffer = false
            }
            return material
        }

        /// Translucent, additive, visible from both sides: front and back facets add up like glass.
        private static func glassMaterial(alpha: CGFloat) -> SCNMaterial {
            let material = constantMaterial(.white, alpha: alpha, additive: true)
            material.isDoubleSided = true
            return material
        }

        private static func colorSource(_ colors: [SIMD4<Float>]) -> SCNGeometrySource {
            let data = colors.withUnsafeBufferPointer { Data(buffer: $0) }
            return SCNGeometrySource(data: data,
                                     semantic: .color,
                                     vectorCount: colors.count,
                                     usesFloatComponents: true,
                                     componentsPerVector: 4,
                                     bytesPerComponent: MemoryLayout<Float>.size,
                                     dataOffset: 0,
                                     dataStride: MemoryLayout<SIMD4<Float>>.stride)
        }

        private static func scnVectors(_ vectors: [Vec]) -> [SCNVector3] {
            vectors.map { SCNVector3($0.x, $0.y, $0.z) }
        }

        // MARK: Building the body

        /// Reshaping the body and building its lines takes a moment, so it happens off the main
        /// thread. The old body stays on screen until the new one is ready.
        private func loadBody(_ profile: BodyProfile, style: HologramStyle) {
            currentProfile = profile
            currentStyle = style
            buildGeneration += 1
            let generation = buildGeneration

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let base = BodyAsset.loadBase() else { return }
                let mesh = BodyAsset.morph(base, profile: profile)
                let lines = BodyAsset.lines(for: mesh, style: style)
                let anchors = BodyAsset.anchors(for: mesh)
                let crystal = style == .crystal && !base.lowPolyTriangles.isEmpty
                    ? BodyAsset.crystal(for: mesh, triangles: base.lowPolyTriangles)
                    : nil

                DispatchQueue.main.async {
                    guard let self, generation == self.buildGeneration else { return }
                    self.install(mesh: mesh, lines: lines, anchors: anchors, crystal: crystal, style: style)
                }
            }
        }

        private func install(mesh: BodyMeshData, lines: BodyLines, anchors: [BodyAnchor],
                             crystal: BodyAsset.CrystalMesh?, style: HologramStyle) {
            self.mesh = mesh
            self.lines = lines
            self.crystal = crystal

            labelLock.lock()
            self.anchors = anchors
            labelLock.unlock()

            let vertices = SCNGeometrySource(vertices: Coordinator.scnVectors(mesh.positions))
            let normals = SCNGeometrySource(normals: Coordinator.scnVectors(mesh.normals))
            let element = SCNGeometryElement(indices: mesh.triangles.map { Int32($0) }, primitiveType: .triangles)
            vertexSource = vertices
            normalSource = normals
            fillElement = element

            lineVertexSource = SCNGeometrySource(vertices: Coordinator.scnVectors(lines.positions))
            lineElement = SCNGeometryElement(indices: (0..<lines.positions.count).map { Int32($0) },
                                             primitiveType: .line)

            let isCrystal = style == .crystal && crystal != nil
            fillNode.isHidden = isCrystal
            crystalFillNode.isHidden = !isCrystal
            crystalEdgeNode.isHidden = !isCrystal
            crystalDotNode.isHidden = !isCrystal
            // Muscle outlines stay on in the crystal style, but softer so the facets lead.
            lineMaterial.transparency = isCrystal ? 0.6 : 1
            if isCrystal { lineMaterial.blendMode = .add } else { lineMaterial.blendMode = .alpha }

            if let crystal, isCrystal {
                crystalFillSources = [
                    SCNGeometrySource(vertices: Coordinator.scnVectors(crystal.positions)),
                    SCNGeometrySource(normals: Coordinator.scnVectors(crystal.normals))
                ]
                crystalFillElement = SCNGeometryElement(indices: (0..<crystal.positions.count).map { Int32($0) },
                                                        primitiveType: .triangles)
                crystalEdgeSource = SCNGeometrySource(vertices: Coordinator.scnVectors(crystal.edgePositions))
                crystalEdgeElement = SCNGeometryElement(indices: (0..<crystal.edgePositions.count).map { Int32($0) },
                                                        primitiveType: .line)
                crystalDotSource = SCNGeometrySource(vertices: Coordinator.scnVectors(crystal.dotPositions))
                let dots = SCNGeometryElement(indices: (0..<crystal.dotPositions.count).map { Int32($0) },
                                              primitiveType: .point)
                dots.pointSize = 0.05
                dots.minimumPointScreenSpaceRadius = 1.2
                dots.maximumPointScreenSpaceRadius = 3
                crystalDotElement = dots
            }

            // Soft rim glow: a slightly inflated copy, drawn only where its far side peeks out.
            let inflated = zip(mesh.positions, mesh.normals).map { $0 + $1 * 0.07 }
            let halo = SCNGeometry(
                sources: [SCNGeometrySource(vertices: Coordinator.scnVectors(inflated)), normals],
                elements: [element]
            )
            haloMaterial.cullMode = .front
            haloMaterial.transparency = isCrystal ? 0.07 : 0.14
            halo.materials = [haloMaterial]
            haloNode.geometry = halo

            shownHeat = nil
            applyHeat()
        }
    }
}

/// The hologram on a dark backdrop, with a flip button, body settings and legend. Always dark so
/// the glow reads in both light and dark mode.
struct HeatBodyCard: View {
    let heat: [MuscleGroup: Double]

    @AppStorage(StorageKey.bodyGender) private var genderRaw = BodyGender.neutral.rawValue
    @AppStorage(StorageKey.bodyAge) private var age = 28
    @AppStorage(StorageKey.bodyWeightKg) private var weightKg = 70.0
    @AppStorage(StorageKey.bodyHeightCm) private var heightCm = 172.0
    @AppStorage(StorageKey.hologramStyle) private var styleRaw = HologramStyle.crystal.rawValue

    @State private var flipToken = 0
    @State private var showingProfile = false
    @State private var selected: MuscleGroup?
    @State private var labels: [MuscleLabel] = []

    private var profile: BodyProfile {
        BodyProfile(genderRaw: genderRaw, age: age, weightKg: weightKg, heightCm: heightCm)
    }

    private var accessibilitySummary: String {
        let worked = heat.sorted { $0.value > $1.value }
            .map { "\($0.key.title) \(HeatScale.label($0.value).lowercased())" }
        return worked.isEmpty ? "No muscles worked" : worked.joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .top) {
                BodyModelView(
                    heat: heat,
                    profile: profile,
                    style: HologramStyle(rawValue: styleRaw) ?? .crystal,
                    flipToken: flipToken,
                    selected: selected,
                    onSelect: { tapped in
                        // Tapping the same muscle again, or empty space, clears the label.
                        selected = (tapped == selected) ? nil : tapped
                    },
                    onLabels: { labels = $0 }
                )
                .frame(height: 440)
                .accessibilityElement()
                .accessibilityLabel("3D muscle heat map")
                .accessibilityValue(accessibilitySummary)

                MuscleLabelsOverlay(labels: labels, heat: heat, selected: selected)
                    .frame(height: 440)

                HStack {
                    Button {
                        showingProfile = true
                    } label: {
                        Label("My body", systemImage: "person.crop.circle")
                    }
                    Spacer()
                    Button {
                        flipToken += 1
                    } label: {
                        Label("Flip", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(12)
            }

            Text("Drag to rotate · tap a muscle to name it")
                .font(.caption)
                .foregroundStyle(.secondary)

            HeatLegend()
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
        }
        .background(Color(Hologram.background))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showingProfile) {
            NavigationStack {
                BodyProfileView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingProfile = false }
                        }
                    }
            }
        }
    }
}

/// Name tags with leader lines pointing at each worked (or tapped) muscle.
struct MuscleLabelsOverlay: View {
    let labels: [MuscleLabel]
    let heat: [MuscleGroup: Double]
    let selected: MuscleGroup?

    private struct Placed: Identifiable {
        let id: MuscleGroup
        let anchor: CGPoint
        let pill: CGPoint
        let edge: CGPoint
        let leftSide: Bool
    }

    private let pillWidth: CGFloat = 92
    private let pillHeight: CGFloat = 32

    /// Labels sit in the left and right margins, top to bottom, nudged apart so they never overlap.
    private func place(in size: CGSize) -> [Placed] {
        var placed: [Placed] = []
        for leftSide in [true, false] {
            let side = labels.filter { ($0.point.x < size.width / 2) == leftSide }.sorted { $0.point.y < $1.point.y }
            var lastY: CGFloat = -.infinity
            for label in side {
                let y = min(max(label.point.y, lastY + pillHeight + 4, pillHeight / 2 + 4), size.height - pillHeight / 2 - 4)
                lastY = y
                let centerX = leftSide ? pillWidth / 2 + 6 : size.width - pillWidth / 2 - 6
                let edgeX = leftSide ? centerX + pillWidth / 2 : centerX - pillWidth / 2
                placed.append(Placed(id: label.muscle, anchor: label.point,
                                     pill: CGPoint(x: centerX, y: y), edge: CGPoint(x: edgeX, y: y),
                                     leftSide: leftSide))
            }
        }
        return placed
    }

    var body: some View {
        GeometryReader { geometry in
            ForEach(place(in: geometry.size)) { item in
                let value = heat[item.id] ?? 0
                let color = value > 0 ? HeatScale.color(value) : Color.white.opacity(0.7)

                Path { path in
                    path.move(to: item.anchor)
                    path.addLine(to: item.edge)
                }
                .stroke(color.opacity(0.85), lineWidth: 1)

                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .position(item.anchor)

                VStack(spacing: 0) {
                    Text(item.id.title)
                        .font(.caption2.weight(.semibold))
                    Text(value > 0 ? HeatScale.label(value) : "Not worked")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(width: pillWidth, height: pillHeight)
                .background(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(color, lineWidth: selected == item.id ? 2 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .position(item.pill)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A cold-to-hot gradient bar, matching the colors on the body.
struct HeatLegend: View {
    var body: some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(HeatScale.gradient)
                .frame(height: 8)
            HStack {
                Text("Not used")
                Spacer()
                Text("Light")
                Spacer()
                Text("Moderate")
                Spacer()
                Text("Max")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Color scale from blue, not used, to red, maximum effort")
    }
}

/// Text list of worked muscles, strongest first. Also keeps the screen usable without color.
struct MuscleBreakdownList: View {
    let heat: [MuscleGroup: Double]

    private var rows: [(muscle: MuscleGroup, value: Double)] {
        heat.map { (muscle: $0.key, value: $0.value) }
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.muscle.title < rhs.muscle.title
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                Text("No muscles tagged for this workout.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows, id: \.muscle) { row in
                    HStack {
                        Circle()
                            .fill(HeatScale.color(row.value))
                            .frame(width: 12, height: 12)
                        Text(row.muscle.title)
                        Spacer()
                        Text(HeatScale.label(row.value))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)

                    if row.muscle != rows.last?.muscle {
                        Divider()
                    }
                }
            }
        }
    }
}
