//
//  BodyAsset.swift
//  WorkoutTracker
//
//  Loads the real human body meshes and prepares them for the hologram: smooth normals,
//  horizontal contour lines, and per-vertex heat colors.
//
//  The meshes are built from the MakeHuman base mesh and shape targets, which are released
//  under CC0 (public domain): https://github.com/makehumancommunity/makehuman
//  Each vertex carries a weight (0–255) for each of the 14 muscle groups, so a muscle's heat
//  fades smoothly across the body instead of showing hard edges.
//

import Foundation
import SceneKit
import simd

enum BodyType: String, CaseIterable, Identifiable {
    case male, female

    var id: String { rawValue }
    var title: String { self == .male ? "Male" : "Female" }
}

extension HeatLevel {
    /// Same colors as `uiColor`, as linear RGB for the vertex-color math.
    var rgb: SIMD3<Float> {
        switch self {
        case .none: return SIMD3(0.5, 0.5, 0.5)
        case .light: return SIMD3(1.00, 0.84, 0.20)
        case .moderate: return SIMD3(1.00, 0.54, 0.10)
        case .heavy: return SIMD3(0.93, 0.16, 0.16)
        }
    }
}

struct BodyMeshData {
    typealias Vec = SIMD3<Float>

    let positions: [Vec]
    let normals: [Vec]
    /// Three indices per triangle.
    let triangles: [UInt16]
    /// `vertexCount × muscleCount` weights, 0–255.
    let weights: [UInt8]
    let muscleCount: Int

    var vertexCount: Int { positions.count }
}

/// Horizontal slices through the body: two vertices per line segment, each expressed as a
/// blend between two mesh vertices so its color can follow the heat map.
struct BodyContours {
    let positions: [SIMD3<Float>]
    let from: [Int32]
    let to: [Int32]
    let blend: [Float]
}

enum BodyAsset {
    typealias Vec = SIMD3<Float>

    /// Order of the weight columns in the data files.
    static let muscleOrder: [MuscleGroup] = [
        .chest, .shoulders, .biceps, .triceps, .forearms, .abs, .obliques,
        .traps, .lats, .lowerBack, .glutes, .quads, .hamstrings, .calves
    ]

    // Hologram palette
    static let baseFill = SIMD4<Float>(0.02, 0.08, 0.18, 1)
    static let baseLine = SIMD3<Float>(0.22, 0.62, 1.0)

    private final class BundleToken {}

    // MARK: Loading

    static func load(_ type: BodyType) -> BodyMeshData? {
        let bundle = Bundle(for: BundleToken.self)
        guard let bodyURL = bundle.url(forResource: "body_\(type.rawValue)", withExtension: "bin"),
              let facesURL = bundle.url(forResource: "body_faces", withExtension: "bin"),
              let body = try? Data(contentsOf: bodyURL),
              let faces = try? Data(contentsOf: facesURL),
              body.count >= 8, faces.count >= 4 else { return nil }

        let vertexCount = Int(readUInt32(body, at: 0))
        let muscleCount = Int(readUInt32(body, at: 4))
        let positionsEnd = 8 + vertexCount * 12
        let weightsEnd = positionsEnd + vertexCount * muscleCount
        guard muscleCount == muscleOrder.count, body.count >= weightsEnd else { return nil }

        let floats: [Float] = copyArray(body, from: 8, count: vertexCount * 3)
        let positions = (0..<vertexCount).map { Vec(floats[$0 * 3], floats[$0 * 3 + 1], floats[$0 * 3 + 2]) }
        let weights: [UInt8] = copyArray(body, from: positionsEnd, count: vertexCount * muscleCount)

        let triangleCount = Int(readUInt32(faces, at: 0))
        guard faces.count >= 4 + triangleCount * 6 else { return nil }
        let triangles: [UInt16] = copyArray(faces, from: 4, count: triangleCount * 3)
        guard triangles.allSatisfy({ Int($0) < vertexCount }) else { return nil }

        return BodyMeshData(positions: positions,
                            normals: smoothNormals(positions: positions, triangles: triangles),
                            triangles: triangles,
                            weights: weights,
                            muscleCount: muscleCount)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset..<(offset + 4)) }
        return UInt32(littleEndian: value)
    }

    private static func copyArray<T>(_ data: Data, from offset: Int, count: Int) -> [T] where T: ExpressibleByIntegerLiteral {
        var result = [T](repeating: 0, count: count)
        let byteCount = count * MemoryLayout<T>.stride
        result.withUnsafeMutableBytes { buffer in
            _ = data.copyBytes(to: buffer, from: offset..<(offset + byteCount))
        }
        return result
    }

    // MARK: Normals

    static func smoothNormals(positions: [Vec], triangles: [UInt16]) -> [Vec] {
        var normals = [Vec](repeating: .zero, count: positions.count)
        var i = 0
        while i + 2 < triangles.count {
            let a = Int(triangles[i]), b = Int(triangles[i + 1]), c = Int(triangles[i + 2])
            let face = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            normals[a] += face
            normals[b] += face
            normals[c] += face
            i += 3
        }
        return normals.map { n in
            let length = simd_length(n)
            return length > 1e-9 ? n / length : Vec(0, 0, 1)
        }
    }

    // MARK: Contour lines

    /// Slices the body with evenly spaced horizontal planes, giving the scan-line look.
    static func contours(for mesh: BodyMeshData, step: Float = 0.06, lift: Float = 0.006) -> BodyContours {
        let offset: Float = 0.0137   // keeps planes off exact vertex heights
        var positions: [Vec] = []
        var from: [Int32] = []
        var to: [Int32] = []
        var blend: [Float] = []

        var i = 0
        while i + 2 < mesh.triangles.count {
            let idx = [Int(mesh.triangles[i]), Int(mesh.triangles[i + 1]), Int(mesh.triangles[i + 2])]
            i += 3

            let ys = idx.map { mesh.positions[$0].y }
            guard let lowest = ys.min(), let highest = ys.max() else { continue }
            let k0 = Int(((lowest - offset) / step).rounded(.up))
            let k1 = Int(((highest - offset) / step).rounded(.down))
            if k0 > k1 { continue }

            for k in k0...k1 {
                let y = offset + Float(k) * step
                var crossings: [(Int, Int, Float)] = []
                for (e0, e1) in [(0, 1), (1, 2), (2, 0)] {
                    let a = idx[e0], b = idx[e1]
                    let ya = mesh.positions[a].y, yb = mesh.positions[b].y
                    if (ya - y) * (yb - y) < 0 {
                        crossings.append((a, b, (y - ya) / (yb - ya)))
                    }
                }
                guard crossings.count == 2 else { continue }
                for (a, b, t) in crossings {
                    let point = mesh.positions[a] * (1 - t) + mesh.positions[b] * t
                    let normal = simd_normalize(mesh.normals[a] * (1 - t) + mesh.normals[b] * t)
                    positions.append(point + normal * lift)
                    from.append(Int32(a))
                    to.append(Int32(b))
                    blend.append(t)
                }
            }
        }
        return BodyContours(positions: positions, from: from, to: to, blend: blend)
    }

    // MARK: Heat colors

    /// Per-vertex colors for the solid body and for the contour lines.
    static func vertexColors(for mesh: BodyMeshData, heat: [MuscleGroup: HeatLevel])
        -> (fill: [SIMD4<Float>], line: [SIMD4<Float>]) {

        let active: [(column: Int, color: SIMD3<Float>)] = muscleOrder.enumerated().compactMap { column, muscle in
            guard let level = heat[muscle], level != HeatLevel.none else { return nil }
            return (column, level.rgb)
        }

        var fill = [SIMD4<Float>](repeating: baseFill, count: mesh.vertexCount)
        var line = [SIMD4<Float>](repeating: SIMD4(baseLine.x, baseLine.y, baseLine.z, 1), count: mesh.vertexCount)
        if active.isEmpty { return (fill, line) }

        for v in 0..<mesh.vertexCount {
            var f = SIMD3<Float>(baseFill.x, baseFill.y, baseFill.z)
            var l = baseLine
            for (column, color) in active {
                let w = Float(mesh.weights[v * mesh.muscleCount + column]) / 255
                if w <= 0 { continue }
                f = f * (1 - w) + color * 0.3 * w
                l = l * (1 - w) + color * w
            }
            fill[v] = SIMD4(f.x, f.y, f.z, 1)
            line[v] = SIMD4(l.x, l.y, l.z, 1)
        }
        return (fill, line)
    }

    /// Colors for the contour-line vertices, blended from the two mesh vertices each one sits between.
    static func lineColors(for contours: BodyContours, vertexLineColors: [SIMD4<Float>]) -> [SIMD4<Float>] {
        var colors = [SIMD4<Float>]()
        colors.reserveCapacity(contours.positions.count)
        for v in 0..<contours.positions.count {
            let a = vertexLineColors[Int(contours.from[v])]
            let b = vertexLineColors[Int(contours.to[v])]
            colors.append(a * (1 - contours.blend[v]) + b * contours.blend[v])
        }
        return colors
    }
}
