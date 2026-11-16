//
//  BodyModelView.swift
//  WorkoutTracker
//
//  A 3D human figure built from SceneKit primitives. Each muscle group is its own set of
//  nodes, tinted yellow / orange / red depending on how hard it was worked.
//

import SwiftUI
import SceneKit

struct BodyModelView: UIViewRepresentable {
    var heat: [MuscleGroup: HeatLevel]
    /// Increment to spin the figure to its other side.
    var flipToken: Int

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(pan)
        context.coordinator.apply(heat: heat, isDark: colorScheme == .dark)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.apply(heat: heat, isDark: colorScheme == .dark)
        context.coordinator.flip(ifTokenChanged: flipToken)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        let scene = SCNScene()

        private let figure = SCNNode()
        private var muscleMaterials: [MuscleGroup: [SCNMaterial]] = [:]
        private var baseMaterials: [SCNMaterial] = []
        private var lastHeat: [MuscleGroup: HeatLevel]?
        private var lastDark: Bool?
        private var lastFlipToken = 0

        override init() {
            super.init()
            buildScene()
        }

        // MARK: Updating

        func apply(heat: [MuscleGroup: HeatLevel], isDark: Bool) {
            guard heat != lastHeat || isDark != lastDark else { return }
            let animated = lastHeat != nil
            lastHeat = heat
            lastDark = isDark

            let baseColor = isDark
                ? UIColor(red: 0.20, green: 0.22, blue: 0.27, alpha: 1)
                : UIColor(red: 0.80, green: 0.82, blue: 0.86, alpha: 1)
            let idleColor = isDark
                ? UIColor(red: 0.32, green: 0.35, blue: 0.43, alpha: 1)
                : UIColor(red: 0.63, green: 0.67, blue: 0.74, alpha: 1)

            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 0.45 : 0
            for material in baseMaterials {
                material.diffuse.contents = baseColor
            }
            for (muscle, materials) in muscleMaterials {
                let level = heat[muscle] ?? HeatLevel.none
                for material in materials {
                    if level == .none {
                        material.diffuse.contents = idleColor
                        material.emission.contents = UIColor.black
                    } else {
                        material.diffuse.contents = level.uiColor
                        // A slight glow so heat reads clearly, especially in dark mode.
                        material.emission.contents = level.uiColor.withAlphaComponent(isDark ? 0.35 : 0.15)
                    }
                }
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

        // MARK: Building the figure

        private func buildScene() {
            scene.background.contents = UIColor.clear
            scene.rootNode.addChildNode(figure)
            buildFigure()

            let camera = SCNNode()
            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 30
            camera.position = SCNVector3(0, 3.5, 16)
            scene.rootNode.addChildNode(camera)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 550
            scene.rootNode.addChildNode(ambient)

            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.intensity = 900
            key.eulerAngles = SCNVector3(-0.5, 0.5, 0)
            scene.rootNode.addChildNode(key)

            let fill = SCNNode()
            fill.light = SCNLight()
            fill.light?.type = .directional
            fill.light?.intensity = 400
            fill.eulerAngles = SCNVector3(-0.2, -0.7, 0)
            scene.rootNode.addChildNode(fill)
        }

        /// Adds one piece of the body. Pass `muscle` to make it tint with that muscle's heat.
        private func add(_ geometry: SCNGeometry,
                         at position: SCNVector3,
                         muscle: MuscleGroup? = nil,
                         scale: SCNVector3 = SCNVector3(1, 1, 1)) {
            let material = SCNMaterial()
            material.lightingModel = .blinn
            material.specular.contents = UIColor(white: 0.3, alpha: 1)
            geometry.materials = [material]

            if let muscle {
                muscleMaterials[muscle, default: []].append(material)
            } else {
                baseMaterials.append(material)
            }

            let node = SCNNode(geometry: geometry)
            node.position = position
            node.scale = scale
            figure.addChildNode(node)
        }

        /// Front of the figure faces +z (toward the camera). Feet at y = 0, head top at y ≈ 7.
        private func buildFigure() {
            let sides: [Float] = [-1, 1]

            // Head, neck, torso and pelvis (neutral base)
            add(SCNSphere(radius: 0.46), at: SCNVector3(0, 6.55, 0))
            add(SCNCylinder(radius: 0.17, height: 0.4), at: SCNVector3(0, 6.05, 0))
            add(SCNBox(width: 1.7, height: 2.5, length: 0.78, chamferRadius: 0.32), at: SCNVector3(0, 4.55, 0))
            add(SCNBox(width: 1.5, height: 0.7, length: 0.74, chamferRadius: 0.3), at: SCNVector3(0, 3.2, 0))

            // Front of the torso
            for s in sides {
                add(SCNBox(width: 0.8, height: 0.72, length: 0.22, chamferRadius: 0.12),
                    at: SCNVector3(s * 0.42, 5.15, 0.33), muscle: .chest)
                // Obliques wrap the sides, so they show from both front and back.
                add(SCNBox(width: 0.22, height: 1.1, length: 0.55, chamferRadius: 0.08),
                    at: SCNVector3(s * 0.8, 4.2, 0), muscle: .obliques)
                // Six-pack: three rows per side.
                for y: Float in [4.65, 4.2, 3.75] {
                    add(SCNBox(width: 0.36, height: 0.38, length: 0.2, chamferRadius: 0.08),
                        at: SCNVector3(s * 0.2, y, 0.35), muscle: .abs)
                }
            }

            // Back of the torso
            add(SCNBox(width: 1.2, height: 0.55, length: 0.2, chamferRadius: 0.1),
                at: SCNVector3(0, 5.6, -0.34), muscle: .traps)
            add(SCNBox(width: 0.9, height: 0.8, length: 0.2, chamferRadius: 0.1),
                at: SCNVector3(0, 3.7, -0.34), muscle: .lowerBack)
            for s in sides {
                add(SCNBox(width: 0.7, height: 1.3, length: 0.2, chamferRadius: 0.1),
                    at: SCNVector3(s * 0.5, 4.75, -0.34), muscle: .lats)
            }

            // Arms
            for s in sides {
                add(SCNSphere(radius: 0.36), at: SCNVector3(s * 1.05, 5.45, 0), muscle: .shoulders)
                add(SCNCapsule(capRadius: 0.24, height: 1.5), at: SCNVector3(s * 1.22, 4.6, 0))
                add(SCNCapsule(capRadius: 0.17, height: 1.15), at: SCNVector3(s * 1.22, 4.65, 0.15), muscle: .biceps)
                add(SCNCapsule(capRadius: 0.17, height: 1.15), at: SCNVector3(s * 1.22, 4.65, -0.15), muscle: .triceps)
                add(SCNCapsule(capRadius: 0.21, height: 1.45), at: SCNVector3(s * 1.27, 3.25, 0), muscle: .forearms)
                add(SCNSphere(radius: 0.17), at: SCNVector3(s * 1.3, 2.4, 0))
            }

            // Legs
            for s in sides {
                add(SCNSphere(radius: 0.42), at: SCNVector3(s * 0.38, 3.05, -0.18),
                    muscle: .glutes, scale: SCNVector3(1, 1.05, 0.85))
                add(SCNCapsule(capRadius: 0.3, height: 2.1), at: SCNVector3(s * 0.4, 1.95, 0))
                add(SCNCapsule(capRadius: 0.31, height: 1.85), at: SCNVector3(s * 0.4, 2.05, 0.1), muscle: .quads)
                add(SCNCapsule(capRadius: 0.29, height: 1.7), at: SCNVector3(s * 0.4, 2.0, -0.1), muscle: .hamstrings)
                add(SCNSphere(radius: 0.27), at: SCNVector3(s * 0.4, 1.1, 0))
                add(SCNCapsule(capRadius: 0.19, height: 1.5), at: SCNVector3(s * 0.4, 0.75, 0.03))
                add(SCNCapsule(capRadius: 0.23, height: 1.45), at: SCNVector3(s * 0.4, 0.75, -0.07), muscle: .calves)
                add(SCNBox(width: 0.36, height: 0.18, length: 0.7, chamferRadius: 0.08), at: SCNVector3(s * 0.4, 0.09, 0.15))
            }
        }
    }
}

// MARK: - Card, legend and breakdown

/// The 3D model on a themed backdrop, with a flip button and legend.
struct HeatBodyCard: View {
    let heat: [MuscleGroup: HeatLevel]

    @State private var flipToken = 0
    @Environment(\.colorScheme) private var colorScheme

    private var backdrop: LinearGradient {
        let colors: [Color] = colorScheme == .dark
            ? [Color(red: 0.07, green: 0.08, blue: 0.11), Color(red: 0.14, green: 0.16, blue: 0.22)]
            : [Color(red: 0.95, green: 0.96, blue: 0.99), Color(red: 0.83, green: 0.87, blue: 0.94)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var accessibilitySummary: String {
        let worked = heat.sorted { $0.value > $1.value }
            .map { "\($0.key.title) \($0.value.title.lowercased())" }
        return worked.isEmpty ? "No muscles worked" : worked.joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                BodyModelView(heat: heat, flipToken: flipToken)
                    .frame(height: 420)
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
        .background(backdrop)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
