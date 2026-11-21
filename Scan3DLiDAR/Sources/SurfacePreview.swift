import ARKit
import SwiftUI
import UIKit
import simd

/// Camera-first display modes. The diagnostic wireframe is not the natural-surface renderer.
enum SurfaceVisualizationMode: String, CaseIterable, Identifiable {
    case natural
    case surfaces
    case wireframe

    var id: Self { self }

    var label: String {
        switch self {
        case .natural: return "Naturlig"
        case .surfaces: return "Flader"
        case .wireframe: return "Trådnet"
        }
    }
}

struct SurfacePreviewFace {
    let a: CGPoint
    let b: CGPoint
    let c: CGPoint
    let alpha: Double
}

struct SurfacePreviewEdge {
    let a: CGPoint
    let b: CGPoint
}

/// Ephemeral, on-screen AR mesh projections. Never exported or stored in a scan project.
struct SurfacePreviewFrame {
    var faces: [SurfacePreviewFace]
    var edges: [SurfacePreviewEdge]

    static let empty = SurfacePreviewFrame(faces: [], edges: [])
    var isEmpty: Bool { faces.isEmpty && edges.isEmpty }
}

struct SurfacePreviewOverlay: View {
    let preview: SurfacePreviewFrame

    var body: some View {
        Canvas { context, _ in
            for face in preview.faces {
                var path = Path()
                path.move(to: face.a)
                path.addLine(to: face.b)
                path.addLine(to: face.c)
                path.closeSubpath()
                context.fill(path, with: .color(Color(red: 0.55, green: 0.96, blue: 0.83)
                    .opacity(face.alpha)))
            }
            for edge in preview.edges {
                var path = Path()
                path.move(to: edge.a)
                path.addLine(to: edge.b)
                context.stroke(path, with: .color(Color(red: 0.67, green: 1.0, blue: 0.91)
                    .opacity(0.72)), lineWidth: 1.35)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Project actual ARKit scene triangles into the existing ARView's viewport.
/// The overlay illustrates observed face orientation, not an isolated, watertight model
/// or a calibrated measurement. Work and output are deliberately bounded for iPhone use.
enum SurfacePreviewProjector {
    private struct EdgeKey: Hashable {
        let low: Int
        let high: Int

        init(_ a: Int, _ b: Int) {
            low = min(a, b)
            high = max(a, b)
        }
    }

    private struct EdgeObservation {
        let normal: SIMD3<Float>
        let a: CGPoint
        let b: CGPoint
    }

    static func hasAngleBreak(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
        // Ignore opposite winding. About 35 degrees distinguishes visible corners
        // from small ARKit mesh facets without drawing the whole triangle grid.
        abs(simd_dot(a, b)) < 0.82
    }

    static func project(frame: ARFrame,
                        viewport: CGSize,
                        orientation: UIInterfaceOrientation,
                        target: SIMD3<Float>) -> SurfacePreviewFrame {
        guard viewport.width > 0, viewport.height > 0 else { return .empty }
        guard case .normal = frame.camera.trackingState else { return .empty }
        let cameraTransform = frame.camera.transform
        let cameraColumn = cameraTransform.columns.3
        let camera = SIMD3<Float>(cameraColumn.x, cameraColumn.y, cameraColumn.z)
        let forwardColumn = cameraTransform.columns.2
        let forward = -simd_normalize(SIMD3<Float>(forwardColumn.x, forwardColumn.y, forwardColumn.z))
        let radius2: Float = 0.70 * 0.70

        let anchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
            .sorted { lhs, rhs in
                let l = lhs.transform.columns.3
                let r = rhs.transform.columns.3
                return simd_length_squared(SIMD3<Float>(l.x, l.y, l.z) - target)
                     < simd_length_squared(SIMD3<Float>(r.x, r.y, r.z) - target)
            }
            .prefix(6)

        var candidateFaces: [SurfacePreviewFace] = []
        var sharpEdges: [SurfacePreviewEdge] = []
        var processed = 0
        let maxProcessed = 2600

        for anchor in anchors {
            guard processed < maxProcessed else { break }
            let geometry = anchor.geometry
            let source = geometry.vertices
            let faces = geometry.faces
            guard source.format == .float3, source.componentsPerVector == 3,
                  faces.indexCountPerPrimitive == 3,
                  faces.bytesPerIndex == 2 || faces.bytesPerIndex == 4 else { continue }

            let vertexBytes = source.buffer.contents()
            let indexBytes = faces.buffer.contents()

            func worldVertex(_ index: Int) -> SIMD3<Float>? {
                guard index >= 0, index < source.count else { return nil }
                let address = vertexBytes.advanced(by: source.offset + index * source.stride)
                let xyz = address.assumingMemoryBound(to: Float.self)
                let world = simd_mul(anchor.transform, SIMD4<Float>(xyz[0], xyz[1], xyz[2], 1))
                let p = SIMD3<Float>(world.x, world.y, world.z)
                return p.x.isFinite && p.y.isFinite && p.z.isFinite ? p : nil
            }

            func vertexIndex(_ number: Int) -> Int {
                let address = indexBytes.advanced(by: number * faces.bytesPerIndex)
                return faces.bytesPerIndex == 4
                    ? Int(address.assumingMemoryBound(to: UInt32.self).pointee)
                    : Int(address.assumingMemoryBound(to: UInt16.self).pointee)
            }

            var previous: [EdgeKey: EdgeObservation] = [:]
            for faceIndex in 0..<min(faces.count, maxProcessed - processed) {
                processed += 1
                let ids = (0..<3).map { vertexIndex(faceIndex * 3 + $0) }
                guard let p0 = worldVertex(ids[0]),
                      let p1 = worldVertex(ids[1]),
                      let p2 = worldVertex(ids[2]) else { continue }
                let center = (p0 + p1 + p2) / 3
                guard simd_length_squared(center - target) < radius2,
                      simd_dot(p0 - camera, forward) > 0.18,
                      simd_dot(p1 - camera, forward) > 0.18,
                      simd_dot(p2 - camera, forward) > 0.18 else { continue }

                let cross = simd_cross(p1 - p0, p2 - p0)
                guard simd_length_squared(cross) > 0.00000001 else { continue }
                let normal = simd_normalize(cross)
                let projected = [p0, p1, p2].map {
                    frame.camera.projectPoint($0, orientation: orientation, viewportSize: viewport)
                }
                guard projected.allSatisfy({ $0.x.isFinite && $0.y.isFinite
                    && $0.x >= 0 && $0.x <= viewport.width
                    && $0.y >= 0 && $0.y <= viewport.height }) else { continue }

                let area = abs((projected[1].x - projected[0].x) * (projected[2].y - projected[0].y)
                    - (projected[2].x - projected[0].x) * (projected[1].y - projected[0].y))
                guard area >= 0.4 && area < viewport.width * viewport.height * 0.20 else { continue }

                let facing = abs(simd_dot(normal, forward))
                candidateFaces.append(SurfacePreviewFace(
                    a: projected[0], b: projected[1], c: projected[2],
                    alpha: 0.055 + Double(facing) * 0.08))

                for edge in 0..<3 {
                    let next = (edge + 1) % 3
                    let key = EdgeKey(ids[edge], ids[next])
                    if let old = previous[key] {
                        if hasAngleBreak(old.normal, normal) && sharpEdges.count < 240 {
                            sharpEdges.append(SurfacePreviewEdge(a: old.a, b: old.b))
                        }
                    } else {
                        previous[key] = EdgeObservation(normal: normal,
                            a: projected[edge], b: projected[next])
                    }
                }
            }
        }

        // Show representative real faces, not a dense polygon grid.
        let step = max(1, (candidateFaces.count + 479) / 480)
        let selected = stride(from: 0, to: candidateFaces.count, by: step).map { candidateFaces[$0] }
        return SurfacePreviewFrame(faces: selected, edges: sharpEdges)
    }
}
