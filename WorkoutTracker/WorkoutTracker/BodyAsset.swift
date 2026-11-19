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
    /// The strongest muscle weight at each vertex (0–1): high on muscle, low on skin.
    let maxWeight: [Float]

    var vertexCount: Int { positions.count }

    func weight(vertex: Int, column: Int) -> Float {
        Float(weights[vertex * muscleCount + column]) / 255
    }
}

/// All the lines drawn on the body, two vertices per segment.
struct BodyLines {
    var positions: [SIMD3<Float>] = []
    /// Index into `BodyAsset.muscleOrder`, or -1 for plain skin lines.
    var muscle: [Int8] = []
    /// 0 = skin line, 1 = muscle fibre, 2 = muscle outline.
    var kind: [UInt8] = []
}

/// Where to attach a muscle's name label, and which way that part of the body faces.
struct BodyAnchor {
    let muscle: MuscleGroup
    let position: SIMD3<Float>
    let normal: SIMD3<Float>
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
    let maxWeight: [Float]
    /// Mesh neighbours in compressed form: vertex `v`'s neighbours are
    /// `neighbours[neighbourStart[v]..<neighbourStart[v + 1]]`. Used to smooth the surface.
    let neighbourStart: [Int32]
    let neighbours: [UInt16]
    /// A coarse triangulation (about 2,500 triangles) that reuses a subset of the body's vertices,
    /// so it follows every body shape. Drives the faceted "crystal" look.
    let lowPolyTriangles: [UInt16]
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
    static let skinFill = SIMD3<Float>(0.02, 0.08, 0.18)
    static let muscleFill = SIMD3<Float>(0.05, 0.16, 0.32)
    static let skinLine = SIMD3<Float>(0.18, 0.50, 0.80)
    static let muscleLine = SIMD3<Float>(0.30, 0.70, 1.0)

    private final class BundleToken {}

    // MARK: Loading

    private static var cachedBase: BodyBase?
    private static let cacheLock = NSLock()

    static func loadBase() -> BodyBase? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
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

        let adjacency = buildAdjacency(vertexCount: vertexCount, triangles: triangles)

        var lowPoly: [UInt16] = []
        if let lowURL = bundle.url(forResource: "body_lowpoly", withExtension: "bin"),
           let low = try? Data(contentsOf: lowURL), low.count >= 4 {
            let count = Int(readUInt32(low, at: 0))
            if low.count >= 4 + count * 6 {
                let candidate: [UInt16] = copyArray(low, from: 4, count: count * 3)
                if candidate.allSatisfy({ Int($0) < vertexCount }) { lowPoly = candidate }
            }
        }
        let loaded = BodyBase(positions: positions,
                              headMask: mask.map { Float($0) / 255 },
                              headCore: core.map { Int($0) },
                              headHeight: headHeight,
                              triangles: triangles,
                              weights: weights,
                              muscleCount: muscleCount,
                              maxWeight: (0..<vertexCount).map { v in
                                  Float((0..<muscleCount).map { weights[v * muscleCount + $0] }.max() ?? 0) / 255
                              },
                              neighbourStart: adjacency.start,
                              neighbours: adjacency.list,
                              lowPolyTriangles: lowPoly,
                              targets: deltas)
        cachedBase = loaded
        return loaded
    }

    /// Convenience: the base body reshaped for a profile.
    static func load(_ profile: BodyProfile = BodyProfile()) -> BodyMeshData? {
        guard let base = loadBase() else { return nil }
        return morph(base, profile: profile)
    }

    private static func buildAdjacency(vertexCount: Int, triangles: [UInt16]) -> (start: [Int32], list: [UInt16]) {
        var sets = [Set<UInt16>](repeating: [], count: vertexCount)
        var i = 0
        while i + 2 < triangles.count {
            let a = triangles[i], b = triangles[i + 1], c = triangles[i + 2]
            sets[Int(a)].formUnion([b, c])
            sets[Int(b)].formUnion([a, c])
            sets[Int(c)].formUnion([a, b])
            i += 3
        }
        var start: [Int32] = [0]
        var list: [UInt16] = []
        for set in sets {
            list.append(contentsOf: set.sorted())
            start.append(Int32(list.count))
        }
        return (start, list)
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

        // The male and female shapes are pushed apart so the difference is easy to see. Neutral
        // stays exactly halfway between them.
        let contrast: Float = 2.0
        let shapeMale = 0.5 + contrast * (male - 0.5)
        let shapeFemale = 1 - shapeMale

        let youngWeight = (1 - age)
        let t = base.targets

        // Coefficients for each target: [target index: weight].
        var coefficients: [(Int, Float)] = [
            (Target.youngMale.rawValue, youngWeight * shapeMale),
            (Target.youngFemale.rawValue, youngWeight * shapeFemale),
            (Target.oldMale.rawValue, age * shapeMale),
            (Target.oldFemale.rawValue, age * shapeFemale),
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
        coefficients = coefficients.filter { $0.1 != 0 }

        var positions = base.positions
        for (index, factor) in coefficients {
            let delta = t[index]
            for v in 0..<positions.count {
                positions[v] += delta[v] * factor
            }
        }

        roundHead(&positions, base: base)
        smooth(&positions, base: base, iterations: 2)

        // Feet on the ground, fixed overall height.
        let minY = positions.map(\.y).min() ?? 0
        let maxY = positions.map(\.y).max() ?? 1
        let scale = figureHeight / max(maxY - minY, 0.001)
        for v in 0..<positions.count {
            positions[v] = Vec(positions[v].x, positions[v].y - minY, positions[v].z) * scale
        }

        // Push each muscle out of the body so it reads as a form, not just a color.
        let flat = smoothNormals(positions: positions, triangles: base.triangles)
        let relief = 0.04 + 0.02 * profile.muscleFactor
        let columns = base.muscleCount
        for v in 0..<positions.count {
            var bump: Float = 0
            for c in 0..<columns {
                bump += smoothstep(Float(base.weights[v * columns + c]) / 255, 0.3, 0.9)
            }
            positions[v] += flat[v] * (relief * min(bump, 1.3))
        }

        // Relief edges and fine bumps make wobbly lines, so iron the surface once more.
        smooth(&positions, base: base, iterations: 3)

        return BodyMeshData(positions: positions,
                            normals: smoothNormals(positions: positions, triangles: base.triangles),
                            triangles: base.triangles,
                            weights: base.weights,
                            muscleCount: base.muscleCount,
                            maxWeight: base.maxWeight)
    }

    /// Light Taubin smoothing: removes small bumps without shrinking the body.
    private static func smooth(_ positions: inout [Vec], base: BodyBase, iterations: Int) {
        let passes: [Float] = [0.5, -0.53]
        for _ in 0..<iterations {
            for factor in passes {
                var next = positions
                for v in 0..<positions.count {
                    let start = Int(base.neighbourStart[v]), end = Int(base.neighbourStart[v + 1])
                    if end <= start { continue }
                    var sum = Vec.zero
                    for k in start..<end { sum += positions[Int(base.neighbours[k])] }
                    let average = sum / Float(end - start)
                    next[v] = positions[v] + (average - positions[v]) * factor
                }
                positions = next
            }
        }
    }

    static func smoothstep(_ x: Float, _ a: Float, _ b: Float) -> Float {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
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

    // MARK: Lines

    private struct Crossing {
        let a: Int
        let b: Int
        let t: Float
    }

    /// Where evenly spaced parallel planes cut through the triangles, as pairs of edge crossings.
    private static func slice(_ mesh: BodyMeshData, normal: Vec, step: Float, offset: Float,
                              triangle keep: (Int, Int, Int) -> Bool) -> [(Crossing, Crossing)] {
        let distances = mesh.positions.map { simd_dot($0, normal) }
        var result: [(Crossing, Crossing)] = []
        var i = 0
        while i + 2 < mesh.triangles.count {
            let ia = Int(mesh.triangles[i]), ib = Int(mesh.triangles[i + 1]), ic = Int(mesh.triangles[i + 2])
            i += 3
            if !keep(ia, ib, ic) { continue }

            let ds = [distances[ia], distances[ib], distances[ic]]
            let ids = [ia, ib, ic]
            guard let lowest = ds.min(), let highest = ds.max() else { continue }
            let k0 = Int(((lowest - offset) / step).rounded(.up))
            let k1 = Int(((highest - offset) / step).rounded(.down))
            if k0 > k1 { continue }

            for k in k0...k1 {
                let value = offset + Float(k) * step
                var found: [Crossing] = []
                for (e0, e1) in [(0, 1), (1, 2), (2, 0)] {
                    if (ds[e0] - value) * (ds[e1] - value) < 0 {
                        found.append(Crossing(a: ids[e0], b: ids[e1], t: (value - ds[e0]) / (ds[e1] - ds[e0])))
                    }
                }
                if found.count == 2 { result.append((found[0], found[1])) }
            }
        }
        return result
    }

    /// Where a scalar field crosses `level` along triangle edges.
    private static func isoLine(_ mesh: BodyMeshData, field: [Float], level: Float) -> [(Crossing, Crossing)] {
        var result: [(Crossing, Crossing)] = []
        var i = 0
        while i + 2 < mesh.triangles.count {
            let ids = [Int(mesh.triangles[i]), Int(mesh.triangles[i + 1]), Int(mesh.triangles[i + 2])]
            i += 3
            let values = ids.map { field[$0] }
            guard let lowest = values.min(), let highest = values.max(), lowest < level, highest >= level else { continue }
            var found: [Crossing] = []
            for (e0, e1) in [(0, 1), (1, 2), (2, 0)] {
                if (values[e0] - level) * (values[e1] - level) < 0 {
                    found.append(Crossing(a: ids[e0], b: ids[e1], t: (level - values[e0]) / (values[e1] - values[e0])))
                }
            }
            if found.count == 2 { result.append((found[0], found[1])) }
        }
        return result
    }

    /// Direction fibres run in, as the normal of the cutting planes (for the right side of the body).
    private static func fibreFamily(_ muscle: MuscleGroup) -> (nx: Float, ny: Float, step: Float, mirrored: Bool) {
        switch muscle {
        case .chest: return (-0.34, 0.94, 0.065, true)       // fans out toward the arm
        case .abs: return (1, 0, 0.07, false)                // vertical
        case .obliques: return (-0.7, 0.7, 0.065, true)      // diagonal
        case .traps: return (0.5, 0.85, 0.06, false)
        case .lats: return (-0.8, 0.6, 0.07, true)
        case .lowerBack: return (1, 0, 0.06, false)
        case .glutes: return (0.5, 0.8, 0.075, true)
        case .shoulders, .biceps, .triceps: return (0.841, 0.542, 0.055, true)   // along the upper arm
        case .forearms: return (0.69, 0.724, 0.05, true)                           // along the forearm
        case .quads: return (1, 0, 0.08, true)
        case .hamstrings: return (1, 0, 0.075, true)
        case .calves: return (1, 0, 0.06, true)
        }
    }

    /// Skin contour lines, plus each muscle's fibres and outline.
    static func lines(for mesh: BodyMeshData, style: HologramStyle = .lines, lift: Float = 0.006) -> BodyLines {
        var out = BodyLines()

        func point(_ c: Crossing) -> Vec {
            let t = c.t
            let position = mesh.positions[c.a] * (1 - t) + mesh.positions[c.b] * t
            let normal = simd_normalize(mesh.normals[c.a] * (1 - t) + mesh.normals[c.b] * t)
            return position + normal * lift
        }
        func add(_ pair: (Crossing, Crossing), muscle: Int, kind: UInt8) {
            out.positions.append(point(pair.0))
            out.positions.append(point(pair.1))
            out.muscle.append(Int8(muscle))
            out.muscle.append(Int8(muscle))
            out.kind.append(kind)
            out.kind.append(kind)
        }
        func value(_ field: [Float], _ c: Crossing) -> Float {
            field[c.a] * (1 - c.t) + field[c.b] * c.t
        }

        // Horizontal scan-lines (plus vertical ones in grid style), only where no muscle is drawn on top.
        // The crystal style draws its own facets, so it keeps only the muscle outlines.
        var skinPlanes: [(normal: Vec, step: Float)] = [(Vec(0, 1, 0), 0.06)]
        if style == .grid { skinPlanes.append((Vec(1, 0, 0), 0.12)) }
        if style == .crystal { skinPlanes = [] }
        for plane in skinPlanes {
            for pair in slice(mesh, normal: plane.normal, step: plane.step, offset: 0.0137, triangle: { _, _, _ in true }) {
                if max(value(mesh.maxWeight, pair.0), value(mesh.maxWeight, pair.1)) < 0.45 {
                    add(pair, muscle: -1, kind: 0)
                }
            }
        }

        for (column, muscle) in muscleOrder.enumerated() {
            let field = (0..<mesh.vertexCount).map { mesh.weight(vertex: $0, column: column) }
            let family = fibreFamily(muscle)

            for side in (style == .crystal ? [] : (family.mirrored ? [Float(1), -1] : [Float(1)])) {
                // Fibres, and in grid style a second set across them.
                var cuts: [(normal: Vec, step: Float)] = [(Vec(family.nx * side, family.ny, 0), family.step)]
                if style == .grid {
                    cuts.append((Vec(-family.ny, family.nx * side, 0), family.step * 1.4))
                }
                for cut in cuts {
                    let pairs = slice(mesh, normal: cut.normal, step: cut.step, offset: 0.0137) { a, b, c in
                        guard max(field[a], field[b], field[c]) > 0.4 else { return false }
                        if !family.mirrored { return true }
                        return (mesh.positions[a].x + mesh.positions[b].x + mesh.positions[c].x) / 3 * side >= -0.02
                    }
                    for pair in pairs where value(field, pair.0) > 0.5 && value(field, pair.1) > 0.5 {
                        add(pair, muscle: column, kind: 1)
                    }
                }
            }

            for pair in isoLine(mesh, field: field, level: 0.5) {
                add(pair, muscle: column, kind: 2)
            }
        }
        return out
    }

    /// One label anchor per muscle (or per side, for paired muscles).
    static func anchors(for mesh: BodyMeshData) -> [BodyAnchor] {
        let central: Set<MuscleGroup> = [.abs, .lowerBack, .traps]
        var result: [BodyAnchor] = []
        for (column, muscle) in muscleOrder.enumerated() {
            for side in (central.contains(muscle) ? [Float(0)] : [Float(1), -1]) {
                var position = Vec.zero
                var normal = Vec.zero
                var total: Float = 0
                for v in 0..<mesh.vertexCount {
                    let w = mesh.weight(vertex: v, column: column)
                    guard w > 0.5, side == 0 || mesh.positions[v].x * side > 0 else { continue }
                    position += mesh.positions[v] * w
                    normal += mesh.normals[v] * w
                    total += w
                }
                guard total > 0 else { continue }
                let n = simd_normalize(normal)
                result.append(BodyAnchor(muscle: muscle, position: position / total + n * 0.05, normal: n))
            }
        }
        return result
    }

    // MARK: Crystal (faceted) body

    /// The faceted body: every triangle gets its own three corners so it shades flat, like cut glass.
    struct CrystalMesh {
        var positions: [Vec] = []       // 3 per triangle
        var normals: [Vec] = []
        var corners: [Int32] = []       // source vertex of each corner
        var edgePositions: [Vec] = []   // 2 per unique edge
        var edgeVertices: [Int32] = []
        var dotPositions: [Vec] = []
        var dotVertices: [Int32] = []

        var triangleCount: Int { positions.count / 3 }
    }

    static func crystal(for mesh: BodyMeshData, triangles: [UInt16]) -> CrystalMesh {
        var result = CrystalMesh()
        var edges = Set<UInt64>()
        var vertices = Set<Int>()

        var i = 0
        while i + 2 < triangles.count {
            let a = Int(triangles[i]), b = Int(triangles[i + 1]), c = Int(triangles[i + 2])
            i += 3

            // Face normal, flipped to point the same way as the smooth body surface.
            var normal = simd_cross(mesh.positions[b] - mesh.positions[a], mesh.positions[c] - mesh.positions[a])
            let length = simd_length(normal)
            if length < 1e-9 { continue }
            normal /= length
            if simd_dot(normal, mesh.normals[a] + mesh.normals[b] + mesh.normals[c]) < 0 { normal = -normal }

            for v in [a, b, c] {
                result.positions.append(mesh.positions[v])
                result.normals.append(normal)
                result.corners.append(Int32(v))
                vertices.insert(v)
            }
            for (p, q) in [(a, b), (b, c), (c, a)] {
                let key = UInt64(min(p, q)) << 32 | UInt64(max(p, q))
                if edges.insert(key).inserted {
                    result.edgePositions.append(mesh.positions[p])
                    result.edgePositions.append(mesh.positions[q])
                    result.edgeVertices.append(Int32(p))
                    result.edgeVertices.append(Int32(q))
                }
            }
        }

        // Glowing nodes at the facet corners, plus a sprinkle of extra points across the surface.
        for v in vertices.sorted() {
            result.dotPositions.append(mesh.positions[v])
            result.dotVertices.append(Int32(v))
        }
        for v in stride(from: 7, to: mesh.vertexCount, by: 17) {
            result.dotPositions.append(mesh.positions[v])
            result.dotVertices.append(Int32(v))
        }
        return result
    }

    // Kept fairly dim so worked muscles stand out against them.
    static let crystalBase = SIMD3<Float>(0.20, 0.40, 0.75)
    static let crystalEdge = SIMD3<Float>(0.42, 0.68, 0.92)
    static let crystalNode = SIMD3<Float>(0.55, 0.80, 1.0)

    /// How strongly each vertex belongs to worked muscles: the tinted color, and 0 when not worked.
    private static func heatTint(for mesh: BodyMeshData, heat: [MuscleGroup: Double]) -> [(color: SIMD3<Float>, amount: Float)] {
        let active = activeMuscles(heat)
        var tints = [(color: SIMD3<Float>, amount: Float)](repeating: (.zero, 0), count: mesh.vertexCount)
        if active.isEmpty { return tints }
        for v in 0..<mesh.vertexCount {
            var color = SIMD3<Float>.zero
            var amount: Float = 0
            for (column, rgb) in active {
                let w = smoothstep(mesh.weight(vertex: v, column: column), 0.15, 0.6)
                if w > amount { amount = w; color = rgb }
            }
            tints[v] = (color, amount)
        }
        return tints
    }

    /// Per-corner colors of the facets: a pale glassy blue that varies from facet to facet, turning
    /// to the heat color on worked muscles.
    static func crystalFillColors(for crystal: CrystalMesh, mesh: BodyMeshData, heat: [MuscleGroup: Double]) -> [SIMD4<Float>] {
        let tints = heatTint(for: mesh, heat: heat)
        let light = simd_normalize(Vec(0.3, 0.5, 0.8))
        var colors = [SIMD4<Float>]()
        colors.reserveCapacity(crystal.positions.count)

        for t in 0..<crystal.triangleCount {
            let base = 3 * t
            let jitter = Float((UInt32(truncatingIfNeeded: t) &* 2654435761) % 1000) / 1000 * 0.36 - 0.18
            let brightness = max(0.55 + 0.45 * abs(simd_dot(crystal.normals[base], light)) + jitter, 0.2)

            // The facet's heat is the average of its corners, in the color of the strongest one.
            var heatColor = SIMD3<Float>.zero
            var strongest: Float = 0
            var total: Float = 0
            for k in 0..<3 {
                let tint = tints[Int(crystal.corners[base + k])]
                total += tint.amount
                if tint.amount > strongest { strongest = tint.amount; heatColor = tint.color }
            }
            // Worked facets switch to a bright, saturated heat color (not dimmed by the facet shading),
            // even at the soft edges of a muscle.
            let share = min(total / 3 * 1.6, 1)
            let heated = heatColor * (0.9 + 0.3 * brightness) * 1.35

            let rgb = crystalBase * brightness * (1 - share) + heated * share
            let color = SIMD4(rgb.x, rgb.y, rgb.z, 1)
            colors.append(color); colors.append(color); colors.append(color)
        }
        return colors
    }

    /// Colors for the facet edges (`edge: true`) or the glowing nodes, tinted by heat.
    static func crystalLineColors(vertices: [Int32], mesh: BodyMeshData, heat: [MuscleGroup: Double], edge: Bool) -> [SIMD4<Float>] {
        let tints = heatTint(for: mesh, heat: heat)
        let base = edge ? crystalEdge : crystalNode
        return vertices.map { v -> SIMD4<Float> in
            let tint = tints[Int(v)]
            let rgb = base * (1 - tint.amount) + tint.color * tint.amount
            return SIMD4(rgb.x, rgb.y, rgb.z, 1)
        }
    }

    // MARK: Heat colors

    private static func activeMuscles(_ heat: [MuscleGroup: Double]) -> [Int: SIMD3<Float>] {
        var active: [Int: SIMD3<Float>] = [:]
        for (column, muscle) in muscleOrder.enumerated() {
            if let intensity = heat[muscle], intensity > 0 {
                active[column] = HeatScale.rgb(intensity)
            }
        }
        return active
    }

    /// Per-vertex color of the solid body: dark skin, lighter muscle, glowing where worked.
    static func fillColors(for mesh: BodyMeshData, heat: [MuscleGroup: Double]) -> [SIMD4<Float>] {
        let active = activeMuscles(heat)
        var colors = [SIMD4<Float>]()
        colors.reserveCapacity(mesh.vertexCount)
        for v in 0..<mesh.vertexCount {
            let muscleShare = smoothstep(mesh.maxWeight[v], 0.3, 0.8)
            var f = skinFill * (1 - muscleShare) + muscleFill * muscleShare
            for (column, color) in active {
                let w = smoothstep(mesh.weight(vertex: v, column: column), 0.15, 0.6)
                if w > 0 { f = f * (1 - w) + color * 0.5 * w }
            }
            colors.append(SIMD4(f.x, f.y, f.z, 1))
        }
        return colors
    }

    /// Per-vertex colors for the lines. A muscle's fibres and outline take its heat color.
    static func lineColors(for lines: BodyLines, heat: [MuscleGroup: Double]) -> [SIMD4<Float>] {
        let active = activeMuscles(heat)
        var colors = [SIMD4<Float>]()
        colors.reserveCapacity(lines.positions.count)
        for i in 0..<lines.positions.count {
            let column = Int(lines.muscle[i])
            let rgb: SIMD3<Float>
            if column < 0 {
                rgb = skinLine
            } else {
                let base = active[column] ?? muscleLine
                switch lines.kind[i] {
                case 2: rgb = simd_min(base * 1.1 + SIMD3<Float>(repeating: 0.1), SIMD3<Float>(repeating: 1))
                default: rgb = base * 0.75
                }
            }
            colors.append(SIMD4(rgb.x, rgb.y, rgb.z, 1))
        }
        return colors
    }
}
