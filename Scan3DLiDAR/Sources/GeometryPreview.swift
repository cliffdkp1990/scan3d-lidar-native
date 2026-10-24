import Foundation

enum GeometryPreviewError: LocalizedError {
    case unsupported, malformed, empty, tooLarge
    var errorDescription: String? {
        switch self {
        case .unsupported: return "Visningen understøtter appens egne ASCII-PLY-punktskyer og trekantede OBJ-mesh uden tekstur."
        case .malformed: return "3D-filen indeholder ugyldige koordinater, antal eller flader. Originalen er bevaret."
        case .empty: return "Filen indeholder ingen synlig 3D-geometri. Prøv at optage mere af genstanden."
        case .tooLarge: return "3D-filen overstiger denne visnings lokale ressourcegrænse. Originalen kan stadig deles."
        }
    }
}

/// A bounded reader for Scan3D's own exports, not a general-purpose model importer.
/// Source coordinates and files stay unchanged; normalization affects display only.
struct GeometryPreview {
    static let maxBytes = 32 * 1024 * 1024
    static let maxVertices = 480_000
    static let maxTriangles = 160_000
    static let maxDisplayPoints = 20_000
    let vertices: [SIMD3<Float>]
    let triangles: [UInt32]
    let sizeMeters: SIMD3<Float>
    var isPointCloud: Bool { triangles.isEmpty }

    static func read(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(1024 * 1024, maxBytes + 1 - data.count)), !chunk.isEmpty {
            try Task.checkCancellation()
            data.append(chunk)
            if data.count > maxBytes { throw GeometryPreviewError.tooLarge }
        }
        return data
    }

    static func parse(_ data: Data, extension ext: String) throws -> GeometryPreview {
        guard data.count <= maxBytes else { throw GeometryPreviewError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw GeometryPreviewError.malformed }
        guard ["ply", "obj"].contains(ext.lowercased()) else { throw GeometryPreviewError.unsupported }
        var lines = text.split(whereSeparator: \.isNewline).makeIterator()
        var vertices: [SIMD3<Float>] = []
        var triangles: [UInt32] = []
        func point(_ values: ArraySlice<Substring>) throws -> SIMD3<Float> {
            guard values.count == 3 else { throw GeometryPreviewError.malformed }
            let numbers = values.compactMap { Float($0) }
            guard numbers.count == 3, numbers.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else {
                throw GeometryPreviewError.malformed
            }
            return SIMD3(numbers[0], numbers[1], numbers[2])
        }
        if ext.lowercased() == "ply" {
            guard lines.next() == "ply", lines.next() == "format ascii 1.0" else { throw GeometryPreviewError.unsupported }
            var count: Int?
            var properties: [String] = []
            var ended = false
            var headerLines = 0
            while let line = lines.next() {
                headerLines += 1
                guard headerLines <= 32 else { throw GeometryPreviewError.malformed }
                if line == "end_header" { ended = true; break }
                if line.hasPrefix("comment ") { continue }
                let tokens = line.split(whereSeparator: \.isWhitespace)
                if tokens.count == 3, tokens[0] == "element", tokens[1] == "vertex", count == nil {
                    guard let n = Int(tokens[2]), n >= 0 else { throw GeometryPreviewError.malformed }
                    guard n <= maxVertices else { throw GeometryPreviewError.tooLarge }
                    count = n
                } else if tokens.count == 3, tokens[0] == "property", tokens[1] == "float", count != nil {
                    properties.append(String(tokens[2]))
                } else { throw GeometryPreviewError.unsupported }
            }
            guard ended, let count, properties == ["x", "y", "z"] else { throw GeometryPreviewError.malformed }
            vertices.reserveCapacity(count)
            for index in 0..<count {
                if index % 1024 == 0 { try Task.checkCancellation() }
                guard let line = lines.next() else { throw GeometryPreviewError.malformed }
                vertices.append(try point(line.split(whereSeparator: \.isWhitespace)[...]))
            }
            guard lines.next() == nil else { throw GeometryPreviewError.malformed }
        } else {
            var lineIndex = 0
            while let line = lines.next() {
                lineIndex += 1
                if lineIndex % 1024 == 0 { try Task.checkCancellation() }
                let tokens = line.split(whereSeparator: \.isWhitespace)
                guard let first = tokens.first else { continue }
                if first.hasPrefix("#") || first == "o" { continue }
                if first == "v" {
                    guard vertices.count < maxVertices else { throw GeometryPreviewError.tooLarge }
                    vertices.append(try point(tokens.dropFirst()))
                } else if first == "f" {
                    guard tokens.count == 4 else { throw GeometryPreviewError.unsupported }
                    guard triangles.count / 3 < maxTriangles else { throw GeometryPreviewError.tooLarge }
                    let indices = tokens.dropFirst().compactMap { UInt32($0) }
                    guard indices.count == 3, indices.allSatisfy({ $0 > 0 }), Set(indices).count == 3 else {
                        throw GeometryPreviewError.malformed
                    }
                    triangles.append(contentsOf: indices.map { $0 - 1 })
                } else { throw GeometryPreviewError.unsupported }
            }
            guard !triangles.isEmpty else { throw GeometryPreviewError.empty }
            guard triangles.allSatisfy({ Int($0) < vertices.count }) else { throw GeometryPreviewError.malformed }
            // Ignore unreferenced OBJ vertices for framing, reject zero-area faces.
            var remapped: [UInt32: UInt32] = [:]
            var used: [SIMD3<Float>] = []
            for index in triangles.indices {
                let original = triangles[index]
                if let replacement = remapped[original] { triangles[index] = replacement }
                else {
                    let replacement = UInt32(used.count)
                    remapped[original] = replacement
                    used.append(vertices[Int(original)])
                    triangles[index] = replacement
                }
            }
            vertices = used
            for index in stride(from: 0, to: triangles.count, by: 3) {
                let a = vertices[Int(triangles[index + 1])] - vertices[Int(triangles[index])]
                let b = vertices[Int(triangles[index + 2])] - vertices[Int(triangles[index])]
                let cross = SIMD3(a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x)
                guard cross != .zero else { throw GeometryPreviewError.malformed }
            }
        }
        guard let first = vertices.first else { throw GeometryPreviewError.empty }
        var lower = first, upper = first
        for p in vertices {
            lower = SIMD3(min(lower.x,p.x), min(lower.y,p.y), min(lower.z,p.z))
            upper = SIMD3(max(upper.x,p.x), max(upper.y,p.y), max(upper.z,p.z))
        }
        let size = upper - lower
        guard max(size.x, size.y, size.z) > 0.000001 else { throw GeometryPreviewError.empty }
        return GeometryPreview(vertices: vertices, triangles: triangles, sizeMeters: size)
    }

    /// Bounded display mesh: measured points become small octahedra, not a reconstructed surface.
    func displayMesh() throws -> (positions: [SIMD3<Float>], indices: [UInt32], displayedPoints: Int) {
        let lower = vertices.reduce(vertices[0]) { SIMD3(min($0.x,$1.x), min($0.y,$1.y), min($0.z,$1.z)) }
        let upper = vertices.reduce(vertices[0]) { SIMD3(max($0.x,$1.x), max($0.y,$1.y), max($0.z,$1.z)) }
        let center = (lower + upper) / 2
        let factor = 2 / max(sizeMeters.x, sizeMeters.y, sizeMeters.z)
        if !isPointCloud { return (vertices.map { ($0 - center) * factor }, triangles, 0) }
        let count = min(vertices.count, Self.maxDisplayPoints)
        let offsets: [SIMD3<Float>] = [[0.006,0,0],[-0.006,0,0],[0,0.006,0],[0,-0.006,0],[0,0,0.006],[0,0,-0.006]]
        let faces: [UInt32] = [0,2,4, 2,1,4, 1,3,4, 3,0,4, 2,0,5, 1,2,5, 3,1,5, 0,3,5]
        var positions: [SIMD3<Float>] = [], indices: [UInt32] = []
        positions.reserveCapacity(count * 6); indices.reserveCapacity(count * faces.count)
        for i in 0..<count {
            if i % 1024 == 0 { try Task.checkCancellation() }
            let point = (vertices[i * vertices.count / count] - center) * factor
            let base = UInt32(positions.count)
            positions.append(contentsOf: offsets.map { point + $0 })
            indices.append(contentsOf: faces.map { base + $0 })
        }
        return (positions, indices, count)
    }
}

struct GeometryCamera {
    var yaw: Float = 0
    var pitch: Float = 0.2
    var distance: Float = 4.5
    mutating func rotate(horizontal: Float, vertical: Float = 0) {
        guard horizontal.isFinite, vertical.isFinite else { return }
        yaw = (yaw + horizontal).truncatingRemainder(dividingBy: 2 * .pi)
        pitch = min(1.4, max(-1.4, pitch + vertical))
    }
    mutating func zoom(by factor: Float) {
        guard factor.isFinite, factor > 0 else { return }
        distance = min(12, max(2.2, distance / factor))
    }
    var position: SIMD3<Float> {
        SIMD3(distance * cos(pitch) * sin(yaw), distance * sin(pitch), distance * cos(pitch) * cos(yaw))
    }
}
