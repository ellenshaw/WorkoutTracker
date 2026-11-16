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
        typealias Vec = SIMD3<Float>

        let scene = SCNScene()

        private let figure = SCNNode()
        private let fillNode = SCNNode()
        private let lineNode = SCNNode()
        private let haloNode = SCNNode()
        private let fillMaterial = Coordinator.constantMaterial(.white)
        private let lineMaterial = Coordinator.constantMaterial(.white)

        private var mesh: BodyMeshData?
        private var contours: BodyContours?
        private var vertexSource: SCNGeometrySource?
        private var normalSource: SCNGeometrySource?
        private var fillElement: SCNGeometryElement?
        private var lineVertexSource: SCNGeometrySource?
        private var lineElement: SCNGeometryElement?

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
                loadBody(bodyType)
            }
            applyHeat(heat)
        }

        private func applyHeat(_ heat: [MuscleGroup: HeatLevel]) {
            guard heat != lastHeat, let mesh, let contours,
                  let vertexSource, let normalSource, let fillElement,
                  let lineVertexSource, let lineElement else { return }
            lastHeat = heat

            let colors = BodyAsset.vertexColors(for: mesh, heat: heat)
            let lineColors = BodyAsset.lineColors(for: contours, vertexLineColors: colors.line)

            let fill = SCNGeometry(sources: [vertexSource, normalSource, Coordinator.colorSource(colors.fill)],
                                   elements: [fillElement])
            fill.materials = [fillMaterial]
            fillNode.geometry = fill

            let lines = SCNGeometry(sources: [lineVertexSource, Coordinator.colorSource(lineColors)],
                                    elements: [lineElement])
            lines.materials = [lineMaterial]
            lineNode.geometry = lines
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
            figure.addChildNode(fillNode)
            figure.addChildNode(lineNode)
            figure.addChildNode(haloNode)

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
            let floorMaterial = Coordinator.constantMaterial(Hologram.glow, alpha: 0.18, additive: true)
            floor.materials = [floorMaterial]
            let floorNode = SCNNode(geometry: floor)
            floorNode.position = SCNVector3(0, -0.02, 0)
            scene.rootNode.addChildNode(floorNode)
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

        /// Loads the mesh for a body type and builds the parts that never change with heat.
        private func loadBody(_ type: BodyType) {
            currentBodyType = type
            lastHeat = nil
            guard let mesh = BodyAsset.load(type) else { return }
            self.mesh = mesh

            let contours = BodyAsset.contours(for: mesh)
            self.contours = contours

            vertexSource = SCNGeometrySource(vertices: Coordinator.scnVectors(mesh.positions))
            normalSource = SCNGeometrySource(normals: Coordinator.scnVectors(mesh.normals))
            fillElement = SCNGeometryElement(indices: mesh.triangles.map { Int32($0) }, primitiveType: .triangles)

            lineVertexSource = SCNGeometrySource(vertices: Coordinator.scnVectors(contours.positions))
            lineElement = SCNGeometryElement(indices: (0..<contours.positions.count).map { Int32($0) },
                                             primitiveType: .line)

            // Soft rim glow: a slightly inflated copy, drawn only where its far side peeks out.
            let inflated = zip(mesh.positions, mesh.normals).map { $0 + $1 * 0.07 }
            let halo = SCNGeometry(
                sources: [SCNGeometrySource(vertices: Coordinator.scnVectors(inflated)),
                          SCNGeometrySource(normals: Coordinator.scnVectors(mesh.normals))],
                elements: [fillElement!]
            )
            let haloMaterial = Coordinator.constantMaterial(Hologram.glow, alpha: 0.16, additive: true)
            haloMaterial.cullMode = .front
            halo.materials = [haloMaterial]
            haloNode.geometry = halo
            haloNode.renderingOrder = 10
        }
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
