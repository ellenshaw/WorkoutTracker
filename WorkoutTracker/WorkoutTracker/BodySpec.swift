//
//  BodySpec.swift
//  WorkoutTracker
//
//  Shape data for the 3D body. Generated from a prototype that was rendered and checked offline.
//  A "tube" is a smooth body part defined by elliptical cross-sections along the Y axis.
//  A "patch" is a muscle: a bulging region on the surface of a tube (angle 0° = front, 180° = back).
//

import Foundation

struct BodyKey {
    let y: Float, cx: Float, cz: Float, rx: Float, rz: Float
}

struct BodyTube {
    let name: String
    let mirrored: Bool
    let keys: [BodyKey]
}

struct BodyPatch {
    let host: String
    let muscle: MuscleGroup
    let y0: Float, y1: Float
    let t0: Float, t1: Float   // degrees
    let amp: Float, peak: Float
    let mirrored: Bool
}

enum BodySpec {
    static let tubes: [BodyTube] = [
        BodyTube(name: "torso", mirrored: false, keys: [
            BodyKey(y: 2.55, cx: 0, cz: 0, rx: 0.5, rz: 0.34),
            BodyKey(y: 2.75, cx: 0, cz: 0, rx: 0.66, rz: 0.4),
            BodyKey(y: 3.1, cx: 0, cz: -0.01, rx: 0.76, rz: 0.45),
            BodyKey(y: 3.5, cx: 0, cz: 0, rx: 0.68, rz: 0.42),
            BodyKey(y: 3.9, cx: 0, cz: 0, rx: 0.62, rz: 0.37),
            BodyKey(y: 4.3, cx: 0, cz: 0, rx: 0.68, rz: 0.39),
            BodyKey(y: 4.75, cx: 0, cz: 0, rx: 0.8, rz: 0.43),
            BodyKey(y: 5.2, cx: 0, cz: 0, rx: 0.86, rz: 0.46),
            BodyKey(y: 5.55, cx: 0, cz: 0, rx: 0.84, rz: 0.4),
            BodyKey(y: 5.8, cx: 0, cz: 0, rx: 0.62, rz: 0.32),
            BodyKey(y: 6, cx: 0, cz: 0, rx: 0.3, rz: 0.24),
            BodyKey(y: 6.1, cx: 0, cz: 0, rx: 0.18, rz: 0.18),
        ]),
        BodyTube(name: "neck", mirrored: false, keys: [
            BodyKey(y: 5.85, cx: 0, cz: 0.02, rx: 0.22, rz: 0.22),
            BodyKey(y: 6.15, cx: 0, cz: 0.03, rx: 0.19, rz: 0.2),
            BodyKey(y: 6.3, cx: 0, cz: 0.03, rx: 0.18, rz: 0.19),
        ]),
        BodyTube(name: "head", mirrored: false, keys: [
            BodyKey(y: 6.2, cx: 0, cz: 0.03, rx: 0.05, rz: 0.06),
            BodyKey(y: 6.3, cx: 0, cz: 0.04, rx: 0.2, rz: 0.24),
            BodyKey(y: 6.55, cx: 0, cz: 0.05, rx: 0.31, rz: 0.37),
            BodyKey(y: 6.8, cx: 0, cz: 0.04, rx: 0.3, rz: 0.35),
            BodyKey(y: 6.95, cx: 0, cz: 0.03, rx: 0.2, rz: 0.23),
            BodyKey(y: 7.02, cx: 0, cz: 0.03, rx: 0.05, rz: 0.06),
        ]),
        BodyTube(name: "upperArm", mirrored: true, keys: [
            BodyKey(y: 3.9, cx: 1.31, cz: 0, rx: 0.18, rz: 0.18),
            BodyKey(y: 4, cx: 1.3, cz: 0, rx: 0.2, rz: 0.2),
            BodyKey(y: 4.5, cx: 1.24, cz: 0, rx: 0.235, rz: 0.235),
            BodyKey(y: 5, cx: 1.18, cz: 0, rx: 0.27, rz: 0.27),
            BodyKey(y: 5.4, cx: 1.13, cz: 0, rx: 0.31, rz: 0.31),
            BodyKey(y: 5.64, cx: 1.07, cz: 0, rx: 0.27, rz: 0.27),
            BodyKey(y: 5.78, cx: 1.03, cz: 0, rx: 0.17, rz: 0.17),
            BodyKey(y: 5.86, cx: 1, cz: 0, rx: 0.06, rz: 0.06),
        ]),
        BodyTube(name: "forearm", mirrored: true, keys: [
            BodyKey(y: 2.6, cx: 1.45, cz: 0, rx: 0.1, rz: 0.09),
            BodyKey(y: 2.75, cx: 1.44, cz: 0, rx: 0.12, rz: 0.11),
            BodyKey(y: 3.2, cx: 1.4, cz: 0, rx: 0.18, rz: 0.17),
            BodyKey(y: 3.7, cx: 1.34, cz: 0, rx: 0.225, rz: 0.22),
            BodyKey(y: 4.05, cx: 1.3, cz: 0, rx: 0.2, rz: 0.2),
        ]),
        BodyTube(name: "hand", mirrored: true, keys: [
            BodyKey(y: 2, cx: 1.47, cz: 0, rx: 0.04, rz: 0.03),
            BodyKey(y: 2.2, cx: 1.47, cz: 0, rx: 0.12, rz: 0.06),
            BodyKey(y: 2.45, cx: 1.46, cz: 0, rx: 0.14, rz: 0.07),
            BodyKey(y: 2.65, cx: 1.45, cz: 0, rx: 0.1, rz: 0.08),
        ]),
        BodyTube(name: "leg", mirrored: true, keys: [
            BodyKey(y: 0.12, cx: 0.38, cz: 0, rx: 0.1, rz: 0.1),
            BodyKey(y: 0.2, cx: 0.38, cz: 0, rx: 0.11, rz: 0.11),
            BodyKey(y: 0.4, cx: 0.38, cz: -0.01, rx: 0.15, rz: 0.15),
            BodyKey(y: 0.7, cx: 0.38, cz: -0.04, rx: 0.22, rz: 0.23),
            BodyKey(y: 1, cx: 0.38, cz: 0, rx: 0.2, rz: 0.22),
            BodyKey(y: 1.2, cx: 0.38, cz: 0.03, rx: 0.2, rz: 0.22),
            BodyKey(y: 1.45, cx: 0.38, cz: 0.03, rx: 0.22, rz: 0.24),
            BodyKey(y: 1.9, cx: 0.39, cz: 0.03, rx: 0.3, rz: 0.31),
            BodyKey(y: 2.4, cx: 0.4, cz: 0.02, rx: 0.34, rz: 0.36),
            BodyKey(y: 2.9, cx: 0.4, cz: 0, rx: 0.37, rz: 0.38),
            BodyKey(y: 3.2, cx: 0.38, cz: 0, rx: 0.33, rz: 0.34),
        ]),
        BodyTube(name: "foot", mirrored: true, keys: [
            BodyKey(y: 0.003, cx: 0.38, cz: 0.2, rx: 0.034, rz: 0.0875),
            BodyKey(y: 0.0333, cx: 0.38, cz: 0.2, rx: 0.1043, rz: 0.2683),
            BodyKey(y: 0.0667, cx: 0.38, cz: 0.2, rx: 0.132, rz: 0.3394),
            BodyKey(y: 0.1, cx: 0.38, cz: 0.2, rx: 0.14, rz: 0.36),
            BodyKey(y: 0.1333, cx: 0.38, cz: 0.2, rx: 0.132, rz: 0.3394),
            BodyKey(y: 0.1667, cx: 0.38, cz: 0.2, rx: 0.1043, rz: 0.2683),
            BodyKey(y: 0.197, cx: 0.38, cz: 0.2, rx: 0.034, rz: 0.0875),
        ]),
    ]

    static let patches: [BodyPatch] = [
        BodyPatch(host: "torso", muscle: .chest, y0: 4.75, y1: 5.55, t0: 6, t1: 82, amp: 0.1, peak: 0.5, mirrored: true),
        BodyPatch(host: "torso", muscle: .abs, y0: 4.33, y1: 4.75, t0: 3, t1: 22, amp: 0.055, peak: 0.5, mirrored: true),
        BodyPatch(host: "torso", muscle: .abs, y0: 3.93, y1: 4.31, t0: 3, t1: 22, amp: 0.055, peak: 0.5, mirrored: true),
        BodyPatch(host: "torso", muscle: .abs, y0: 3.53, y1: 3.91, t0: 3, t1: 22, amp: 0.05, peak: 0.5, mirrored: true),
        BodyPatch(host: "torso", muscle: .obliques, y0: 3.4, y1: 4.5, t0: 28, t1: 88, amp: 0.05, peak: 0.5, mirrored: true),
        BodyPatch(host: "torso", muscle: .traps, y0: 5.1, y1: 6.02, t0: 142, t1: 218, amp: 0.11, peak: 0.45, mirrored: false),
        BodyPatch(host: "torso", muscle: .lats, y0: 3.95, y1: 5.4, t0: 105, t1: 168, amp: 0.09, peak: 0.55, mirrored: true),
        BodyPatch(host: "torso", muscle: .lowerBack, y0: 3.3, y1: 4.1, t0: 160, t1: 178, amp: 0.06, peak: 0.5, mirrored: true),
        BodyPatch(host: "torso", muscle: .glutes, y0: 2.7, y1: 3.5, t0: 120, t1: 176, amp: 0.14, peak: 0.4, mirrored: true),
        BodyPatch(host: "upperArm", muscle: .shoulders, y0: 4.7, y1: 5.8, t0: -95, t1: 115, amp: 0.11, peak: 0.6, mirrored: true),
        BodyPatch(host: "upperArm", muscle: .biceps, y0: 4.15, y1: 5, t0: -52, t1: 52, amp: 0.075, peak: 0.5, mirrored: true),
        BodyPatch(host: "upperArm", muscle: .triceps, y0: 4.15, y1: 5.05, t0: 128, t1: 232, amp: 0.075, peak: 0.5, mirrored: true),
        BodyPatch(host: "forearm", muscle: .forearms, y0: 2.8, y1: 4.05, t0: -170, t1: 170, amp: 0.055, peak: 0.55, mirrored: true),
        BodyPatch(host: "leg", muscle: .quads, y0: 1.5, y1: 3, t0: 6, t1: 82, amp: 0.1, peak: 0.45, mirrored: true),
        BodyPatch(host: "leg", muscle: .quads, y0: 1.5, y1: 3, t0: -82, t1: -6, amp: 0.09, peak: 0.45, mirrored: true),
        BodyPatch(host: "leg", muscle: .hamstrings, y0: 1.55, y1: 2.9, t0: 105, t1: 255, amp: 0.075, peak: 0.5, mirrored: true),
        BodyPatch(host: "leg", muscle: .calves, y0: 0.5, y1: 1.2, t0: 112, t1: 178, amp: 0.09, peak: 0.62, mirrored: true),
        BodyPatch(host: "leg", muscle: .calves, y0: 0.5, y1: 1.2, t0: 182, t1: 248, amp: 0.09, peak: 0.62, mirrored: true),
    ]
}

// MARK: - Male / female

enum BodyType: String, CaseIterable, Identifiable {
    case male, female

    var id: String { rawValue }
    var title: String { self == .male ? "Male" : "Female" }
}

extension BodySpec {
    static func tubes(for type: BodyType) -> [BodyTube] {
        guard type == .female else { return tubes }
        return tubes.map { tube in
            BodyTube(name: tube.name, mirrored: tube.mirrored, keys: tube.keys.map { adaptForFemale($0, tube: tube.name) })
        }
    }

    static func patches(for type: BodyType) -> [BodyPatch] {
        guard type == .female else { return patches }
        return patches.map { patch in
            let factor: Float
            switch patch.muscle {
            case .chest: factor = 1.15
            case .glutes: factor = 1.1
            default: factor = 0.78
            }
            return BodyPatch(host: patch.host, muscle: patch.muscle, y0: patch.y0, y1: patch.y1,
                             t0: patch.t0, t1: patch.t1, amp: patch.amp * factor, peak: patch.peak,
                             mirrored: patch.mirrored)
        }
    }

    // Female proportions: narrower shoulders and waist, wider hips, slimmer limbs.
    private static let torsoWidth: [(Float, Float)] = [(2.5, 1.08), (3.1, 1.13), (3.9, 0.84), (4.7, 0.88), (5.5, 0.86), (6.1, 0.9)]
    private static let torsoDepth: [(Float, Float)] = [(2.5, 0.95), (3.1, 1.0), (3.9, 0.88), (4.6, 0.98), (5.1, 1.06), (5.6, 0.9), (6.1, 0.9)]

    private static func interpolate(_ points: [(Float, Float)], at y: Float) -> Float {
        guard let first = points.first, let last = points.last else { return 1 }
        if y <= first.0 { return first.1 }
        for i in 0..<(points.count - 1) {
            let (y0, v0) = points[i]
            let (y1, v1) = points[i + 1]
            if y <= y1 { return v0 + (v1 - v0) * (y - y0) / (y1 - y0) }
        }
        return last.1
    }

    private static func adaptForFemale(_ key: BodyKey, tube: String) -> BodyKey {
        var cx = key.cx, rx = key.rx, rz = key.rz
        switch tube {
        case "torso":
            rx *= interpolate(torsoWidth, at: key.y)
            rz *= interpolate(torsoDepth, at: key.y)
        case "upperArm", "forearm", "hand":
            cx *= 0.9; rx *= 0.82; rz *= 0.82
        case "leg":
            rx *= 0.95; rz *= 0.95
        case "head", "neck":
            rx *= 0.93; rz *= 0.93
        case "foot":
            rx *= 0.9; rz *= 0.9
        default:
            break
        }
        return BodyKey(y: key.y, cx: cx, cz: key.cz, rx: rx, rz: rz)
    }
}
