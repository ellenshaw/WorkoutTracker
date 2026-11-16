//
//  BodyAsset.swift
//  WorkoutTracker
//
//  Loads the real human body mesh, reshapes it for the user's profile (gender, age, weight),
//  and prepares it for the hologram: smooth normals, horizontal contour lines, heat colors.
//
//  The meshes are built from the MakeHuman base mesh and shape targets, which are released
//  under CC0 (public domain): https://github.com/makehumancommunity/makehuman
//  Each vertex carries a weight (0–255) for each of the 14 muscle groups, so a muscle's heat
//  fades smoothly across the body instead of showing hard edges.
//

import Foundation
import SceneKit
import simd

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

/// The base mesh plus the shape targets it is morphed with. Loaded once.
struct BodyBase {
    let positions: [SIMD3<Float>]
    /// How strongly each vertex is replaced by the smooth head shape (0 = not at all).
    let headMask: [Float]
    /// Vertices used to size the head shape.
    let headCore: [Int]
    let headHeight: Float
    let triangles: [UInt16]
    /// Muscle weights for the base body, `vertexCount × muscleCount`.
    let weights: [UInt8]
    let muscleCount: Int
    /// Shape deltas in the order of `BodyAsset.targetOrder`.
    let targets: [[SIMD3<Float>]]
}

enum BodyAsset {
    typealias Vec = SIMD3<Float>

    /// Order of the weight columns in the data files.
    static let muscleOrder: [MuscleGroup] = [
        .chest, .shoulders, .biceps, .triceps, .forearms, .abs, .obliques,
        .traps, .lats, .lowerBack, .glutes, .quads, .hamstrings, .calves
    ]

    private enum Target: Int {
        case youngMale, youngFemale, oldMale, oldFemale
        case muscleMale, muscleFemale
        case heavyMale, heavyFemale, slimMale, slimFemale
    }

    /// Height of the figure in scene units.
    static let figureHeight: Float = 7.02

    // Hologram palette
    static let baseFill = SIMD4<Float>(0.02, 0.08, 0.18, 1)
    static let baseLine = SIMD3<Float>(0.22, 0.62, 1.0)

    private final class BundleToken {}

    // MARK: Loading

    private static var cachedBase: BodyBase?

    static func loadBase() -> BodyBase? {
        if let cachedBase { return cachedBase }

        let bundle = Bundle(for: BundleToken.self)
        guard let baseURL = bundle.url(forResource: "body_base", withExtension: "bin"),
              let targetsURL = bundle.url(forResource: "body_targets", withExtension: "bin"),
              let facesURL = bundle.url(forResource: "body_faces", withExtension: "bin"),
              let base = try? Data(contentsOf: baseURL),
              let targets = try? Data(contentsOf: targetsURL),
              let faces = try? Data(contentsOf: facesURL),
              base.count >= 16, targets.count >= 8, faces.count >= 4 else { return nil }

        let vertexCount = Int(readUInt32(base, at: 0))
        let muscleCount = Int(readUInt32(base, at: 4))
        let coreCount = Int(readUInt32(base, at: 8))
        let headHeight = readFloat(base, at: 12)

        let positionsStart = 16
        let maskStart = positionsStart + vertexCount * 12
        let coreStart = maskStart + vertexCount
        let weightsStart = coreStart + coreCount * 4
        guard muscleCount == muscleOrder.count, base.count >= weightsStart + vertexCount * muscleCount else { return nil }

        let floats: [Float] = copyArray(base, from: positionsStart, count: vertexCount * 3)
        let positions = vectors(from: floats)
        let mask: [UInt8] = copyArray(base, from: maskStart, count: vertexCount)
        let core: [UInt32] = copyArray(base, from: coreStart, count: coreCount)
        let weights: [UInt8] = copyArray(base, from: weightsStart, count: vertexCount * muscleCount)

        guard Int(readUInt32(targets, at: 0)) == vertexCount else { return nil }
        let targetCount = Int(readUInt32(targets, at: 4))
        guard targetCount == 10, targets.count >= 8 + targetCount * vertexCount * 12 else { return nil }
        let deltas: [[Vec]] = (0..<targetCount).map { index in
            let start = 8 + index * vertexCount * 12
            return vectors(from: copyArray(targets, from: start, count: vertexCount * 3) as [Float])
        }

        let triangleCount = Int(readUInt32(faces, at: 0))
        guard faces.count >= 4 + triangleCount * 6 else { return nil }
        let triangles: [UInt16] = copyArray(faces, from: 4, count: triangleCount * 3)
        guard triangles.allSatisfy({ Int($0) < vertexCount }) else { return nil }

        let loaded = BodyBase(positions: positions,
                              headMask: mask.map { Float($0) / 255 },
                              headCore: core.map { Int($0) },
                              headHeight: headHeight,
                              triangles: triangles,
                              weights: weights,
                              muscleCount: muscleCount,
                              targets: deltas)
        cachedBase = loaded
        return loaded
    }

    /// Convenience: the base body reshaped for a profile.
    static func load(_ profile: BodyProfile = BodyProfile()) -> BodyMeshData? {
        guard let base = loadBase() else { return nil }
        return morph(base, profile: profile)
    }

    private static func vectors(from floats: [Float]) -> [Vec] {
        (0..<(floats.count / 3)).map { Vec(floats[$0 * 3], floats[$0 * 3 + 1], floats[$0 * 3 + 2]) }
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset..<(offset + 4)) }
        return UInt32(littleEndian: value)
    }

    private static func readFloat(_ data: Data, at offset: Int) -> Float {
        Float(bitPattern: readUInt32(data, at: offset))
    }

    private static func copyArray<T>(_ data: Data, from offset: Int, count: Int) -> [T] where T: ExpressibleByIntegerLiteral {
        var result = [T](repeating: 0, count: count)
        let byteCount = count * MemoryLayout<T>.stride
        result.withUnsafeMutableBytes { buffer in
            _ = data.copyBytes(to: buffer, from: offset..<(offset + byteCount))
        }
        return result
    }

    // MARK: Morphing

    /// Reshapes the base body for a profile: blends the male and female shapes, then age,
    /// muscle and weight, rounds the head into a featureless egg, and scales to a fixed height.
    static func morph(_ base: BodyBase, profile: BodyProfile) -> BodyMeshData {
        let male = profile.gender.maleShare
        let female = 1 - male
        let age = profile.ageFactor
        let muscle = profile.muscleFactor
        let weight = profile.weightFactor

        let youngWeight = (1 - age)
        let t = base.targets

        // Coefficients for each target: [target index: weight].
        var coefficients: [(Int, Float)] = [
            (Target.youngMale.rawValue, youngWeight * male),
            (Target.youngFemale.rawValue, youngWeight * female),
            (Target.oldMale.rawValue, age * male),
            (Target.oldFemale.rawValue, age * female),
            (Target.muscleMale.rawValue, muscle * male),
            (Target.muscleFemale.rawValue, muscle * female)
        ]
        if weight >= 0 {
            coefficients.append((Target.heavyMale.rawValue, weight * male))
            coefficients.append((Target.heavyFemale.rawValue, weight * female))
        } else {
            coefficients.append((Target.slimMale.rawValue, -weight * male))
            coefficients.append((Target.slimFemale.rawValue, -weight * female))
        }
        coefficients = coefficients.filter { $0.1 > 0 }

        var positions = base.positions
        for (index, factor) in coefficients {
            let delta = t[index]
            for v in 0..<positions.count {
                positions[v] += delta[v] * factor
            }
        }

        roundHead(&positions, base: base)

        // Feet on the ground, fixed overall height.
        let minY = positions.map(\.y).min() ?? 0
        let maxY = positions.map(\.y).max() ?? 1
        let scale = figureHeight / max(maxY - minY, 0.001)
        for v in 0..<positions.count {
            positions[v] = Vec(positions[v].x, positions[v].y - minY, positions[v].z) * scale
        }

        return BodyMeshData(positions: positions,
                            normals: smoothNormals(positions: positions, triangles: base.triangles),
                            triangles: base.triangles,
                            weights: base.weights,
                            muscleCount: base.muscleCount)
    }

    /// Replaces the face with a smooth egg-shaped head, fitted to this particular body.
    private static func roundHead(_ positions: inout [Vec], base: BodyBase) {
        guard !base.headCore.isEmpty else { return }
        let core = base.headCore.map { positions[$0] }

        func quantile(_ values: [Float], _ q: Float) -> Float {
            let sorted = values.sorted()
            let index = min(max(Int(Float(sorted.count - 1) * q), 0), sorted.count - 1)
            return sorted[index]
        }

        let top = core.map(\.y).max() ?? 0
        let halfWidth = quantile(core.map { abs($0.x) }, 0.97)
        let zBack = quantile(core.map(\.z), 0.02)
        let zFront = quantile(core.map(\.z), 0.90)
        let bottom = top - base.headHeight

        let center = Vec(0, (top + bottom) / 2, (zBack + zFront) / 2)
        let radii = Vec(max(halfWidth, 0.01), max(base.headHeight / 2, 0.01), max((zFront - zBack) / 2, 0.01))

        for v in 0..<positions.count {
            let amount = base.headMask[v]
            if amount <= 0 { continue }
            let offset = positions[v] - center
            let length = simd_length(offset)
            let direction = length > 1e-6 ? offset / length : Vec(0, 1, 0)
            let scaled = direction / radii
            let k = simd_length(scaled)
            let target = center + direction / max(k, 1e-6)
            positions[v] += (target - positions[v]) * amount
        }
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
    static func vertexColors(for mesh: BodyMeshData, heat: [MuscleGroup: Double])
        -> (fill: [SIMD4<Float>], line: [SIMD4<Float>]) {

        let active: [(column: Int, color: SIMD3<Float>)] = muscleOrder.enumerated().compactMap { column, muscle in
            guard let intensity = heat[muscle], intensity > 0 else { return nil }
            return (column, HeatScale.rgb(intensity))
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
