//
//  BodyMesher.swift
//  WorkoutTracker
//
//  Turns the shape data in BodySpec into SceneKit meshes: solid surfaces, plus the
//  horizontal contour lines that give the hologram its scan-line look.
//

import SceneKit
import simd

enum BodyMesher {
    typealias Vec = SIMD3<Float>

    /// A grid of surface points (rows go up the body, columns go around or across it).
    struct Grid {
        var positions: [Vec]
        var hints: [Vec]
        let rows: Int
        let cols: Int
    }

    // MARK: Profile

    /// Smoothly interpolates the cross-section at height `y` (Catmull-Rom between keys sorted by y).
    static func profile(_ keys: [BodyKey], y: Float) -> (cx: Float, cz: Float, rx: Float, rz: Float) {
        let y = min(max(y, keys[0].y), keys[keys.count - 1].y)
        var i = 0
        while i < keys.count - 2 && y > keys[i + 1].y { i += 1 }

        let k0 = keys[max(i - 1, 0)]
        let k1 = keys[i]
        let k2 = keys[i + 1]
        let k3 = keys[min(i + 2, keys.count - 1)]
        let span = k2.y - k1.y
        let t: Float = span > 0 ? (y - k1.y) / span : 0

        func cr(_ a: Float, _ b: Float, _ c: Float, _ d: Float) -> Float {
            0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t * t * t)
        }

        return (
            cr(k0.cx, k1.cx, k2.cx, k3.cx),
            cr(k0.cz, k1.cz, k2.cz, k3.cz),
            max(cr(k0.rx, k1.rx, k2.rx, k3.rx), 0.005),
            max(cr(k0.rz, k1.rz, k2.rz, k3.rz), 0.005)
        )
    }

    /// A point on the surface (optionally pushed outward by `bulge`) and its outward direction.
    static func surface(_ keys: [BodyKey], side: Float, y: Float, theta: Float, bulge: Float = 0) -> (point: Vec, outward: Vec) {
        let p = profile(keys, y: y)
        var nx = side * sin(theta) / p.rx
        var nz = cos(theta) / p.rz
        let length = max((nx * nx + nz * nz).squareRoot(), 1e-6)
        nx /= length
        nz /= length
        let point = Vec(
            side * (p.cx + p.rx * sin(theta)) + nx * bulge,
            y,
            p.cz + p.rz * cos(theta) + nz * bulge
        )
        return (point, Vec(nx, 0, nz))
    }

    // MARK: Grids

    /// Rings around a body part, bottom to top.
    static func tubeGrid(_ keys: [BodyKey], side: Float, cols: Int = 32) -> Grid {
        let y0 = keys[0].y
        let y1 = keys[keys.count - 1].y
        let rows = max(14, Int((y1 - y0) * 16))

        var positions: [Vec] = []
        var hints: [Vec] = []
        for r in 0..<rows {
            let y = y0 + (y1 - y0) * Float(r) / Float(rows - 1)
            for c in 0..<cols {
                let theta = 2 * Float.pi * Float(c) / Float(cols)
                let s = surface(keys, side: side, y: y, theta: theta)
                positions.append(s.point)
                hints.append(s.outward)
            }
        }
        return Grid(positions: positions, hints: hints, rows: rows, cols: cols)
    }

    /// A muscle: a smooth bulge lying on a tube's surface that fades to zero at its edges.
    static func patchGrid(_ keys: [BodyKey], side: Float, spec: BodyPatch, rows: Int = 16, cols: Int = 16) -> Grid {
        let k = log(0.5) / log(spec.peak)
        var positions: [Vec] = []
        var hints: [Vec] = []
        for r in 0..<rows {
            let v = Float(r) / Float(rows - 1)
            let y = spec.y0 + (spec.y1 - spec.y0) * v
            for c in 0..<cols {
                let u = Float(c) / Float(cols - 1)
                let theta = (spec.t0 + (spec.t1 - spec.t0) * u) * Float.pi / 180
                let shape = max(sin(Float.pi * u) * sin(Float.pi * pow(v, k)), 0)
                let bulge = spec.amp * pow(shape, 0.7) + 0.004
                let s = surface(keys, side: side, y: y, theta: theta, bulge: bulge)
                positions.append(s.point)
                hints.append(s.outward)
            }
        }
        return Grid(positions: positions, hints: hints, rows: rows, cols: cols)
    }

    // MARK: Solid meshes

    /// Closed surface for a tube. `inflate` pushes it outward, used for the soft glow shell.
    static func tubeMesh(_ grid: Grid, inflate: Float = 0) -> SCNGeometry {
        var positions = grid.positions.enumerated().map { $0.element + grid.hints[$0.offset] * inflate }
        var hints = grid.hints
        let rows = grid.rows
        let cols = grid.cols

        var triangles: [(Int, Int, Int)] = []
        for r in 0..<(rows - 1) {
            for c in 0..<cols {
                let c2 = (c + 1) % cols
                let a = r * cols + c
                let b = r * cols + c2
                let cc = (r + 1) * cols + c2
                let d = (r + 1) * cols + c
                triangles.append((a, b, cc))
                triangles.append((a, cc, d))
            }
        }

        // Close both ends with a fan around the ring's center.
        for (row, sign) in [(0, Float(-1)), (rows - 1, Float(1))] {
            let ring = (0..<cols).map { row * cols + $0 }
            var center = Vec.zero
            for i in ring { center += positions[i] }
            center /= Float(cols)
            positions.append(center)
            hints.append(Vec(0, sign, 0))
            let ci = positions.count - 1
            for c in 0..<cols {
                triangles.append((ci, ring[c], ring[(c + 1) % cols]))
            }
        }

        return geometry(positions: positions, hints: hints, triangles: triangles)
    }

    static func patchMesh(_ grid: Grid) -> SCNGeometry {
        let rows = grid.rows
        let cols = grid.cols
        var triangles: [(Int, Int, Int)] = []
        for r in 0..<(rows - 1) {
            for c in 0..<(cols - 1) {
                let a = r * cols + c
                let b = a + 1
                let cc = (r + 1) * cols + c + 1
                let d = (r + 1) * cols + c
                triangles.append((a, b, cc))
                triangles.append((a, cc, d))
            }
        }
        return geometry(positions: grid.positions, hints: grid.hints, triangles: triangles)
    }

    // MARK: Contour lines

    /// One line per row, hovering just above the surface so it never sinks into the fill.
    static func contours(_ grid: Grid, wrap: Bool, lift: Float = 0.006) -> SCNGeometry {
        let points = grid.positions.enumerated().map { $0.element + grid.hints[$0.offset] * lift }
        var indices: [Int32] = []
        let segments = wrap ? grid.cols : grid.cols - 1
        for r in 0..<grid.rows {
            for c in 0..<segments {
                let a = r * grid.cols + c
                let b = r * grid.cols + (c + 1) % grid.cols
                indices.append(Int32(a))
                indices.append(Int32(b))
            }
        }
        let vertexSource = SCNGeometrySource(vertices: points.map { SCNVector3($0.x, $0.y, $0.z) })
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        return SCNGeometry(sources: [vertexSource], elements: [element])
    }

    // MARK: Geometry assembly

    /// Builds smooth vertex normals and makes every triangle wind so it faces outward.
    private static func geometry(positions: [Vec], hints: [Vec], triangles: [(Int, Int, Int)]) -> SCNGeometry {
        var normals = [Vec](repeating: .zero, count: positions.count)
        var indices: [Int32] = []
        indices.reserveCapacity(triangles.count * 3)

        for (a, b, c) in triangles {
            var faceNormal = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            var second = b
            var third = c
            if simd_dot(faceNormal, hints[a] + hints[b] + hints[c]) < 0 {
                faceNormal = -faceNormal
                second = c
                third = b
            }
            normals[a] += faceNormal
            normals[b] += faceNormal
            normals[c] += faceNormal
            indices.append(Int32(a))
            indices.append(Int32(second))
            indices.append(Int32(third))
        }

        for i in 0..<normals.count {
            let length = simd_length(normals[i])
            normals[i] = length > 1e-9 ? normals[i] / length : hints[i]
        }

        let vertexSource = SCNGeometrySource(vertices: positions.map { SCNVector3($0.x, $0.y, $0.z) })
        let normalSource = SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) })
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
    }
}
