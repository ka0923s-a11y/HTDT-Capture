import Foundation

// MARK: - Normalized display/image geometry (issue bolph71656-ai/HTDT-Capture#269)
//
// The UI-to-image seed mapping is an explicit authority chain:
//
//   view point (top-left origin, normalized inside the preview view)
//     -> inverse ARKit display transform
//     -> image-normalized point (top-left origin of the capturedImage)
//     -> Vision normalized point (same image, LOWER-LEFT origin)
//
// Only the last flip is Vision-specific; the stored observation record
// uses the image-normalized top-left convention so seed/refinement
// coordinates stay in the same space as `image_width`/`image_height`.

/// One normalized point in the [0,1] unit square.
public struct NormalizedPoint2D: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public var isUnitSquare: Bool {
        x.isFinite && y.isFinite
            && x >= 0 && x <= 1 && y >= 0 && y <= 1
    }
}

/// One normalized rect in the [0,1] unit square (origin + extent).
public struct NormalizedRect2D: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var isUnitSquare: Bool {
        x.isFinite && y.isFinite
            && width.isFinite && height.isFinite
            && x >= 0 && y >= 0
            && width > 0 && height > 0
            && x + width <= 1 && y + height <= 1
    }
}

/// A 2D affine on normalized coordinates with CGAffineTransform
/// semantics: `x' = a*x + c*y + tx`, `y' = b*x + d*y + ty`. ARKit's
/// display transforms have exactly this shape; keeping a Core value
/// type lets the mapping authority be unit-tested without ARKit.
public struct NormalizedAffine2D: Codable, Sendable, Equatable {
    public let a: Double
    public let b: Double
    public let c: Double
    public let d: Double
    public let tx: Double
    public let ty: Double

    public init(
        a: Double,
        b: Double,
        c: Double,
        d: Double,
        tx: Double,
        ty: Double
    ) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public static let identity = NormalizedAffine2D(
        a: 1,
        b: 0,
        c: 0,
        d: 1,
        tx: 0,
        ty: 0
    )

    public func applying(to point: NormalizedPoint2D)
        -> NormalizedPoint2D
    {
        NormalizedPoint2D(
            x: a * point.x + c * point.y + tx,
            y: b * point.x + d * point.y + ty
        )
    }

    /// Exact inverse, or nil when the transform is singular. ARKit
    /// display transforms are always invertible; a nil here means the
    /// caller's transform source was bogus and the gesture must be
    /// dropped, never clamped into a fake seed.
    public func inverted() -> NormalizedAffine2D? {
        let determinant = a * d - b * c
        guard determinant.isFinite,
              determinant.magnitude > 1e-12
        else {
            return nil
        }
        let inverse = 1.0 / determinant
        let ia = d * inverse
        let ib = -b * inverse
        let ic = -c * inverse
        let id = a * inverse
        return NormalizedAffine2D(
            a: ia,
            b: ib,
            c: ic,
            d: id,
            tx: -(ia * tx + ic * ty),
            ty: -(ib * tx + id * ty)
        )
    }
}

/// The display-mapping authority actually used to produce a seed,
/// recorded on the observation. `viewRotationAngle` is the iOS 27
/// ARKit rotation authority; `interfaceOrientation` is the documented
/// legacy path kept as the fallback/reference (legacy bolph71656-ai/HTDT-Capture#269).
public enum SegmentationDisplayAuthority: Sendable, Equatable {
    /// iOS 27 `ARSession.viewRotationAngle` qualified the display
    /// transform; the value is the degrees passed to
    /// `displayTransform(viewRotationAngle:viewportSize:)`.
    case viewRotationAngle(degrees: Double)
    /// Legacy `ARFrame.displayTransform(for:viewportSize:)` path; the
    /// value is the `UIInterfaceOrientation` token that produced it.
    case interfaceOrientation(String)

    /// Stable machine token for the record's
    /// `view_rotation_or_display_transform_revision` field.
    public var revisionToken: String {
        switch self {
        case .viewRotationAngle(let degrees):
            return "authority=view_rotation_angle;degrees="
                + String(format: "%.4f", degrees)
        case .interfaceOrientation(let token):
            return "authority=interface_orientation;orientation="
                + token
        }
    }

    public static func revisionToken(
        authority: SegmentationDisplayAuthority,
        viewportWidthPoints: Double,
        viewportHeightPoints: Double
    ) -> String {
        "arkit_display_transform;"
            + authority.revisionToken
            + ";viewport_pt="
            + String(format: "%.1fx%.1f",
                     viewportWidthPoints, viewportHeightPoints)
    }
}

/// The explicit authority chain from a normalized view point to the
/// Vision request's normalized image point.
public enum SegmentationViewToImageMapping {
    /// Maps a normalized view point (top-left origin inside the
    /// presentation view) through the *inverse* of the ARKit display
    /// transform into image-normalized coordinates (top-left origin of
    /// `capturedImage`). Returns nil when the transform is singular or
    /// the mapped point lands outside the image — a tap outside the
    /// camera's aspect-fill coverage region is not a seed.
    public static func imageNormalizedPoint(
        fromViewPoint viewPoint: NormalizedPoint2D,
        displayTransform: NormalizedAffine2D
    ) -> NormalizedPoint2D? {
        guard viewPoint.isUnitSquare,
              let inverse = displayTransform.inverted()
        else {
            return nil
        }
        let mapped = inverse.applying(to: viewPoint)
        guard mapped.isUnitSquare else {
            return nil
        }
        return mapped
    }

    /// Image-normalized top-left -> Vision lower-left. Vision's
    /// `NormalizedPoint` space is the same pixel space with the y
    /// origin at the bottom of the (already upright) image.
    public static func visionPoint(
        fromImagePoint imagePoint: NormalizedPoint2D
    ) -> NormalizedPoint2D? {
        guard imagePoint.isUnitSquare else {
            return nil
        }
        return NormalizedPoint2D(
            x: imagePoint.x,
            y: 1.0 - imagePoint.y
        )
    }

    /// Convenience: view point straight to a Vision seed point.
    public static func visionPoint(
        fromViewPoint viewPoint: NormalizedPoint2D,
        displayTransform: NormalizedAffine2D
    ) -> NormalizedPoint2D? {
        guard let image = imageNormalizedPoint(
            fromViewPoint: viewPoint,
            displayTransform: displayTransform
        ) else {
            return nil
        }
        return visionPoint(fromImagePoint: image)
    }
}

// MARK: - Bounded policy (issue bolph71656-ai/HTDT-Capture#269)

/// Deliberate bounds on iterative segmentation usage: never at frame
/// rate, bounded refinement counts, bounded persisted mask size.
public struct SegmentationRunPolicy: Sendable, Equatable {
    /// Camera translation (meters) past which the operator may request
    /// a fresh keyframe segmentation for the same pass.
    public var materialViewChangeTranslationMeters: Double = 0.35
    /// Camera yaw (degrees) past which a fresh segmentation is allowed
    /// on request.
    public var materialViewChangeYawDegrees: Double = 25
    /// Hard cap on included/excluded refinement points per mask —
    /// Apple's iterative refinement is documented as bounded; we keep
    /// our own lower bound so a runaway tap loop cannot queue work.
    public var maximumRefinementCount: Int = 8
    /// Mask pixel threshold: Vision mask values >= this count as
    /// object. Recorded on the observation for reproducibility.
    public var maskAcceptThreshold: Double = 0.5
    /// A lasso drag is decimated to at most this many normalized
    /// points before becoming a scribble seed.
    public var maximumScribblePoints: Int = 64
    /// The persisted mask is downsampled to at most this dimension so
    /// the derived doc stays bounded regardless of the sensor size.
    public var persistedMaskMaximumDimension: Int = 256
    /// A mask with fewer set pixels than this is treated as empty —
    /// a speck is not an object selection.
    public var minimumMaskPixelCount: Int = 24
    /// Minimum world points a mask-gated depth observation must yield
    /// to feed the targeted fusion tracker; fewer means the 2D mask
    /// stayed unsupported and only persists as derived evidence.
    public var minimumWorldPointCount: Int = 8

    public init() {}

    public func acceptsRefinement(count: Int) -> Bool {
        count < maximumRefinementCount
    }

    public func viewChangeIsMaterial(
        translationMeters: Double,
        yawDegrees: Double
    ) -> Bool {
        translationMeters >= materialViewChangeTranslationMeters
            || yawDegrees >= materialViewChangeYawDegrees
    }
}

// MARK: - Segmentation mask grid

/// A compact bit-packed binary mask in the source image's pixel space
/// (row 0 = top of image). Bit order: MSB-first within each byte,
/// row-major across the grid.
public struct SegmentationMaskGrid: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// (width*height + 7)/8 bytes, MSB-first row-major.
    public private(set) var bytes: [UInt8]

    public init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
        self.bytes = [UInt8](
            repeating: 0,
            count: (self.width * self.height + 7) / 8
        )
    }

    public init?(width: Int, height: Int, bytes: [UInt8]) {
        guard width >= 0, height >= 0,
              bytes.count == (width * height + 7) / 8
        else {
            return nil
        }
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    public init?(width: Int, height: Int, base64: String) {
        guard let bytes = Data(base64Encoded: base64) else {
            return nil
        }
        self.init(width: width, height: height, bytes: [UInt8](bytes))
    }

    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public func isSet(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else {
            return false
        }
        let bit = y * width + x
        return bytes[bit / 8] & (0x80 >> (bit % 8)) != 0
    }

    public mutating func set(x: Int, y: Int) {
        guard x >= 0, y >= 0, x < width, y < height else {
            return
        }
        let bit = y * width + x
        bytes[bit / 8] |= UInt8(0x80 >> (bit % 8))
    }

    public var setCount: Int {
        var total = 0
        for byte in bytes {
            total += byte.nonzeroBitCount
        }
        return total
    }

    /// Mask membership for an image-normalized top-left point.
    public func contains(
        imageNormalizedX x: Double,
        imageNormalizedY y: Double
    ) -> Bool {
        guard x.isFinite, y.isFinite,
              x >= 0, x < 1, y >= 0, y < 1
        else {
            return false
        }
        return isSet(
            x: min(width - 1, Int(x * Double(width))),
            y: min(height - 1, Int(y * Double(height)))
        )
    }

    /// Whether the depth-map pixel at (dx, dy) of a depth buffer sized
    /// (depthWidth, depthHeight) falls inside the mask. ARKit scene
    /// depth maps are documented to map to the same frame's
    /// `capturedImage` at lower resolution, so depth and image share
    /// one top-left normalized space.
    public func contains(
        depthX dx: Int,
        depthY dy: Int,
        depthWidth: Int,
        depthHeight: Int
    ) -> Bool {
        guard depthWidth > 0, depthHeight > 0 else {
            return false
        }
        return contains(
            imageNormalizedX: (Double(dx) + 0.5) / Double(depthWidth),
            imageNormalizedY: (Double(dy) + 0.5) / Double(depthHeight)
        )
    }

    /// Downsampled copy (nearest set-pixel majority via any-set rule:
    /// a destination bit is set when any covered source bit is set).
    /// Bounds the persisted mask independently of sensor resolution —
    /// never upsampled, which keeps it honest derived evidence.
    public func downsampled(
        toMaximumDimension maximum: Int
    ) -> SegmentationMaskGrid {
        guard maximum > 0, width > maximum || height > maximum else {
            return self
        }
        let scale = max(
            Double(width) / Double(maximum),
            Double(height) / Double(maximum)
        )
        let newWidth = max(1, Int((Double(width) / scale).rounded()))
        let newHeight = max(1, Int((Double(height) / scale).rounded()))
        var result = SegmentationMaskGrid(
            width: newWidth,
            height: newHeight
        )
        for y in 0..<height {
            let targetY = min(newHeight - 1, y * newHeight / height)
            for x in 0..<width where isSet(x: x, y: y) {
                let targetX = min(newWidth - 1, x * newWidth / width)
                result.set(x: targetX, y: targetY)
            }
        }
        return result
    }

    public var base64Encoded: String {
        Data(bytes).base64EncodedString()
    }
}

// MARK: - Seed & gestures

/// The request's initial seed kind. Mirrors
/// `GenerateIterativeSegmentationRequest`'s supported inputs; lasso UI
/// translates to the scribble representation — never a fake API.
public enum SegmentationSeedKind: String, Codable, Sendable {
    case point
    case box
    case scribble
}

/// Which seeding affordance the operator armed in the UI.
public enum SegmentationSeedMode: String, Codable, Sendable,
    CaseIterable
{
    case point
    case box
    case lasso

    public var seedKind: SegmentationSeedKind {
        switch self {
        case .point: return .point
        case .box: return .box
        case .lasso: return .scribble
        }
    }
}

/// One operator gesture on the preview, already normalized inside the
/// presentation view's bounds. The view layer produces this; the
/// coordinator maps it through the display-transform authority.
public enum SegmentationGestureKind: String, Sendable {
    case seedPoint
    case seedBox
    case seedScribble
    case includePoint
    case excludePoint
}

public struct SegmentationGesture: Sendable, Equatable {
    public let kind: SegmentationGestureKind
    /// View-normalized points (top-left origin) — one for taps, the
    /// drag bbox's corners for a box, the decimated path for a lasso.
    public let viewNormalizedPoints: [NormalizedPoint2D]
    /// The presentation view's size in points at gesture time — the
    /// viewportSize the display transform was computed for.
    public let viewportWidthPoints: Double
    public let viewportHeightPoints: Double

    public init(
        kind: SegmentationGestureKind,
        viewNormalizedPoints: [NormalizedPoint2D],
        viewportWidthPoints: Double,
        viewportHeightPoints: Double
    ) {
        self.kind = kind
        self.viewNormalizedPoints = viewNormalizedPoints
        self.viewportWidthPoints = viewportWidthPoints
        self.viewportHeightPoints = viewportHeightPoints
    }
}

// MARK: - Asset readiness (issue bolph71656-ai/HTDT-Capture#269)

/// Runtime truth for the downloadable segmentation model asset.
/// `assetStatus`/`downloadAssets()` on the request is the authority;
/// this is the host-side mirror surfaced to the UI.
public enum SegmentationAssetReadiness: Sendable, Equatable {
    /// Never probed this session.
    case unknown
    /// The OS/Vision level does not provide the request (< iOS 27).
    case unsupported
    /// Asset is not on-device; an explicit prepare/download is needed.
    case notReady
    /// A bounded, single-flight download is in flight.
    case downloading
    /// Ready — a segmentation attempt will not trigger network work.
    case ready
    /// `assetStatus` reported `.error` or the download threw.
    case failed(String)

    /// Only `.ready` admits a segmentation attempt — a not-ready or
    /// in-flight download must never begin network work mid-scan.
    public var admitsSegmentation: Bool {
        if case .ready = self { return true }
        return false
    }
}

// MARK: - Interaction state (view model)

/// The host's published segmentation state for the scanning UI.
public enum SegmentationInteractionPhase: String, Sendable {
    /// Feature unusable: no asset, not supported, or not in a pass.
    case unavailable
    /// Inside a target pass; the operator may arm a seed gesture.
    case seeding
    /// A Vision request is running off the AR delegate path.
    case running
    /// A mask exists; the operator may Use / Refine / Cancel it.
    case maskReady
    /// The mask was accepted — its gated depth observation already
    /// entered the targeted fusion tracker.
    case accepted
    /// The last attempt failed; retry is a fresh seed.
    case failed
}

public struct SegmentationInteractionState: Sendable, Equatable {
    public var phase: SegmentationInteractionPhase
    public var assetReadiness: SegmentationAssetReadiness
    /// Set pixels in the current mask (source-image resolution).
    public var maskPixelCount: Int?
    /// World points the accepted mask contributed to fusion.
    public var fusedWorldPointCount: Int?
    public var refinementCount: Int
    /// Whether a refinement point may still be added (bounded policy).
    public var canRefine: Bool
    /// Whether a fresh segmentation may be requested now (policy).
    public var canResegment: Bool
    /// Short machine detail for the status line, never localized copy.
    public var detail: String?

    public init(
        phase: SegmentationInteractionPhase,
        assetReadiness: SegmentationAssetReadiness,
        maskPixelCount: Int? = nil,
        fusedWorldPointCount: Int? = nil,
        refinementCount: Int = 0,
        canRefine: Bool = false,
        canResegment: Bool = false,
        detail: String? = nil
    ) {
        self.phase = phase
        self.assetReadiness = assetReadiness
        self.maskPixelCount = maskPixelCount
        self.fusedWorldPointCount = fusedWorldPointCount
        self.refinementCount = refinementCount
        self.canRefine = canRefine
        self.canResegment = canResegment
        self.detail = detail
    }

    public static let unavailable = SegmentationInteractionState(
        phase: .unavailable,
        assetReadiness: .unknown
    )
}

// MARK: - Persisted observation record (issue bolph71656-ai/HTDT-Capture#269)

public struct SegmentationObservationID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public enum SegmentationPersistenceError: Error, Sendable, Equatable {
    case invalidIdentifier
    case invalidSessionTimestamp
    case invalidImageDimensions
    case invalidRefinementCount
    case emptyDisplayTransformRevision
    case missingSeedGeometry
    case tooManySeedPoints
    case pointOutsideUnitSquare
    case invalidMaskEncoding
    case invalidMaskDimensions
    case emptyQualityLevel
    case emptyFrameworkContext
    case missingSourceFrameReference
    case negativePointCount
    case missingSourcePayloadReference
    case encodedDocumentMismatch
}

/// One accepted segmentation, persisted as a derived image-processing
/// observation (issue bolph71656-ai/HTDT-Capture#269): the mask lives only here — linked to its
/// exact source frame + seed/refinement metadata — never as canonical
/// geometry and never with a fabricated semantic confidence.
public struct ObjectSegmentationObservation: Codable, Sendable,
    Equatable
{
    /// Hard bound on refinement coordinate lists so a pathological
    /// session cannot grow the doc unbounded.
    public static let maxCoordinateList = 64

    public let observationID: SegmentationObservationID
    public let captureSessionID: CaptureSessionID
    public let coordinateSpaceID: CoordinateSpaceID
    /// `path:` ref to the persisted source frame descriptor
    /// (`evidence/frames/<id>.json`) — the exact frame the request
    /// ran on, materialized through the normal frame pipeline.
    public let sourceFrameRef: String
    /// `streamed` — the ARKit session frame; `high_quality_visual`
    /// is reserved for legacy bolph71656-ai/HTDT-Capture#275 sources and never emitted yet.
    public let sourceFrameKind: String
    public let sessionTimestampSeconds: Double
    public let imageWidth: Int
    public let imageHeight: Int
    public let pixelFormatFourCC: UInt32
    /// Which display-mapping authority produced the seed mapping
    /// (viewRotationAngle degrees or the legacy orientation token,
    /// plus the viewport size the transform was computed for).
    public let viewRotationOrDisplayTransformRevision: String
    public let seedKind: SegmentationSeedKind
    /// Seed coordinates in image-normalized top-left space: one point
    /// (point), the rect origin+extent (box), or the decimated path
    /// (scribble).
    public let seedPoints: [NormalizedPoint2D]
    public let seedBox: NormalizedRect2D?
    /// Included/excluded refinement points, same convention.
    public let refinementIncludedPoints: [NormalizedPoint2D]
    public let refinementExcludedPoints: [NormalizedPoint2D]
    public let refinementCount: Int
    /// accurate | balanced | fast (Vision `qualityLevel` token).
    public let qualityLevel: String
    public let maskWidth: Int
    public let maskHeight: Int
    /// "bitpack_msb_rows_base64" — MSB-first row-major bitpack of the
    /// accepted (thresholded) mask at `mask_width`x`mask_height`.
    public let maskEncoding: String
    /// "inline" — the mask payload is `mask_payload_base64`.
    public let maskPayloadRef: String
    public let maskPayloadBase64: String
    /// The threshold applied to Vision mask values to accept pixels.
    public let maskAcceptThreshold: Double
    /// Vision request identifier actually used.
    public let visionRequest: String
    public let osVersion: String
    public let osBuild: String
    public let appVersion: String
    public let appBuild: String
    /// `path:` ref to the frame the downstream depth/mesh evidence
    /// was sampled from — the same source frame for this feature.
    public let downstreamSpatialFrameRef: String?
    /// e.g. "arkit_confidence_map_nonzero" | "confidence_map_absent".
    public let downstreamDepthConfidencePolicy: String?
    /// World points the accepted mask contributed to the targeted
    /// fusion tracker; 0 means the 2D mask stayed unsupported and is
    /// persisted only as derived evidence (never extruded).
    public let downstream3DPointCount: Int

    public init(
        observationID: SegmentationObservationID =
            SegmentationObservationID(),
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        sourceFrameRef: String,
        sourceFrameKind: String,
        sessionTimestampSeconds: Double,
        imageWidth: Int,
        imageHeight: Int,
        pixelFormatFourCC: UInt32,
        viewRotationOrDisplayTransformRevision: String,
        seedKind: SegmentationSeedKind,
        seedPoints: [NormalizedPoint2D],
        seedBox: NormalizedRect2D? = nil,
        refinementIncludedPoints: [NormalizedPoint2D] = [],
        refinementExcludedPoints: [NormalizedPoint2D] = [],
        refinementCount: Int,
        qualityLevel: String,
        maskWidth: Int,
        maskHeight: Int,
        maskEncoding: String,
        maskPayloadRef: String,
        maskPayloadBase64: String,
        maskAcceptThreshold: Double,
        visionRequest: String,
        osVersion: String,
        osBuild: String,
        appVersion: String,
        appBuild: String,
        downstreamSpatialFrameRef: String? = nil,
        downstreamDepthConfidencePolicy: String? = nil,
        downstream3DPointCount: Int
    ) throws {
        guard sessionTimestampSeconds.isFinite,
              sessionTimestampSeconds >= 0
        else {
            throw SegmentationPersistenceError.invalidSessionTimestamp
        }
        guard imageWidth > 0, imageHeight > 0 else {
            throw SegmentationPersistenceError.invalidImageDimensions
        }
        guard refinementCount >= 0 else {
            throw SegmentationPersistenceError.invalidRefinementCount
        }
        let normalizedRevision = SchemaOwnedText.nfc(
            viewRotationOrDisplayTransformRevision
        )
        guard !normalizedRevision.isEmpty else {
            throw SegmentationPersistenceError
                .emptyDisplayTransformRevision
        }
        let normalizedSourceRef = SchemaOwnedText.nfc(sourceFrameRef)
        guard !normalizedSourceRef.isEmpty else {
            throw SegmentationPersistenceError
                .missingSourceFrameReference
        }
        let allPoints =
            seedPoints + refinementIncludedPoints
            + refinementExcludedPoints
        guard allPoints.count <= Self.maxCoordinateList * 3 else {
            throw SegmentationPersistenceError.tooManySeedPoints
        }
        guard allPoints.allSatisfy(\.isUnitSquare) else {
            throw SegmentationPersistenceError.pointOutsideUnitSquare
        }
        switch seedKind {
        case .point:
            guard seedPoints.count == 1, seedBox == nil else {
                throw SegmentationPersistenceError.missingSeedGeometry
            }
        case .box:
            guard let seedBox, seedBox.isUnitSquare else {
                throw SegmentationPersistenceError.missingSeedGeometry
            }
        case .scribble:
            guard seedPoints.count >= 2 else {
                throw SegmentationPersistenceError.missingSeedGeometry
            }
        }
        guard maskWidth > 0, maskHeight > 0 else {
            throw SegmentationPersistenceError.invalidMaskDimensions
        }
        guard maskEncoding == "bitpack_msb_rows_base64",
              SegmentationMaskGrid(
                width: maskWidth,
                height: maskHeight,
                base64: maskPayloadBase64
              ) != nil
        else {
            throw SegmentationPersistenceError.invalidMaskEncoding
        }
        let normalizedQuality = SchemaOwnedText.nfc(qualityLevel)
        guard ["accurate", "balanced", "fast"]
            .contains(normalizedQuality)
        else {
            throw SegmentationPersistenceError.emptyQualityLevel
        }
        let normalizedRequest = SchemaOwnedText.nfc(visionRequest)
        let normalizedOS = SchemaOwnedText.nfc(osVersion)
        let normalizedOSBuild = SchemaOwnedText.nfc(osBuild)
        guard !normalizedRequest.isEmpty, !normalizedOS.isEmpty,
              !normalizedOSBuild.isEmpty
        else {
            throw SegmentationPersistenceError.emptyFrameworkContext
        }
        guard downstream3DPointCount >= 0 else {
            throw SegmentationPersistenceError.negativePointCount
        }

        self.observationID = observationID
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.sourceFrameRef = normalizedSourceRef
        self.sourceFrameKind = sourceFrameKind
        self.sessionTimestampSeconds = sessionTimestampSeconds
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.pixelFormatFourCC = pixelFormatFourCC
        self.viewRotationOrDisplayTransformRevision = normalizedRevision
        self.seedKind = seedKind
        self.seedPoints = seedPoints
        self.seedBox = seedBox
        self.refinementIncludedPoints = refinementIncludedPoints
        self.refinementExcludedPoints = refinementExcludedPoints
        self.refinementCount = refinementCount
        self.qualityLevel = normalizedQuality
        self.maskWidth = maskWidth
        self.maskHeight = maskHeight
        self.maskEncoding = maskEncoding
        self.maskPayloadRef = maskPayloadRef
        self.maskPayloadBase64 = maskPayloadBase64
        self.maskAcceptThreshold = maskAcceptThreshold
        self.visionRequest = normalizedRequest
        self.osVersion = normalizedOS
        self.osBuild = normalizedOSBuild
        self.appVersion = SchemaOwnedText.nfc(appVersion)
        self.appBuild = SchemaOwnedText.nfc(appBuild)
        self.downstreamSpatialFrameRef = downstreamSpatialFrameRef
            .map(SchemaOwnedText.nfc)
        self.downstreamDepthConfidencePolicy =
            downstreamDepthConfidencePolicy.map(SchemaOwnedText.nfc)
        self.downstream3DPointCount = downstream3DPointCount
    }

    private enum CodingKeys: String, CodingKey {
        case observationID = "observation_id"
        case captureSessionID = "capture_session_id"
        case coordinateSpaceID = "coordinate_space_id"
        case sourceFrameRef = "source_frame_ref"
        case sourceFrameKind = "source_frame_kind"
        case sessionTimestampSeconds = "session_timestamp_s"
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case pixelFormatFourCC = "pixel_format_fourcc"
        case viewRotationOrDisplayTransformRevision =
            "view_rotation_or_display_transform_revision"
        case seedKind = "seed_kind"
        case seedPoints = "seed_points"
        case seedBox = "seed_box"
        case refinementIncludedPoints = "refinement_included_points"
        case refinementExcludedPoints = "refinement_excluded_points"
        case refinementCount = "refinement_count"
        case qualityLevel = "quality_level"
        case maskWidth = "mask_width"
        case maskHeight = "mask_height"
        case maskEncoding = "mask_encoding"
        case maskPayloadRef = "mask_payload_ref"
        case maskPayloadBase64 = "mask_payload_base64"
        case maskAcceptThreshold = "mask_accept_threshold"
        case visionRequest = "vision_request"
        case osVersion = "os_version"
        case osBuild = "os_build"
        case appVersion = "app_version"
        case appBuild = "app_build"
        case downstreamSpatialFrameRef =
            "downstream_spatial_frame_ref"
        case downstreamDepthConfidencePolicy =
            "downstream_depth_confidence_policy"
        case downstream3DPointCount = "downstream_3d_point_count"
    }
}

/// `derived/segmentation-observations.json` — the bounded set of
/// accepted segmentation observations for this revision.
public struct ObjectSegmentationObservationDocument: Codable, Sendable,
    Equatable
{
    public let schema: String
    public let schemaVersion: String
    public let captureRevisionID: CaptureRevisionID
    public let captureSessionID: CaptureSessionID
    public let observations: [ObjectSegmentationObservation]

    public init(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        observations: [ObjectSegmentationObservation]
    ) {
        self.schema = ObjectSegmentationObservationPackage.schema
        self.schemaVersion =
            ObjectSegmentationObservationPackage.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.captureSessionID = captureSessionID
        self.observations = observations
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case captureSessionID = "capture_session_id"
        case observations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == ObjectSegmentationObservationPackage.schema,
              schemaVersion
                == ObjectSegmentationObservationPackage.schemaVersion
        else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription:
                        "Unsupported segmentation observations schema"
                )
            )
        }
        try self.init(
            captureRevisionID: container.decode(
                CaptureRevisionID.self,
                forKey: .captureRevisionID
            ),
            captureSessionID: container.decode(
                CaptureSessionID.self,
                forKey: .captureSessionID
            ),
            observations: container.decode(
                [ObjectSegmentationObservation].self,
                forKey: .observations
            )
        )
    }
}

public struct ObjectSegmentationObservationPackage: Sendable,
    Equatable
{
    public static let schema =
        "htdt.capture.segmentation-observations"
    public static let schemaVersion = "1.0.0"
    public static let path = "derived/segmentation-observations.json"

    public let document: ObjectSegmentationObservationDocument
    public let data: Data

    public init(
        document: ObjectSegmentationObservationDocument,
        data: Data
    ) {
        self.document = document
        self.data = data
    }
}

public enum ObjectSegmentationObservationPackageBuilder {
    /// Builds the accepted-End segmentation observation payload.
    /// `sourcePayloadRefs` are the manifest `path:` refs the records
    /// depend on (the persisted source frame descriptors).
    public static func build(
        observations: [ObjectSegmentationObservation],
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        sourcePayloadRefs: [String]
    ) throws -> (
        package: ObjectSegmentationObservationPackage,
        declaration: BundlePayloadDeclaration
    ) {
        let document = ObjectSegmentationObservationDocument(
            captureRevisionID: captureRevisionID,
            captureSessionID: captureSessionID,
            observations: observations
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, .withoutEscapingSlashes,
        ]
        let data = try encoder.encode(document)
        guard
            let decoded = try? JSONDecoder().decode(
                ObjectSegmentationObservationDocument.self,
                from: data
            ),
            decoded == document
        else {
            throw SegmentationPersistenceError.encodedDocumentMismatch
        }

        let normalizedRefs = SchemaOwnedText.nfc(sourcePayloadRefs)
        guard !normalizedRefs.isEmpty else {
            throw SegmentationPersistenceError
                .missingSourcePayloadReference
        }
        let declaration = BundlePayloadDeclaration(
            path: ObjectSegmentationObservationPackage.path,
            mediaType: "application/json",
            producer: "derived_segmentation",
            provenanceClass: .captureAppDerived,
            role: .derived,
            sourceRefs: normalizedRefs
        )
        return (
            ObjectSegmentationObservationPackage(
                document: document,
                data: data
            ),
            declaration
        )
    }
}

// MARK: - Depth/mesh gating math (testable without ARKit)

public enum SegmentationDepthGate {
    /// Projects a world point through the frame's own
    /// `T_world_from_camera` + intrinsics into the capturedImage's
    /// pixel space and tests the mask there — the "rays constrain
    /// mesh support" direction of legacy bolph71656-ai/HTDT-Capture#269. Returns nil when the point is
    /// behind the camera or lands outside the image.
    public static func projectedImagePoint(
        worldX: Double,
        worldY: Double,
        worldZ: Double,
        worldFromCamera: Matrix4x4F,
        intrinsics: CameraIntrinsics3x3
    ) -> (x: Double, y: Double)? {
        // Rigid-inverse: camera = R^T * (world - t). Column-major
        // values: rotation basis in columns 0-2, translation in col 3.
        let v = worldFromCamera.values
        let dx = Float(worldX) - v[12]
        let dy = Float(worldY) - v[13]
        let dz = Float(worldZ) - v[14]
        let camX = v[0] * dx + v[1] * dy + v[2] * dz
        let camY = v[4] * dx + v[5] * dy + v[6] * dz
        let camZ = v[8] * dx + v[9] * dy + v[10] * dz
        // ARKit camera looks down -Z; points in front have camZ < 0.
        let depth = -camZ
        guard depth.isFinite, depth > 0 else {
            return nil
        }
        let k = intrinsics.values
        let px = Double(k[0]) * Double(camX) / Double(depth)
            + Double(k[6])
        let py = Double(k[7])
            - Double(k[4]) * Double(camY) / Double(depth)
        guard px.isFinite, py.isFinite else {
            return nil
        }
        return (px, py)
    }

    /// Whether a world point projects inside the mask on the given
    /// frame — used to constrain candidate mesh support to the
    /// segmented region without fabricating new surface.
    public static func maskContains(
        mask: SegmentationMaskGrid,
        worldX: Double,
        worldY: Double,
        worldZ: Double,
        worldFromCamera: Matrix4x4F,
        intrinsics: CameraIntrinsics3x3,
        imageWidth: Int,
        imageHeight: Int
    ) -> Bool {
        guard imageWidth > 0, imageHeight > 0,
              let pixel = projectedImagePoint(
                worldX: worldX,
                worldY: worldY,
                worldZ: worldZ,
                worldFromCamera: worldFromCamera,
                intrinsics: intrinsics
              )
        else {
            return false
        }
        return mask.contains(
            imageNormalizedX: pixel.x / Double(imageWidth),
            imageNormalizedY: pixel.y / Double(imageHeight)
        )
    }
}
