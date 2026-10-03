import Foundation
import HTDTCaptureCore

#if os(iOS) && canImport(ARKit) && canImport(Vision) && canImport(RoomPlan)
import ARKit
import CoreImage
import CoreVideo
import UIKit
import Vision

// MARK: - Iterative Vision segmentation support (issue #269)
//
// This file holds the platform half of the operator-seeded iterative
// segmentation feature: the downloadable-asset lifecycle, the
// `GenerateIterativeSegmentationRequest` adapter (off the AR delegate
// path), the explicit display-orientation authority that turns a view
// gesture into a Vision seed, and the mask-gated depth sampling that
// feeds the existing world-space targeted fusion.
//
// Prohibitions honored here (issue body):
//   * no fake "lasso" API — lasso gestures are decimated into the
//     request's supported scribble representation;
//   * no fabricated semantic confidence — the observation's scalar
//     `confidence` is never emitted as object-ness;
//   * masks persist only as derived evidence (the Core record);
//   * Vision work runs off the AR delegate path, bounded by policy;
//   * `viewRotationAngle` is adopted only when the SDK reports it.

public enum ObjectSegmentationError: Error, Sendable, Equatable {
    /// OS/framework does not provide the request (< iOS 27).
    case unsupportedOS
    /// `assetStatus` is not `.ready` — no attempt may start
    /// network-dependent work mid-scan, so callers must prep first.
    case assetNotReady
    /// No pose-linked source frame was available to snapshot.
    case noSourceFrame
    /// Vision returned no mask observation for this attempt.
    case noMaskReturned
    /// The accepted mask was empty after thresholding.
    case emptyMask
    /// A refinement point was offered past the bounded count.
    case refinementLimitReached
    /// A refine call arrived with no live request.
    case noActiveRequest
    /// The request could not be constructed/performed.
    case requestFailed(String)
}

/// Host-facing quality-level token mapped onto Vision's
/// `qualityLevel` property. `.balanced` is the deliberate default —
/// `.accurate` costs more per attempt, `.fast` favors latency.
public enum SegmentationQualityLevel: String, Sendable,
    CaseIterable
{
    case accurate
    case balanced
    case fast
}

/// The operator's seed, already mapped into the source image's own
/// coordinate conventions:
/// * point/box are Vision-normalized (lower-left origin);
/// * scribble points are image PIXEL coordinates (top-left origin)
///   rasterized into the request's scribble buffer.
public enum ObjectSegmentationSeed: Sendable {
    case point(x: Double, y: Double)
    case box(x: Double, y: Double, width: Double, height: Double)
    case scribble(imagePixelPoints: [SIMD2<Float>])
}

/// The retained source frame plus the exact display-mapping authority
/// that produced the seed mapping for it. The revision token is
/// persisted on the observation record.
public struct SegmentationSourceFrame: Sendable {
    public let snapshot: CapturedFrameSnapshot
    /// View-normalized → image-normalized affine (ARKit display
    /// transform, view→image direction is its inverse — the caller
    /// inverts through `SegmentationViewToImageMapping`).
    public let imageFromViewDisplayTransform: NormalizedAffine2D
    /// e.g. `arkit_display_transform;authority=view_rotation_angle;
    /// degrees=90.0;viewport_pt=393.0x852.0`
    public let revisionToken: String
    public let authority: SegmentationDisplayAuthority
    public let viewportWidthPoints: Double
    public let viewportHeightPoints: Double
}

// MARK: - Downloadable asset lifecycle

/// Runtime truth for the Vision segmentation model asset. Wraps
/// `assetStatus`/`downloadAssets()` with a single-flight guarantee:
/// capture never blocks on this actor, and a segmentation attempt is
/// never allowed to begin network-dependent work implicitly.
public actor ObjectSegmentationAssetController {
    private var prepareTask: Task<SegmentationAssetReadiness, Never>?

    public init() {}

    /// Read-only probe: never starts a download.
    public func status() async -> SegmentationAssetReadiness {
        guard #available(iOS 27, *) else {
            return .unsupported
        }
        let request = GenerateIterativeSegmentationRequest(
            seedPoint: Vision.NormalizedPoint(x: 0.5, y: 0.5)
        )
        return Self.mapStatus(await request.assetStatus)
    }

    /// Explicit local preparation: `notReady`/`downloading` runs a
    /// bounded `downloadAssets()`; `ready` returns immediately; every
    /// outcome is mirrored back as `SegmentationAssetReadiness`.
    /// Single-flight — concurrent callers share the task.
    @discardableResult
    public func prepare() async -> SegmentationAssetReadiness {
        if let task = prepareTask {
            return await task.value
        }
        guard #available(iOS 27, *) else {
            return .unsupported
        }
        let task = Task<SegmentationAssetReadiness, Never> {
            let request = GenerateIterativeSegmentationRequest(
                seedPoint: Vision.NormalizedPoint(x: 0.5, y: 0.5)
            )
            let initial = Self.mapStatus(await request.assetStatus)
            switch initial {
            case .ready, .unsupported:
                return initial
            case .failed:
                // `.error` status may be transient — one bounded retry
                // is explicit operator-driven work, still offline-safe
                // to attempt because the operator asked for it.
                break
            case .unknown, .notReady, .downloading:
                break
            }
            do {
                try await request.downloadAssets()
            } catch {
                return .failed(String(describing: error))
            }
            return Self.mapStatus(await request.assetStatus)
        }
        prepareTask = task
        let result = await task.value
        prepareTask = nil
        return result
    }

    @available(iOS 27, *)
    private static func mapStatus(
        _ status: DownloadableAssetsRequestStatus
    ) -> SegmentationAssetReadiness {
        switch status {
        case .notReady: return .notReady
        case .downloading: return .downloading
        case .ready: return .ready
        case .error(let error):
            return .failed(String(describing: error))
        @unknown default:
            return .unknown
        }
    }
}

// MARK: - Request adapter

/// One bounded iterative-segmentation run against a single retained
/// source frame. The actor lives off `MainActor`; `perform(on:)` is
/// async and the caller runs the whole attempt inside a detached task,
/// so Vision never executes on the AR delegate path.
public actor IterativeObjectSegmenter {
    /// `GenerateIterativeSegmentationRequest` boxed because the type is
    /// iOS-27-gated and this file compiles on the repo's lower
    /// deployment floor.
    private var requestBox: AnyObject?
    /// `nonisolated(unsafe)` so the retained buffer can be sent into the
    /// request's async `perform(on:)` — writes only happen inside actor
    /// methods, so single-threaded access is preserved in practice.
    nonisolated(unsafe) private var sourceImage: CVPixelBuffer?
    /// Width/height of the retained source image for scribble buffers
    /// and (potentially) mask-space diagnostics.
    private var imageWidth = 0
    private var imageHeight = 0
    public private(set) var refinementCount = 0

    public init() {}

    /// Start a fresh run on `image` (the retained `capturedImage` of a
    /// pose-linked snapshot). `image` is treated as the raw stored
    /// buffer: the display-transform authority already produced seed
    /// coordinates in exactly this pixel space, so `orientation` stays
    /// nil — passing an EXIF-style interpretation would double-rotate.
    @discardableResult
    public func start(
        image: CVPixelBuffer,
        seed: ObjectSegmentationSeed,
        qualityLevel: SegmentationQualityLevel,
        maskAcceptThreshold: Double,
        refinementLimit: Int
    ) async throws -> SegmentationMaskGrid {
        guard #available(iOS 27, *) else {
            throw ObjectSegmentationError.unsupportedOS
        }
        imageWidth = CVPixelBufferGetWidth(image)
        imageHeight = CVPixelBufferGetHeight(image)
        guard imageWidth > 0, imageHeight > 0 else {
            throw ObjectSegmentationError.noSourceFrame
        }

        let request: GenerateIterativeSegmentationRequest
        do {
            switch seed {
            case .point(let x, let y):
                request = GenerateIterativeSegmentationRequest(
                    seedPoint: Vision.NormalizedPoint(x: x, y: y)
                )
            case .box(let x, let y, let width, let height):
                request = GenerateIterativeSegmentationRequest(
                    seedBox: Vision.NormalizedRect(
                        x: x,
                        y: y,
                        width: width,
                        height: height
                    )
                )
            case .scribble(let imagePixelPoints):
                let buffer = try Self.makeScribbleBuffer(
                    imagePixelPoints: imagePixelPoints,
                    width: imageWidth,
                    height: imageHeight
                )
                request = GenerateIterativeSegmentationRequest(
                    seedScribbleBuffer: CVReadOnlyPixelBuffer(
                        unsafeBuffer: buffer
                    )
                )
            }
        } catch {
            throw ObjectSegmentationError.requestFailed(
                String(describing: error)
            )
        }

        switch qualityLevel {
        case .accurate: request.qualityLevel = .accurate
        case .balanced: request.qualityLevel = .balanced
        case .fast: request.qualityLevel = .fast
        }

        requestBox = request
        sourceImage = image
        refinementCount = 0
        self.lastRefinementLimit = refinementLimit
        self.lastThreshold = maskAcceptThreshold
        return try await performCurrent(
            threshold: maskAcceptThreshold
        )
    }

    /// Add one included/excluded point and re-run on the same source
    /// image. Throws `refinementLimitReached` past the policy bound —
    /// the bound is also enforced API-side.
    @discardableResult
    public func refine(
        visionNormalizedX x: Double,
        visionNormalizedY y: Double,
        included: Bool
    ) async throws -> SegmentationMaskGrid {
        guard #available(iOS 27, *) else {
            throw ObjectSegmentationError.unsupportedOS
        }
        guard let request = requestBox
                as? GenerateIterativeSegmentationRequest,
              let image = sourceImage
        else {
            throw ObjectSegmentationError.noActiveRequest
        }
        guard refinementCount < lastRefinementLimit else {
            throw ObjectSegmentationError.refinementLimitReached
        }
        let point = Vision.NormalizedPoint(x: x, y: y)
        do {
            if included {
                try request.addIncludedPoint(point)
            } else {
                try request.addExcludedPoint(point)
            }
        } catch {
            throw ObjectSegmentationError.requestFailed(
                String(describing: error)
            )
        }
        refinementCount += 1
        return try await performCurrent(threshold: lastThreshold)
    }

    /// Abandon the live request — a new `start` replaces it anyway.
    public func cancel() {
        requestBox = nil
        sourceImage = nil
        refinementCount = 0
    }

    private var lastThreshold = 0.5
    private var lastRefinementLimit = 8

    @available(iOS 27, *)
    private func performCurrent(
        threshold: Double
    ) async throws -> SegmentationMaskGrid {
        guard let request = requestBox
                as? GenerateIterativeSegmentationRequest,
              let image = sourceImage
        else {
            throw ObjectSegmentationError.noActiveRequest
        }
        let observation: PixelBufferObservation?
        do {
            observation = try await request.perform(on: image)
        } catch {
            throw ObjectSegmentationError.requestFailed(
                String(describing: error)
            )
        }
        guard let observation else {
            throw ObjectSegmentationError.noMaskReturned
        }
        let grid = Self.maskGrid(
            from: observation,
            threshold: threshold
        )
        if grid.setCount == 0 {
            throw ObjectSegmentationError.emptyMask
        }
        return grid
    }

    /// Threshold the observation's mask buffer into a bit-packed grid.
    /// Supports the one-component formats Vision emits for mask
    /// observations; anything else falls back to bounded `pixel(at:)`
    /// sampling — never guessing a binary mask from an unknown layout.
    @available(iOS 27, *)
    private static func maskGrid(
        from observation: PixelBufferObservation,
        threshold: Double
    ) -> SegmentationMaskGrid {
        let maskWidth = max(1, Int(observation.size.width))
        let maskHeight = max(1, Int(observation.size.height))
        var grid = SegmentationMaskGrid(
            width: maskWidth,
            height: maskHeight
        )

        func fillBySampling() {
            // Bounded fallback for unhandled pixel formats: sample the
            // observation at the mask grid's own resolution.
            for y in 0..<maskHeight {
                let ny = (Double(y) + 0.5) / Double(maskHeight)
                for x in 0..<maskWidth {
                    let nx = (Double(x) + 0.5) / Double(maskWidth)
                    let value = observation.pixel(
                        at: Vision.NormalizedPoint(x: nx, y: ny)
                    )
                    if Double(value) >= threshold {
                        grid.set(x: x, y: y)
                    }
                }
            }
        }

        observation.pixelBuffer.withUnsafeBuffer { buffer in
            let width = CVPixelBufferGetWidth(buffer)
            let height = CVPixelBufferGetHeight(buffer)
            guard width == maskWidth, height == maskHeight,
                  width > 0, height > 0,
                  CVPixelBufferLockBaseAddress(buffer, .readOnly)
                    == kCVReturnSuccess
            else {
                fillBySampling()
                return
            }
            defer {
                CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            }
            guard let base = CVPixelBufferGetBaseAddress(buffer)
            else {
                fillBySampling()
                return
            }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let format = CVPixelBufferGetPixelFormatType(buffer)
            switch format {
            case kCVPixelFormatType_OneComponent32Float:
                guard bytesPerRow
                        >= width * MemoryLayout<Float>.size
                else {
                    fillBySampling()
                    return
                }
                for y in 0..<height {
                    let row = base
                        .advanced(by: y * bytesPerRow)
                        .assumingMemoryBound(to: Float.self)
                    for x in 0..<width {
                        if Double(row[x]) >= threshold {
                            grid.set(x: x, y: y)
                        }
                    }
                }
            case kCVPixelFormatType_OneComponent8:
                guard bytesPerRow >= width else {
                    fillBySampling()
                    return
                }
                let cutoff = UInt8(
                    min(255, max(0, (threshold * 255).rounded()))
                )
                for y in 0..<height {
                    let row = base
                        .advanced(by: y * bytesPerRow)
                        .assumingMemoryBound(to: UInt8.self)
                    for x in 0..<width where row[x] >= cutoff {
                        grid.set(x: x, y: y)
                    }
                }
            case kCVPixelFormatType_OneComponent16Half:
                guard bytesPerRow
                        >= width * MemoryLayout<UInt16>.size
                else {
                    fillBySampling()
                    return
                }
                for y in 0..<height {
                    let row = base
                        .advanced(by: y * bytesPerRow)
                        .assumingMemoryBound(to: UInt16.self)
                    for x in 0..<width {
                        let half = Float16(bitPattern: row[x])
                        if Double(Float(half)) >= threshold {
                            grid.set(x: x, y: y)
                        }
                    }
                }
            default:
                fillBySampling()
            }
        }
        return grid
    }

    /// Rasterize a lasso/scribble path into the request's scribble
    /// buffer: an 8-bit gray buffer at the source image's dimensions
    /// with non-zero pixels along the stroke.
    private static func makeScribbleBuffer(
        imagePixelPoints: [SIMD2<Float>],
        width: Int,
        height: Int
    ) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent8,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = buffer
        else {
            throw ObjectSegmentationError.requestFailed(
                "scribble buffer allocation failed (\(status))"
            )
        }
        guard CVPixelBufferLockBaseAddress(pixelBuffer, [])
                == kCVReturnSuccess
        else {
            throw ObjectSegmentationError.requestFailed(
                "scribble buffer lock failed"
            )
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer)
        else {
            throw ObjectSegmentationError.requestFailed(
                "scribble buffer base address unavailable"
            )
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        memset(base, 0, bytesPerRow * height)
        let radius = max(3, min(width, height) / 100)
        for point in imagePixelPoints {
            let cx = Int(point.x.rounded())
            let cy = Int(point.y.rounded())
            for dy in -radius...radius {
                let y = cy + dy
                guard y >= 0, y < height else { continue }
                for dx in -radius...radius
                where dx * dx + dy * dy <= radius * radius {
                    let x = cx + dx
                    guard x >= 0, x < width else { continue }
                    base
                        .advanced(by: y * bytesPerRow + x)
                        .assumingMemoryBound(to: UInt8.self)
                        .pointee = 0xFF
                }
            }
        }
        return pixelBuffer
    }
}

// MARK: - Display-orientation authority (issue #269)

extension SharedARSessionController {

    /// Retain a pose-linked source frame AND resolve the exact
    /// display-mapping authority for it in one hop, so the seed's
    /// transform and the image it seeds can never mix frames.
    ///
    /// Authority order (#269):
    ///   1. iOS 27 `ARSession.viewRotationAngle` +
    ///      `ARFrame.displayTransform(viewRotationAngle:viewportSize:)`
    ///      — adopted only when the session reports a finite angle,
    ///      which requires `viewLayer` (set in
    ///      `markLiveRoomCaptureViewMounted`);
    ///   2. the documented legacy
    ///      `displayTransform(for:viewportSize:)` fallback keyed by the
    ///      active `UIInterfaceOrientation`.
    ///
    /// The SwiftUI orientation value is never consulted as camera
    /// extrinsics; it only parameterizes the legacy ARKit transform.
    public func snapshotSegmentationSourceFrame(
        viewportWidthPoints: Double,
        viewportHeightPoints: Double,
        interfaceOrientation: UIInterfaceOrientation
    ) throws -> SegmentationSourceFrame {
        guard viewportWidthPoints > 1,
              viewportHeightPoints > 1,
              viewportWidthPoints.isFinite,
              viewportHeightPoints.isFinite,
              let frame = arSession.currentFrame
        else {
            throw PlatformCaptureError.currentFrameUnavailable
        }
        let snapshot = try ARFrameArtifactAdapter.snapshot(
            frame: frame,
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            depthSelection: .discrete
        )

        let viewport = CGSize(
            width: viewportWidthPoints,
            height: viewportHeightPoints
        )
        let transform: CGAffineTransform
        let authority: SegmentationDisplayAuthority
        if #available(iOS 27, *),
           let angle = arSession.viewRotationAngle,
           angle.isFinite
        {
            transform = frame.displayTransform(
                viewRotationAngle: angle,
                viewportSize: viewport
            )
            authority = .viewRotationAngle(degrees: Double(angle))
        } else {
            transform = frame.displayTransform(
                for: interfaceOrientation,
                viewportSize: viewport
            )
            authority = .interfaceOrientation(
                "uiinterfaceorientation=\(interfaceOrientation.rawValue)"
            )
        }

        let affine = NormalizedAffine2D(
            a: Double(transform.a),
            b: Double(transform.b),
            c: Double(transform.c),
            d: Double(transform.d),
            tx: Double(transform.tx),
            ty: Double(transform.ty)
        )
        return SegmentationSourceFrame(
            snapshot: snapshot,
            imageFromViewDisplayTransform: affine,
            revisionToken:
                SegmentationDisplayAuthority.revisionToken(
                    authority: authority,
                    viewportWidthPoints: viewportWidthPoints,
                    viewportHeightPoints: viewportHeightPoints
                ),
            authority: authority,
            viewportWidthPoints: viewportWidthPoints,
            viewportHeightPoints: viewportHeightPoints
        )
    }
}
#endif
