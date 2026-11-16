//
//  BodyModelView.swift
//  WorkoutTracker
//
//  A holographic 3D human: a dark translucent body, glowing contour lines and a soft rim
//  glow. Worked muscles light up yellow / orange / red in the same hologram style.
//

import SwiftUI
import SceneKit

/// Colors shared by the 3D scene and the card around it.
enum Hologram {
    static let background = UIColor(red: 0.03, green: 0.05, blue: 0.10, alpha: 1)
    static let bodyFill = UIColor(red: 0.02, green: 0.08, blue: 0.18, alpha: 1)
    static let muscleFill = UIColor(red: 0.04, green: 0.13, blue: 0.27, alpha: 1)
    static let bodyLine = UIColor(red: 0.22, green: 0.62, blue: 1.0, alpha: 1)
    static let muscleLine = UIColor(red: 0.30, green: 0.68, blue: 1.0, alpha: 1)
    static let glow = UIColor(red: 0.25, green: 0.60, blue: 1.0, alpha: 1)
}

struct BodyModelView: UIViewRepresentable {
    var heat: [MuscleGroup: HeatLevel]
    var bodyType: BodyType
    /// Increment to spin the figure to its other side.
    var flipToken: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.backgroundColor = Hologram.background
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(pan)
        context.coordinator.update(bodyType: bodyType, heat: heat)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(bodyType: bodyType, heat: heat)
        context.coordinator.flip(ifTokenChanged: flipToken)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        let scene = SCNScene()

        private let figure = SCNNode()
        private var muscleFills: [MuscleGroup: [SCNMaterial]] = [:]
        private var muscleLines: [MuscleGroup: [SCNMaterial]] = [:]
        private var currentBodyType: BodyType?
        private var lastHeat: [MuscleGroup: HeatLevel]?
        private var lastFlipToken = 0

        override init() {
            super.init()
            buildScene()
        }

        // MARK: Updating

        func update(bodyType: BodyType, heat: [MuscleGroup: HeatLevel]) {
            if bodyType != currentBodyType {
                rebuildFigure(for: bodyType)
            }
            apply(heat: heat)
        }

        private func apply(heat: [MuscleGroup: HeatLevel]) {
            guard heat != lastHeat else { return }
            let animated = lastHeat != nil
            lastHeat = heat

            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 0.45 : 0
            for muscle in MuscleGroup.allCases {
                let level = heat[muscle] ?? HeatLevel.none
                let line: UIColor
                let fill: UIColor
                if level == HeatLevel.none {
                    line = Hologram.muscleLine
                    fill = Hologram.muscleFill
                } else {
                    line = level.uiColor
                    fill = level.uiColor.withAlphaComponent(1).scaled(by: 0.32)
                }
                muscleLines[muscle]?.forEach { $0.diffuse.contents = line }
                muscleFills[muscle]?.forEach { $0.diffuse.contents = fill }
            }
            SCNTransaction.commit()
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

        // MARK: Scene

        private func buildScene() {
            scene.background.contents = Hologram.background
            scene.rootNode.addChildNode(figure)

            let camera = SCNNode()
            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 30
            // HDR + bloom is what makes the thin lines glow.
            camera.camera?.wantsHDR = true
            camera.camera?.wantsExposureAdaptation = false
            camera.camera?.bloomIntensity = 1.1
            camera.camera?.bloomThreshold = 0.35
            camera.camera?.bloomBlurRadius = 9
            camera.position = SCNVector3(0, 3.5, 16)
            scene.rootNode.addChildNode(camera)

            // A faint glowing disc under the feet.
            let floor = SCNCylinder(radius: 1.9, height: 0.02)
            floor.materials = [constantMaterial(Hologram.glow, alpha: 0.18, additive: true)]
            let floorNode = SCNNode(geometry: floor)
            floorNode.position = SCNVector3(0, -0.02, 0)
            scene.rootNode.addChildNode(floorNode)
        }

        private func constantMaterial(_ color: UIColor, alpha: CGFloat = 1, additive: Bool = false) -> SCNMaterial {
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

        private func rebuildFigure(for type: BodyType) {
            currentBodyType = type
            lastHeat = nil
            muscleFills = [:]
            muscleLines = [:]
            figure.childNodes.forEach { $0.removeFromParentNode() }

            var tubeKeys: [String: [BodyKey]] = [:]

            for tube in BodySpec.tubes(for: type) {
                tubeKeys[tube.name] = tube.keys
                for side in (tube.mirrored ? [Float(-1), 1] : [Float(1)]) {
                    let grid = BodyMesher.tubeGrid(tube.keys, side: side)

                    // Dark translucent body.
                    let fill = SCNNode(geometry: BodyMesher.tubeMesh(grid))
                    fill.geometry?.materials = [constantMaterial(Hologram.bodyFill)]
                    figure.addChildNode(fill)

                    // Glowing contour lines.
                    let lines = SCNNode(geometry: BodyMesher.contours(grid, wrap: true))
                    lines.geometry?.materials = [constantMaterial(Hologram.bodyLine)]
                    figure.addChildNode(lines)

                    // Soft rim glow: an inflated shell seen only from behind its edges.
                    let halo = SCNNode(geometry: BodyMesher.tubeMesh(grid, inflate: 0.07))
                    let haloMaterial = constantMaterial(Hologram.glow, alpha: 0.16, additive: true)
                    haloMaterial.cullMode = .front
                    halo.geometry?.materials = [haloMaterial]
                    halo.renderingOrder = 10
                    figure.addChildNode(halo)
                }
            }

            for patch in BodySpec.patches(for: type) {
                guard let keys = tubeKeys[patch.host] else { continue }
                for side in (patch.mirrored ? [Float(-1), 1] : [Float(1)]) {
                    let grid = BodyMesher.patchGrid(keys, side: side, spec: patch)

                    let fillMaterial = constantMaterial(Hologram.muscleFill)
                    let fill = SCNNode(geometry: BodyMesher.patchMesh(grid))
                    fill.geometry?.materials = [fillMaterial]
                    figure.addChildNode(fill)

                    let lineMaterial = constantMaterial(Hologram.muscleLine)
                    let lines = SCNNode(geometry: BodyMesher.contours(grid, wrap: false))
                    lines.geometry?.materials = [lineMaterial]
                    figure.addChildNode(lines)

                    muscleFills[patch.muscle, default: []].append(fillMaterial)
                    muscleLines[patch.muscle, default: []].append(lineMaterial)
                }
            }
        }
    }
}

private extension UIColor {
    /// Darkens a color toward black, keeping it fully opaque.
    func scaled(by factor: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * factor, green: g * factor, blue: b * factor, alpha: 1)
    }
}

// MARK: - Card, legend and breakdown

/// The hologram on a dark backdrop, with a flip button and legend. Always dark so the glow reads
/// in both light and dark mode.
struct HeatBodyCard: View {
    let heat: [MuscleGroup: HeatLevel]

    @AppStorage(StorageKey.bodyType) private var bodyTypeRaw = BodyType.male.rawValue
    @State private var flipToken = 0

    private var accessibilitySummary: String {
        let worked = heat.sorted { $0.value > $1.value }
            .map { "\($0.key.title) \($0.value.title.lowercased())" }
        return worked.isEmpty ? "No muscles worked" : worked.joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                BodyModelView(heat: heat, bodyType: BodyType(rawValue: bodyTypeRaw) ?? .male, flipToken: flipToken)
                    .frame(height: 440)
                    .accessibilityElement()
                    .accessibilityLabel("3D muscle heat map")
                    .accessibilityValue(accessibilitySummary)

                Button {
                    flipToken += 1
                } label: {
                    Label("Flip", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(12)
            }

            Text("Drag to rotate")
                .font(.caption)
                .foregroundStyle(.secondary)

            HeatLegend()
                .padding(.bottom, 14)
        }
        .background(Color(Hologram.background))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

struct HeatLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach([HeatLevel.none, .light, .moderate, .heavy], id: \.self) { level in
                HStack(spacing: 5) {
                    Circle()
                        .fill(level.color)
                        .frame(width: 10, height: 10)
                    Text(level.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Text list of worked muscles, strongest first. Also keeps the screen usable without color.
struct MuscleBreakdownList: View {
    let heat: [MuscleGroup: HeatLevel]

    private var rows: [(muscle: MuscleGroup, level: HeatLevel)] {
        heat.map { (muscle: $0.key, level: $0.value) }
            .sorted { lhs, rhs in
                lhs.level != rhs.level ? lhs.level > rhs.level : lhs.muscle.title < rhs.muscle.title
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
                            .fill(row.level.color)
                            .frame(width: 12, height: 12)
                        Text(row.muscle.title)
                        Spacer()
                        Text(row.level.title)
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
