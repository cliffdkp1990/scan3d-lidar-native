import Foundation

/// ARKit's smoothed and discrete depth maps are alternatives from one ARFrame.
/// The camera/point-cloud pipeline must use ONE confidence-validated source
/// for both its center distance and reconstructed geometry.
enum LiDARDepthOrigin: String, Equatable {
    case smoothedSceneDepth
    case sceneDepth
}

enum LiDARDepthFallbackPolicy {
    /// "Available" is NOT enough: only accept a source if a full, coherent
    /// center patch passed depth/confidence validation. Never combine individual
    /// pixels from separate ARKit depth sources to fabricate an estimate.
    static func choose(smoothedCenterValid: Bool, rawCenterValid: Bool) -> LiDARDepthOrigin? {
        if smoothedCenterValid { return .smoothedSceneDepth }
        if rawCenterValid { return .sceneDepth }
        return nil
    }
}
