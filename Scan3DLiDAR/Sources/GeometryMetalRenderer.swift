import MetalKit
import simd

/// Own bounded stored-file renderer. No camera session or second RealityKit scene.
/// GPU buffers are immutable; uniforms are copied into each submitted command.
final class GeometryMetalRenderer: NSObject, MTKViewDelegate {
    private struct Uniforms {
        var transform: simd_float4x4
        var tint: SIMD4<Float>
        var options: SIMD4<Float>
    }
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depth: MTLDepthStencilState
    private let vertices: MTLBuffer
    private let indices: MTLBuffer?
    private let vertexCount: Int
    private let indexCount: Int
    var camera = GeometryCamera()
    var lightBackground = false

    init(view: MTKView, positions: [SIMD3<Float>], indices: [UInt32]) throws {
        guard let device = view.device, let queue = device.makeCommandQueue(), !positions.isEmpty else {
            throw RenderError.unavailable
        }
        let packed = positions.map { SIMD4<Float>($0, 1) }
        guard let vertices = packed.withUnsafeBytes({ bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }) else { throw RenderError.unavailable }
        self.vertices = vertices
        self.queue = queue
        vertexCount = positions.count
        indexCount = indices.count
        if indices.isEmpty { self.indices = nil }
        else {
            guard let buffer = indices.withUnsafeBytes({ bytes in
                device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
            }) else { throw RenderError.unavailable }
            self.indices = buffer
        }
        // Small first-party shader compiled once per viewer; no downloaded executable code.
        let library = try device.makeLibrary(source: Self.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "geometryVertex")
        descriptor.fragmentFunction = library.makeFunction(name: indices.isEmpty ? "pointFragment" : "meshFragment")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        descriptor.rasterSampleCount = view.sampleCount
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depth = device.makeDepthStencilState(descriptor: depthDescriptor) else { throw RenderError.unavailable }
        self.depth = depth
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.setNeedsDisplay() }

    func draw(in view: MTKView) {
        guard view.drawableSize.width > 0, view.drawableSize.height > 0 else { return }
        view.clearColor = lightBackground ? MTLClearColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1)
            : MTLClearColor(red: 0.008, green: 0.016, blue: 0.025, alpha: 1)
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        let eye = camera.position
        let forward = simd_normalize(-eye)
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0,1,0)))
        let up = simd_cross(right, forward)
        let look = simd_float4x4(columns: (
            SIMD4(right.x,up.x,-forward.x,0), SIMD4(right.y,up.y,-forward.y,0),
            SIMD4(right.z,up.z,-forward.z,0),
            SIMD4(-simd_dot(right,eye),-simd_dot(up,eye),simd_dot(forward,eye),1)))
        let aspect = Float(view.drawableSize.width / view.drawableSize.height)
        let y: Float = 1 / tan(25 * .pi / 180), near: Float = 0.01, far: Float = 50
        let z = far / (near - far)
        let projection = simd_float4x4(columns: (
            SIMD4(y/aspect,0,0,0), SIMD4(0,y,0,0), SIMD4(0,0,z,-1), SIMD4(0,0,near*z,0)))
        var uniforms = Uniforms(transform: projection * look,
            tint: lightBackground ? SIMD4(0.008,0.24,0.30,1) : SIMD4(0.04,0.82,0.77,1),
            options: SIMD4(Float(view.contentScaleFactor) * 2.2,0,0,0))
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depth)
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        if let indices {
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32,
                indexBuffer: indices, indexBufferOffset: 0)
        } else { encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: vertexCount) }
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }

    enum RenderError: LocalizedError {
        case unavailable
        var errorDescription: String? { "3D-rendereren kunne ikke startes på denne enhed. Originalfilen er bevaret." }
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Uniforms { float4x4 transform; float4 tint; float4 options; };
    struct Vertex { float4 position [[position]]; float3 world; float size [[point_size]]; };
    vertex Vertex geometryVertex(uint id [[vertex_id]], const device float4 *positions [[buffer(0)]],
                                 constant Uniforms &u [[buffer(1)]]) {
        Vertex out; out.position=u.transform*positions[id]; out.world=positions[id].xyz;
        out.size=u.options.x; return out;
    }
    fragment float4 pointFragment(Vertex in [[stage_in]], float2 uv [[point_coord]],
                                   constant Uniforms &u [[buffer(1)]]) {
        if (distance(uv,float2(0.5))>0.5) discard_fragment();
        return u.tint;
    }
    fragment float4 meshFragment(Vertex in [[stage_in]], constant Uniforms &u [[buffer(1)]]) {
        float3 normal=normalize(cross(dfdx(in.world),dfdy(in.world)));
        float diffuse=0.45+0.55*abs(dot(normal,normalize(float3(0.4,0.8,1.0))));
        return float4(u.tint.rgb*diffuse,1);
    }
    """
}
