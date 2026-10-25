import RealityKit
import SwiftUI
import UIKit

/// Debug-only, generated test geometry. Never camera footage or measured LiDAR.
struct StudioFixtureBackdrop:View {
    var body:some View {
        #if DEBUG
        StudioFixtureViewport()
        #else
        Color.black
        #endif
    }
}

#if DEBUG
enum StudioFixtures {
    private static let profile:[(Float,Float)]=[(-0.55,0.18),(-0.5,0.28),(-0.4,0.33),(-0.25,0.34),(-0.1,0.30),(0.05,0.22),(0.17,0.15),(0.32,0.13),(0.45,0.13),(0.48,0.16)]
    static func geometry()->(vertices:[CloudVertex],triangles:[(Int,Int,Int)]) {
        let sectors=48
        var vertices:[CloudVertex]=[], triangles:[(Int,Int,Int)]=[]
        for (y,radius) in profile { for sector in 0..<sectors {
            let angle=Float(sector)*2 * .pi/Float(sectors)
            vertices.append(CloudVertex(x:radius*cos(angle),y:y,z:radius*sin(angle)))
        }}
        for row in 0..<(profile.count-1) { for sector in 0..<sectors {
            let a=row*sectors+sector, b=row*sectors+(sector+1)%sectors
            triangles.append((a,a+sectors,b)); triangles.append((b,a+sectors,b+sectors))
        }}
        return (vertices,triangles)
    }
    private static func denseCloud()->[CloudVertex] {
        var points:[CloudVertex]=[]
        points.reserveCapacity(48_000)
        for row in 0..<400 {
            let y=profile[0].0 + (profile.last!.0-profile[0].0)*Float(row)/399
            let segment=min(profile.count-2,max(0,(0..<(profile.count-1)).first(where:{y<=profile[$0+1].0}) ?? profile.count-2))
            let t=(y-profile[segment].0)/(profile[segment+1].0-profile[segment].0)
            let radius=profile[segment].1+(profile[segment+1].1-profile[segment].1)*t
            for sector in 0..<120 {
                let angle=Float(sector)*2 * .pi/120
                points.append(CloudVertex(x:radius*cos(angle),y:y,z:radius*sin(angle)))
            }
        }
        return points
    }
    static func project(in store:ProjectStore,dense:Bool=false)throws->ScanProject {
        if let existing=try store.library().projects.first(where:{$0.title=="SIMULATOR — TESTDATA"}) { return existing }
        var project=try store.create()
        // The visible title is persisted through the store's existing rename-free manifest format.
        project.title="SIMULATOR — TESTDATA"
        let geometry=geometry()
        let points=dense ? denseCloud():geometry.vertices
        let pointData=GeometryExport.ply(points:points)
        let renderer=UIGraphicsImageRenderer(size:CGSize(width:320,height:320))
        let image=renderer.image { context in
            UIColor(red:0.04,green:0.08,blue:0.10,alpha:1).setFill();context.fill(CGRect(x:0,y:0,width:320,height:320))
            UIColor.systemMint.setStroke();context.cgContext.setLineWidth(4);context.cgContext.strokeEllipse(in:CGRect(x:70,y:55,width:180,height:220))
            ("TESTMOTIV" as NSString).draw(at:CGPoint(x:95,y:145),withAttributes:[.font:UIFont.boldSystemFont(ofSize:20),.foregroundColor:UIColor.white])
        }
        guard let jpeg=image.jpegData(compressionQuality:0.9) else { throw ProjectStoreError.emptyFile }
        for slot in 0..<(dense ? 1:8) {
            project=try store.saveCapture(projectID:project.id,slot:slot,jpeg:jpeg,
                metadata:Data("{\"synthetic_ui_fixture\":true}".utf8),thumbnail:jpeg,pointCloud:pointData)
        }
        if !dense { _=try store.saveExport(projectID:project.id,data:GeometryExport.obj(vertices:geometry.vertices,triangles:geometry.triangles),ext:"obj") }
        // This is an isolated Simulator test project; no deletion or user-original mutation.
        project=try store.load(project.id)
        project.title="SIMULATOR — TESTDATA"
        let manifest=store.root.appendingPathComponent(project.id.uuidString).appendingPathComponent("project.json")
        try JSONEncoder().encode(project).write(to:manifest,options:.atomic)
        return project
    }
}

private struct StudioFixtureViewport:UIViewRepresentable {
    func makeUIView(context:Context)->ARView {
        let view=ARView(frame:.zero,cameraMode:.nonAR,automaticallyConfigureSession:false)
        view.environment.background = .color(UIColor(red:0.10,green:0.15,blue:0.18,alpha:1))
        view.renderOptions=[.disableCameraGrain,.disableMotionBlur,.disableDepthOfField]
        let data=StudioFixtures.geometry()
        var descriptor=MeshDescriptor(name:"Synthetic studio test object")
        descriptor.positions=MeshBuffers.Positions(data.vertices.map { SIMD3<Float>($0.x,$0.y,$0.z) })
        descriptor.primitives = .triangles(data.triangles.flatMap { [UInt32($0.0),UInt32($0.1),UInt32($0.2)] })
        let anchor=AnchorEntity(world:.zero)
        if let mesh=try? MeshResource.generate(from:[descriptor]) {
            var material=PhysicallyBasedMaterial()
            material.baseColor = .init(tint:UIColor(red:0.88,green:0.82,blue:0.70,alpha:1))
            material.roughness = .init(floatLiteral:0.45)
            material.faceCulling = .none
            anchor.addChild(ModelEntity(mesh:mesh,materials:[material]))
        }
        let light=DirectionalLight();light.light.intensity=4000
        light.look(at:.zero,from:[-2,3,3],relativeTo:nil);anchor.addChild(light)
        let fill=DirectionalLight();fill.light.intensity=1400
        fill.look(at:.zero,from:[2,0,-2],relativeTo:nil);anchor.addChild(fill)
        let camera=PerspectiveCamera();camera.camera.fieldOfViewInDegrees=45
        camera.look(at:[0,-0.02,0],from:[1.2,0.55,2.0],relativeTo:nil)
        anchor.addChild(camera);view.scene.addAnchor(anchor)
        return view
    }
    func updateUIView(_ view:ARView,context:Context) {}
    static func dismantleUIView(_ view:ARView,coordinator:()) { view.scene.anchors.removeAll() }
}
#endif
