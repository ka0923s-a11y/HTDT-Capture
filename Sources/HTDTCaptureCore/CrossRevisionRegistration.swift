import Foundation

/// Identity for an accepted cross-revision spatial registration
/// (issue #395). A distinct identity space from capture identifiers —
/// registrations are app-local authority records, not captures.
public struct CrossRevisionRegistrationID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// How a correspondence pair was physically established between two
/// finalized capture coordinate spaces (issue #395).
public enum CrossRevisionCorrespondenceKind:
    String,
    Codable,
    Sendable,
    Equatable
{
    /// Derived from each revision's committed room field datum — the
    /// same physical install datum declared in both spaces.
    case sharedFieldDatum = "shared_field_datum"
    /// The same declared reference target observed in both revisions —
    /// identity attested by target_id equality on both sides.
    case referenceTarget = "reference_target"
    /// Operator-declared corresponding points in the two spaces.
    case manualPoint = "manual_point"
}

/// Whether a registration may estimate a uniform scale correction
/// (issue #395). The default is rigid: scale changes stay forbidden
/// unless the operator explicitly declares the policy up front.
public enum CrossRevisionScalePolicy:
    String,
    Codable,
    Sendable,
    Equatable
{
    /// Pure rigid registration — rotation + translation only.
    case rigidOnly = "rigid_only"
    /// Uniform-scale correction permitted; the fitted factor is
    /// recorded verbatim, never silently applied elsewhere.
    case uniformScalePermitted = "uniform_scale_permitted"
}

/// One physical correspondence attested between two capture spaces:
/// the same physical point observed at `sourcePosition` in the source
/// revision's coordinate space and at `targetPosition` in the target's
/// (issue #395). `ref` names the physical referent — a
/// `reference_target:<id>` token, a manual-point label, or a
/// `field_datum:<element>` token — so the pairing is inspectable
/// rather than an anonymous index.
public struct CrossRevisionCorrespondence:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    public let kind: CrossRevisionCorrespondenceKind
    public let ref: String
    /// Position in the source revision's coordinate space, meters.
    public let sourcePosition: WorldPoint3D
    /// The same physical point in the target revision's coordinate
    /// space, meters.
    public let targetPosition: WorldPoint3D

    public init(
        kind: CrossRevisionCorrespondenceKind,
        ref: String,
        sourcePosition: WorldPoint3D,
        targetPosition: WorldPoint3D
    ) throws {
        guard !ref.isEmpty else {
            throw CrossRevisionRegistrationError.emptyField
        }
        guard sourcePosition.isFinite, targetPosition.isFinite else {
            throw CrossRevisionRegistrationError
                .nonFiniteCorrespondence(ref)
        }
        self.kind = kind
        self.ref = ref
        self.sourcePosition = sourcePosition
        self.targetPosition = targetPosition
    }

    public var id: String { ref }

    private enum CodingKeys: String, CodingKey {
        case kind
        case ref
        case sourcePosition = "source_position_m"
        case targetPosition = "target_position_m"
    }
}

/// The post-fit residual of one correspondence, meters — surfaced
/// before acceptance so the operator sees the fit quality per point,
/// not just an aggregate.
public struct CrossRevisionCorrespondenceResidual:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    public let ref: String
    public let residualMeters: Double

    public init(ref: String, residualMeters: Double) {
        self.ref = ref
        self.residualMeters = residualMeters
    }

    public var id: String { ref }

    private enum CodingKeys: String, CodingKey {
        case ref
        case residualMeters = "residual_m"
    }
}

public enum CrossRevisionRegistrationError:
    Error,
    Sendable,
    Equatable
{
    case emptyField
    /// Fewer than three usable correspondences were supplied.
    case insufficientCorrespondences(found: Int)
    /// The correspondence geometry is degenerate — coincident or
    /// collinear points cannot determine a rigid transform; the
    /// registration fails closed rather than emitting a confident
    /// wrong answer.
    case degenerateCorrespondences
    case nonFiniteCorrespondence(String)
    case duplicateCorrespondenceRef(String)
    /// The pair identities do not match (empty ref or differing
    /// identity on the two sides of a pairing).
    case mismatchedCorrespondenceIdentity
    /// Correspondences in one registration must share a mechanism.
    case mixedCorrespondenceKinds
    /// A uniform-scale fit was requested under `rigid_only` policy,
    /// or a fitted transform/scale was not finite and positive.
    case scaleNotPermitted
    /// The fitted rigid transform failed the `Matrix4x4F` contract —
    /// defensive fail-close; indicates degenerate solver input that
    /// slipped the geometric checks.
    case transformNonRigid
    case invalidResidualValue
    case invalidTimestamp
    /// An accepted registration already binds this (source → target)
    /// ordered revision pair — registrations are immutable once
    /// accepted, so a second one is refused rather than overwriting.
    case conflictingRegistration
    case unknownRegistration(String)
    case unreadableDocument
    case schemaMismatch
    case encodedDocumentMismatch
}

/// Solver output for a proposed registration — everything the operator
/// needs to inspect before accepting: the transform, the scale factor
/// actually fitted, per-correspondence residuals, and RMS/max
/// aggregates (issue #395).
public struct CrossRevisionRegistrationSolve:
    Sendable,
    Equatable
{
    /// Rigid part of the fit (rotation + translation). With a
    /// uniform-scale fit the stored transform stays rigid — the scale
    /// factor is carried separately so the `Matrix4x4F` contract
    /// (orthonormal basis, det +1) is never weakened.
    public let targetFromSource: Matrix4x4F
    /// Fitted uniform scale factor. Always exactly 1 under
    /// `rigidOnly` policy.
    public let uniformScale: Double
    public let residuals: [CrossRevisionCorrespondenceResidual]
    public let rmsMeters: Double
    public let maxResidualMeters: Double
    /// Edge uncertainty used by registration-graph accumulation:
    /// the worst single-point fit residual — an honest floor, not a
    /// tuned estimate.
    public var uncertaintyMeters: Double {
        maxResidualMeters
    }
}

/// Least-squares absolute-orientation solver for cross-revision
/// registration (issue #395). Rigid by default: Horn's unit-
/// quaternion closed form on double-precision points — no
/// dependencies, deterministic. Uniform scale is fitted only when
/// `uniformScalePermitted` was explicitly requested; the fitted
/// factor `s` minimizes `Σ|q_i − (s·R·p_i + t)|²` exactly
/// (`s = Σ q_i·(R p_i) / Σ|p_i|²` with centered points).
///
/// Failure is closed: fewer than three correspondences, non-finite
/// coordinates, duplicated referents, or collinear/coincident
/// geometry all throw rather than emit a transform.
public enum CrossRevisionRegistrationSolver {
    /// Minimum usable correspondences for a rigid solve.
    public static let minimumCorrespondences = 3
    /// Geometry below this span (meters) cannot orient a solve.
    private static let degenerateSpanMeters = 1e-6
    /// Maximum allowed perpendicular off-line deviation, relative to
    /// the point set's span, before the set counts as collinear.
    private static let collinearityFraction = 1e-3

    public static func solve(
        correspondences: [CrossRevisionCorrespondence],
        scalePolicy: CrossRevisionScalePolicy = .rigidOnly
    ) throws -> CrossRevisionRegistrationSolve {
        guard correspondences.count >= minimumCorrespondences else {
            throw CrossRevisionRegistrationError
                .insufficientCorrespondences(
                    found: correspondences.count
                )
        }
        var seenRefs = Set<String>()
        var kinds = Set<CrossRevisionCorrespondenceKind>()
        var source: [WorldPoint3D] = []
        var target: [WorldPoint3D] = []
        for pair in correspondences {
            guard !pair.ref.isEmpty else {
                throw CrossRevisionRegistrationError
                    .mismatchedCorrespondenceIdentity
            }
            guard pair.sourcePosition.isFinite,
                  pair.targetPosition.isFinite
            else {
                throw CrossRevisionRegistrationError
                    .nonFiniteCorrespondence(pair.ref)
            }
            guard seenRefs.insert(pair.ref).inserted else {
                throw CrossRevisionRegistrationError
                    .duplicateCorrespondenceRef(pair.ref)
            }
            kinds.insert(pair.kind)
            source.append(pair.sourcePosition)
            target.append(pair.targetPosition)
        }
        guard kinds.count == 1 else {
            throw CrossRevisionRegistrationError
                .mixedCorrespondenceKinds
        }
        guard !Self.isDegenerate(source),
              !Self.isDegenerate(target)
        else {
            throw CrossRevisionRegistrationError
                .degenerateCorrespondences
        }

        let centroidS = Self.centroid(source)
        let centroidT = Self.centroid(target)
        var p: [WorldPoint3D] = []
        var q: [WorldPoint3D] = []
        p.reserveCapacity(source.count)
        q.reserveCapacity(target.count)
        for i in source.indices {
            p.append(Self.subtract(source[i], centroidS))
            q.append(Self.subtract(target[i], centroidT))
        }

        let rotation = Self.fitRotation(p: p, q: q)
        let scale: Double
        switch scalePolicy {
        case .rigidOnly:
            scale = 1
        case .uniformScalePermitted:
            var numerator = 0.0
            var denominator = 0.0
            for i in p.indices {
                let rotated = Self.applyRotation(rotation, p[i])
                numerator += q[i].dot(rotated)
                denominator += p[i].dot(p[i])
            }
            guard denominator > 0 else {
                throw CrossRevisionRegistrationError
                    .degenerateCorrespondences
            }
            let fitted = numerator / denominator
            guard fitted.isFinite, fitted > 0 else {
                throw CrossRevisionRegistrationError
                    .scaleNotPermitted
            }
            scale = fitted
        }

        // t = centroidT − s·R·centroidS
        let rotatedCentroid = Self.applyRotation(rotation, centroidS)
        let translation = WorldPoint3D(
            x: centroidT.x - scale * rotatedCentroid.x,
            y: centroidT.y - scale * rotatedCentroid.y,
            z: centroidT.z - scale * rotatedCentroid.z
        )

        let matrix: Matrix4x4F
        do {
            matrix = try Matrix4x4F(values: [
                Float(rotation[0][0]), Float(rotation[1][0]),
                Float(rotation[2][0]), 0,
                Float(rotation[0][1]), Float(rotation[1][1]),
                Float(rotation[2][1]), 0,
                Float(rotation[0][2]), Float(rotation[1][2]),
                Float(rotation[2][2]), 0,
                Float(translation.x), Float(translation.y),
                Float(translation.z), 1,
            ])
        } catch {
            throw CrossRevisionRegistrationError.transformNonRigid
        }

        var residuals: [CrossRevisionCorrespondenceResidual] = []
        var squaredSum = 0.0
        var maxResidual = 0.0
        for (i, pair) in correspondences.enumerated() {
            let mapped = Self.apply(
                rotation: rotation,
                scale: scale,
                translation: translation,
                to: source[i]
            )
            let residual = mapped.distance(to: target[i])
            residuals.append(
                CrossRevisionCorrespondenceResidual(
                    ref: pair.ref,
                    residualMeters: residual
                )
            )
            squaredSum += residual * residual
            maxResidual = max(maxResidual, residual)
        }
        let rms = (squaredSum / Double(correspondences.count))
            .squareRoot()

        return CrossRevisionRegistrationSolve(
            targetFromSource: matrix,
            uniformScale: scale,
            residuals: residuals,
            rmsMeters: rms,
            maxResidualMeters: maxResidual
        )
    }

    /// Whether the point set is coincident or collinear — checked on
    /// BOTH sides so a degenerate target set also fails closed.
    private static func isDegenerate(
        _ points: [WorldPoint3D]
    ) -> Bool {
        var farthest = (i: 0, j: 0, d2: 0.0)
        for i in points.indices {
            for j in points.indices where j > i {
                let d2 = points[i].distanceSquared(to: points[j])
                if d2 > farthest.d2 {
                    farthest = (i, j, d2)
                }
            }
        }
        let span = farthest.d2.squareRoot()
        guard span >= degenerateSpanMeters else {
            return true
        }
        let a = points[farthest.i]
        let b = points[farthest.j]
        let ab = Self.subtract(b, a)
        // Collinear when every point sits within a small fraction of
        // the span off the a–b line.
        let threshold = max(
            span * collinearityFraction,
            degenerateSpanMeters
        )
        for (index, point) in points.enumerated()
        where index != farthest.i && index != farthest.j {
            let ap = Self.subtract(point, a)
            let cross = Self.cross(ap, ab)
            let distanceOffLine = cross.magnitude / span
            if distanceOffLine > threshold {
                return false
            }
        }
        return true
    }

    private static func centroid(
        _ points: [WorldPoint3D]
    ) -> WorldPoint3D {
        var sum = WorldPoint3D.zero
        for point in points {
            sum = WorldPoint3D(
                x: sum.x + point.x,
                y: sum.y + point.y,
                z: sum.z + point.z
            )
        }
        let count = Double(points.count)
        return WorldPoint3D(
            x: sum.x / count,
            y: sum.y / count,
            z: sum.z / count
        )
    }

    private static func subtract(
        _ a: WorldPoint3D,
        _ b: WorldPoint3D
    ) -> WorldPoint3D {
        WorldPoint3D(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
    }

    private static func cross(
        _ a: WorldPoint3D,
        _ b: WorldPoint3D
    ) -> WorldPoint3D {
        WorldPoint3D(
            x: a.y * b.z - a.z * b.y,
            y: a.z * b.x - a.x * b.z,
            z: a.x * b.y - a.y * b.x
        )
    }

    /// Horn's closed-form rotation: maximizes `Σ (R p_i)·q_i` over
    /// unit quaternions — the largest-eigenvalue eigenvector of the
    /// 4×4 N matrix, found by cyclic Jacobi sweeps on a symmetric
    /// matrix (deterministic, dependency-free).
    private static func fitRotation(
        p: [WorldPoint3D],
        q: [WorldPoint3D]
    ) -> [[Double]] {
        var sxx = 0.0, sxy = 0.0, sxz = 0.0
        var syx = 0.0, syy = 0.0, syz = 0.0
        var szx = 0.0, szy = 0.0, szz = 0.0
        for i in p.indices {
            sxx += p[i].x * q[i].x
            sxy += p[i].x * q[i].y
            sxz += p[i].x * q[i].z
            syx += p[i].y * q[i].x
            syy += p[i].y * q[i].y
            syz += p[i].y * q[i].z
            szx += p[i].z * q[i].x
            szy += p[i].z * q[i].y
            szz += p[i].z * q[i].z
        }
        let n: [[Double]] = [
            [
                sxx + syy + szz,
                syz - szy,
                szx - sxz,
                sxy - syx,
            ],
            [
                syz - szy,
                sxx - syy - szz,
                sxy + syx,
                szx + sxz,
            ],
            [
                szx - sxz,
                sxy + syx,
                -sxx + syy - szz,
                syz + szy,
            ],
            [
                sxy - syx,
                szx + sxz,
                syz + szy,
                -sxx - syy + szz,
            ],
        ]
        let quaternion = Self.largestEigenvectorSymmetric4(n)
        let (w, x, y, z) = (
            quaternion[0], quaternion[1],
            quaternion[2], quaternion[3]
        )
        return [
            [
                1 - 2 * (y * y + z * z),
                2 * (x * y - w * z),
                2 * (x * z + w * y),
            ],
            [
                2 * (x * y + w * z),
                1 - 2 * (x * x + z * z),
                2 * (y * z - w * x),
            ],
            [
                2 * (x * z - w * y),
                2 * (y * z + w * x),
                1 - 2 * (x * x + y * y),
            ],
        ]
    }

    /// Largest-eigenvalue eigenvector of a symmetric 4×4 matrix via
    /// cyclic Jacobi rotations. ~12 sweeps converges far past Float
    /// precision for the benign spectra absolute-orientation N
    /// matrices produce.
    private static func largestEigenvectorSymmetric4(
        _ matrix: [[Double]]
    ) -> [Double] {
        var a = matrix
        var v: [[Double]] = [
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
            [0, 0, 0, 1],
        ]
        for _ in 0..<64 {
            var largest = (i: 0, j: 1, magnitude: abs(a[0][1]))
            for i in 0..<4 {
                for j in (i + 1)..<4 {
                    let magnitude = abs(a[i][j])
                    if magnitude > largest.magnitude {
                        largest = (i, j, magnitude)
                    }
                }
            }
            if largest.magnitude < 1e-12 {
                break
            }
            let i = largest.i
            let j = largest.j
            let theta = 0.5 * atan2(
                2 * a[i][j],
                a[j][j] - a[i][i]
            )
            let c = cos(theta)
            let s = sin(theta)
            for k in 0..<4 {
                let aik = a[i][k]
                let ajk = a[j][k]
                a[i][k] = c * aik - s * ajk
                a[j][k] = s * aik + c * ajk
            }
            for k in 0..<4 {
                let aki = a[k][i]
                let akj = a[k][j]
                a[k][i] = c * aki - s * akj
                a[k][j] = s * aki + c * akj
            }
            for k in 0..<4 {
                let vki = v[k][i]
                let vkj = v[k][j]
                v[k][i] = c * vki - s * vkj
                v[k][j] = s * vki + c * vkj
            }
        }
        var best = 0
        for index in 1..<4 where a[index][index] > a[best][best] {
            best = index
        }
        var vector = [v[0][best], v[1][best], v[2][best], v[3][best]]
        let magnitude = (vector[0] * vector[0]
            + vector[1] * vector[1]
            + vector[2] * vector[2]
            + vector[3] * vector[3]).squareRoot()
        guard magnitude > 0 else {
            return [1, 0, 0, 0]
        }
        vector = vector.map { $0 / magnitude }
        if vector[0] < 0 {
            vector = vector.map { -$0 }
        }
        return vector
    }

    private static func applyRotation(
        _ rotation: [[Double]],
        _ point: WorldPoint3D
    ) -> WorldPoint3D {
        WorldPoint3D(
            x: rotation[0][0] * point.x + rotation[0][1] * point.y
                + rotation[0][2] * point.z,
            y: rotation[1][0] * point.x + rotation[1][1] * point.y
                + rotation[1][2] * point.z,
            z: rotation[2][0] * point.x + rotation[2][1] * point.y
                + rotation[2][2] * point.z
        )
    }

    private static func apply(
        rotation: [[Double]],
        scale: Double,
        translation: WorldPoint3D,
        to point: WorldPoint3D
    ) -> WorldPoint3D {
        let scaled = WorldPoint3D(
            x: point.x * scale,
            y: point.y * scale,
            z: point.z * scale
        )
        let rotated = applyRotation(rotation, scaled)
        return WorldPoint3D(
            x: rotated.x + translation.x,
            y: rotated.y + translation.y,
            z: rotated.z + translation.z
        )
    }
}

private extension WorldPoint3D {
    var magnitude: Double {
        (x * x + y * y + z * z).squareRoot()
    }
}

/// An accepted cross-revision registration — the explicit, inspectable
/// transform authority between two independent finalized capture
/// coordinate spaces (issue #395). Immutable once accepted: the store
/// appends only, and a second registration for the same directed pair
/// is refused. It never rewrites either revision's bytes — both stay
/// immutable; the transform is supplemental authority carried beside
/// them.
public struct CrossRevisionRegistration:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    public let registrationID: CrossRevisionRegistrationID
    /// The revision whose coordinate space points are mapped FROM.
    public let sourceRevisionID: CaptureRevisionID
    public let sourceCoordinateSpaceID: CoordinateSpaceID
    /// The revision whose coordinate space points are mapped TO.
    public let targetRevisionID: CaptureRevisionID
    public let targetCoordinateSpaceID: CoordinateSpaceID
    /// How the correspondences were physically established.
    public let mechanism: CrossRevisionCorrespondenceKind
    public let correspondences: [CrossRevisionCorrespondence]
    /// Per-correspondence post-fit residuals — inspectable forever.
    public let residuals: [CrossRevisionCorrespondenceResidual]
    public let rmsMeters: Double
    public let maxResidualMeters: Double
    public let scalePolicy: CrossRevisionScalePolicy
    /// The fitted uniform scale (1.0 under `rigid_only`).
    public let uniformScale: Double
    /// The rigid part of `T_target_from_source`.
    public let targetFromSource: Matrix4x4F
    public let acceptedAtUTC: String
    /// Operator provenance note, when provided.
    public let note: String?
    /// Evidence refs (e.g. `path:session/room-field-datum.json`,
    /// `path:evidence/reference-targets.json`) the registration was
    /// established from.
    public let evidenceRefs: [String]

    public init(
        registrationID: CrossRevisionRegistrationID =
            CrossRevisionRegistrationID(),
        sourceRevisionID: CaptureRevisionID,
        sourceCoordinateSpaceID: CoordinateSpaceID,
        targetRevisionID: CaptureRevisionID,
        targetCoordinateSpaceID: CoordinateSpaceID,
        mechanism: CrossRevisionCorrespondenceKind,
        correspondences: [CrossRevisionCorrespondence],
        residuals: [CrossRevisionCorrespondenceResidual],
        rmsMeters: Double,
        maxResidualMeters: Double,
        scalePolicy: CrossRevisionScalePolicy,
        uniformScale: Double,
        targetFromSource: Matrix4x4F,
        acceptedAtUTC: String,
        note: String? = nil,
        evidenceRefs: [String] = []
    ) throws {
        guard sourceRevisionID != targetRevisionID else {
            throw CrossRevisionRegistrationError
                .mismatchedCorrespondenceIdentity
        }
        for value in [rmsMeters, maxResidualMeters] {
            guard value.isFinite, value >= 0 else {
                throw CrossRevisionRegistrationError
                    .invalidResidualValue
            }
        }
        guard uniformScale.isFinite, uniformScale > 0 else {
            throw CrossRevisionRegistrationError.scaleNotPermitted
        }
        if scalePolicy == .rigidOnly {
            guard uniformScale == 1 else {
                throw CrossRevisionRegistrationError.scaleNotPermitted
            }
        }
        guard correspondences.allSatisfy({ $0.kind == mechanism })
        else {
            throw CrossRevisionRegistrationError
                .mixedCorrespondenceKinds
        }
        guard Set(residuals.map(\.ref))
                == Set(correspondences.map(\.ref))
        else {
            throw CrossRevisionRegistrationError
                .mismatchedCorrespondenceIdentity
        }
        guard acceptedAtUTC.hasSuffix("Z") else {
            throw CrossRevisionRegistrationError.invalidTimestamp
        }
        self.registrationID = registrationID
        self.sourceRevisionID = sourceRevisionID
        self.sourceCoordinateSpaceID = sourceCoordinateSpaceID
        self.targetRevisionID = targetRevisionID
        self.targetCoordinateSpaceID = targetCoordinateSpaceID
        self.mechanism = mechanism
        self.correspondences = correspondences
        self.residuals = residuals
        self.rmsMeters = rmsMeters
        self.maxResidualMeters = maxResidualMeters
        self.scalePolicy = scalePolicy
        self.uniformScale = uniformScale
        self.targetFromSource = targetFromSource
        self.acceptedAtUTC = acceptedAtUTC
        self.note = note
        self.evidenceRefs = evidenceRefs
    }

    public var id: CrossRevisionRegistrationID { registrationID }

    /// Worst observed fit residual — the edge uncertainty the
    /// registration graph accumulates.
    public var uncertaintyMeters: Double {
        maxResidualMeters
    }

    /// Applies the fitted transform to a source-space point:
    /// `p' = R·(s·p) + t`.
    public func applying(to point: WorldPoint3D) -> WorldPoint3D {
        let scaled = Float3(
            Float(point.x * uniformScale),
            Float(point.y * uniformScale),
            Float(point.z * uniformScale)
        )
        let mapped = targetFromSource.applying(to: scaled)
        return WorldPoint3D(
            x: Double(mapped.x),
            y: Double(mapped.y),
            z: Double(mapped.z)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case registrationID = "registration_id"
        case sourceRevisionID = "source_revision_id"
        case sourceCoordinateSpaceID = "source_coordinate_space_id"
        case targetRevisionID = "target_revision_id"
        case targetCoordinateSpaceID = "target_coordinate_space_id"
        case mechanism
        case correspondences
        case residuals
        case rmsMeters = "rms_m"
        case maxResidualMeters = "max_residual_m"
        case scalePolicy = "scale_policy"
        case uniformScale = "uniform_scale"
        case targetFromSource = "T_target_from_source"
        case acceptedAtUTC = "accepted_at"
        case note
        case evidenceRefs = "evidence_refs"
    }
}

/// Versioned app-local registry document —
/// `<captureRoot>/spatial-registrations.json`. Deliberately outside
/// `finalized/`, `exports/`, and `working/` like the other app-local
/// stores: accepted registrations are supplemental authority layered
/// beside the immutable bundles, never inside them.
public struct CrossRevisionRegistrationRegistryDocument:
    Codable,
    Sendable,
    Equatable
{
    public static let schema = "htdt.cross-revision-registry"
    public static let schemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public var registrations: [CrossRevisionRegistration]

    public init(
        registrations: [CrossRevisionRegistration] = []
    ) {
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.registrations = registrations
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case registrations
    }
}

/// The app-local registration authority (issue #395). `propose` runs
/// the solver and returns the inspectable fit without persisting;
/// `accept` commits it immutably. Acceptance is the only write —
/// nothing updates or deletes a registration.
public struct CrossRevisionRegistrationStore: Sendable {
    public let fileURL: URL

    public init(captureRoot: URL) {
        self.fileURL = captureRoot.appendingPathComponent(
            "spatial-registrations.json",
            isDirectory: false
        )
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws
        -> CrossRevisionRegistrationRegistryDocument
    {
        guard FileManager.default.fileExists(atPath: fileURL.path)
        else {
            return CrossRevisionRegistrationRegistryDocument()
        }
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(
                CrossRevisionRegistrationRegistryDocument.self,
                from: data
              )
        else {
            throw CrossRevisionRegistrationError.unreadableDocument
        }
        guard document.schema
                == CrossRevisionRegistrationRegistryDocument.schema,
              document.schemaVersion
                == CrossRevisionRegistrationRegistryDocument
                    .schemaVersion
        else {
            throw CrossRevisionRegistrationError.schemaMismatch
        }
        return document
    }

    /// Accepted registrations involving `revisionID` on either side.
    public func registrations(
        involving revisionID: CaptureRevisionID
    ) throws -> [CrossRevisionRegistration] {
        try load().registrations.filter {
            $0.sourceRevisionID == revisionID
                || $0.targetRevisionID == revisionID
        }
    }

    /// Computes the fit for inspection without persisting anything —
    /// the pre-acceptance preview the operator reviews (mechanism,
    /// per-correspondence residuals, RMS/max, fitted scale).
    public func propose(
        correspondences: [CrossRevisionCorrespondence],
        scalePolicy: CrossRevisionScalePolicy = .rigidOnly
    ) throws -> CrossRevisionRegistrationSolve {
        try CrossRevisionRegistrationSolver.solve(
            correspondences: correspondences,
            scalePolicy: scalePolicy
        )
    }

    /// Solves and commits a registration immutably. Refuses when an
    /// accepted registration already binds this directed pair —
    /// re-registration is a deliberate new authority and never a
    /// silent overwrite.
    @discardableResult
    public func accept(
        sourceRevisionID: CaptureRevisionID,
        sourceCoordinateSpaceID: CoordinateSpaceID,
        targetRevisionID: CaptureRevisionID,
        targetCoordinateSpaceID: CoordinateSpaceID,
        mechanism: CrossRevisionCorrespondenceKind,
        correspondences: [CrossRevisionCorrespondence],
        scalePolicy: CrossRevisionScalePolicy = .rigidOnly,
        note: String? = nil,
        evidenceRefs: [String] = [],
        acceptedAtUTC: String = BundleTimestamp.utcString(
            from: Date()
        )
    ) throws -> CrossRevisionRegistration {
        var document = try load()
        guard !document.registrations.contains(where: {
            $0.sourceRevisionID == sourceRevisionID
                && $0.targetRevisionID == targetRevisionID
        }) else {
            throw CrossRevisionRegistrationError
                .conflictingRegistration
        }
        let solve = try CrossRevisionRegistrationSolver.solve(
            correspondences: correspondences,
            scalePolicy: scalePolicy
        )
        guard let kind = correspondences.first?.kind,
              kind == mechanism
        else {
            throw CrossRevisionRegistrationError
                .mismatchedCorrespondenceIdentity
        }
        let registration = try CrossRevisionRegistration(
            sourceRevisionID: sourceRevisionID,
            sourceCoordinateSpaceID: sourceCoordinateSpaceID,
            targetRevisionID: targetRevisionID,
            targetCoordinateSpaceID: targetCoordinateSpaceID,
            mechanism: mechanism,
            correspondences: correspondences,
            residuals: solve.residuals,
            rmsMeters: solve.rmsMeters,
            maxResidualMeters: solve.maxResidualMeters,
            scalePolicy: scalePolicy,
            uniformScale: solve.uniformScale,
            targetFromSource: solve.targetFromSource,
            acceptedAtUTC: acceptedAtUTC,
            note: note,
            evidenceRefs: evidenceRefs
        )
        document.registrations.append(registration)
        try save(document)
        return registration
    }

    private func save(
        _ document: CrossRevisionRegistrationRegistryDocument
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
            .prettyPrinted,
        ]
        let data = try encoder.encode(document)
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        let temporary = parent.appendingPathComponent(
            ".tmp-\(UUID().uuidString)"
        )
        do {
            try data.write(to: temporary, options: .atomic)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(
                    fileURL,
                    withItemAt: temporary
                )
            } else {
                try FileManager.default.moveItem(
                    at: temporary,
                    to: fileURL
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}

/// Canonical supplemental-authority payload listing the accepted
/// registrations that bind a revision (issue #395), committed at
/// `revision/registrations.json` inside a revision's bundle. The
/// payload is additive authority: it never rewrites coordinate truth
/// inside the revision it travels with, and HTDT consumes it as an
/// explicit transform declaration rather than inferring one.
public struct CrossRevisionRegistrationBundleDocument:
    Codable,
    Sendable,
    Equatable
{
    public static let schema =
        "htdt.capture.cross-revision-registration"
    public static let schemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    /// The revision this bundle document belongs to. Every listed
    /// registration must name it as source or target.
    public let captureRevisionID: CaptureRevisionID
    public let registrations: [CrossRevisionRegistration]

    public init(
        captureRevisionID: CaptureRevisionID,
        registrations: [CrossRevisionRegistration]
    ) throws {
        guard registrations.allSatisfy({
            $0.sourceRevisionID == captureRevisionID
                || $0.targetRevisionID == captureRevisionID
        }) else {
            throw CrossRevisionRegistrationError
                .mismatchedCorrespondenceIdentity
        }
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.registrations = registrations
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case registrations
    }
}

/// Canonical payload + declaration for committing the registration
/// document into a working set as a supplemental authority payload.
public struct CrossRevisionRegistrationPackage: Sendable, Equatable {
    public static let path = "revision/registrations.json"

    public let document: CrossRevisionRegistrationBundleDocument
    public let data: Data

    public init(
        document: CrossRevisionRegistrationBundleDocument,
        data: Data
    ) {
        self.document = document
        self.data = data
    }

    /// Supplemental authority: computed from finalized
    /// revision evidence, recorded by the capture app, never part of
    /// either endpoint's canonical truth. The v1 `source_refs`
    /// grammar cannot reference a revision outside this bundle, so
    /// the endpoint revision IDs live only in the document body.
    public var payloadDeclaration: BundlePayloadDeclaration {
        BundlePayloadDeclaration(
            path: Self.path,
            mediaType: "application/json",
            producer: "capture_app_derived",
            provenanceClass: .captureAppDerived,
            role: .canonical
        )
    }
}

public enum CrossRevisionRegistrationPackageBuilder {
    /// Encodes a bundle document deterministically and verifies the
    /// round-trip — the same convention every canonical payload
    /// builder follows.
    public static func build(
        document: CrossRevisionRegistrationBundleDocument
    ) throws -> CrossRevisionRegistrationPackage {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        let data = try encoder.encode(document)
        guard let decoded = try? JSONDecoder().decode(
            CrossRevisionRegistrationBundleDocument.self,
            from: data
        ), decoded == document else {
            throw CrossRevisionRegistrationError
                .encodedDocumentMismatch
        }
        return CrossRevisionRegistrationPackage(
            document: document,
            data: data
        )
    }
}

/// How a path between two capture coordinate spaces resolves through
/// the accepted-registration graph (issue #395). A direct edge carries
/// its own uncertainty; a chained path composes transforms and
/// accumulates uncertainty in quadrature — the graph never pretends a
/// multi-hop alignment is as confident as a direct one.
public enum CrossRevisionTransformPath:
    Sendable,
    Equatable
{
    /// No accepted path connects the two spaces.
    case unresolved
    /// The spaces are the same (identity); no transform needed.
    case identity
    /// One accepted registration maps source → target directly.
    case direct(CrossRevisionRegistration)
    /// A multi-hop path: the ordered edge list (each applied forward
    /// or inverse), the composed transform, and accumulated
    /// uncertainty `sqrt(Σ uᵢ²)` in meters.
    case chained(
        registrations: [CrossRevisionRegistration],
        targetFromSource: CrossRevisionScaledTransform,
        accumulatedUncertaintyMeters: Double
    )
}

/// A rigid transform plus its separately-carried uniform scale
/// (`p' = R·(s·p) + t`); the composed/identity/inverse arithmetic for
/// registration-graph path resolution.
public struct CrossRevisionScaledTransform:
    Codable,
    Sendable,
    Equatable
{
    public let rigid: Matrix4x4F
    public let uniformScale: Double

    public init(rigid: Matrix4x4F, uniformScale: Double) throws {
        guard uniformScale.isFinite, uniformScale > 0 else {
            throw CrossRevisionRegistrationError.scaleNotPermitted
        }
        self.rigid = rigid
        self.uniformScale = uniformScale
    }

    public static var identity: CrossRevisionScaledTransform {
        try! CrossRevisionScaledTransform(
            rigid: .identity,
            uniformScale: 1
        )
    }

    /// `p' = R·(s·p) + t`.
    public func applying(to point: WorldPoint3D) -> WorldPoint3D {
        let scaled = Float3(
            Float(point.x * uniformScale),
            Float(point.y * uniformScale),
            Float(point.z * uniformScale)
        )
        let mapped = rigid.applying(to: scaled)
        return WorldPoint3D(
            x: Double(mapped.x),
            y: Double(mapped.y),
            z: Double(mapped.z)
        )
    }

    /// `other ∘ self`: applies `self` first, then `other`.
    public func concatenated(
        then other: CrossRevisionScaledTransform
    ) throws -> CrossRevisionScaledTransform {
        // R' = R2·R1; t' = R2·(s2·t1) + t2; s' = s1·s2.
        // Element (row, col) of the column-major Matrix4x4F basis is
        // values[row + 4·col].
        let r1 = rigid
        let r2 = other.rigid
        var columns = [Float](repeating: 0, count: 9)
        for column in 0..<3 {
            for row in 0..<3 {
                var sum: Float = 0
                for k in 0..<3 {
                    sum += r2.values[row + 4 * k]
                        * r1.values[k + 4 * column]
                }
                columns[column * 3 + row] = sum
            }
        }
        let s2 = Float(other.uniformScale)
        let t1 = Float3(
            r1.values[12], r1.values[13], r1.values[14]
        )
        let scaledT1 = t1 * s2
        // Rotation only — applying(to:) would add r2's translation,
        // which is folded in separately below.
        let rotatedT1 = r2.applying(toDirection: scaledT1)
        let t2 = r2.values
        // `s1·s2` and the rotated translation can overflow to non-
        // finite values on extreme decoded scales — propagate the
        // validation failure instead of trapping.
        let transform = try Matrix4x4F(values: [
            columns[0], columns[1], columns[2], 0,
            columns[3], columns[4], columns[5], 0,
            columns[6], columns[7], columns[8], 0,
            rotatedT1.x + t2[12], rotatedT1.y + t2[13],
            rotatedT1.z + t2[14], 1,
        ])
        return try CrossRevisionScaledTransform(
            rigid: transform,
            uniformScale: uniformScale * other.uniformScale
        )
    }

    /// The inverse map: `p = Rᵀ·((1/s)·p') − Rᵀ·(t/s)` — rotation
    /// transposed, scale reciprocated, translation `−Rᵀ·t/s`.
    public func inverted() throws -> CrossRevisionScaledTransform {
        let t = rigid.translationWorld
        let invScale = Float(1 / uniformScale)
        let negT = Float3(
            -t.x * invScale,
            -t.y * invScale,
            -t.z * invScale
        )
        // Rᵀ·(−t/s): row i of R dots the vector.
        let rotated = Float3(
            rigid.values[0] * negT.x + rigid.values[4] * negT.y
                + rigid.values[8] * negT.z,
            rigid.values[1] * negT.x + rigid.values[5] * negT.y
                + rigid.values[9] * negT.z,
            rigid.values[2] * negT.x + rigid.values[6] * negT.y
                + rigid.values[10] * negT.z
        )
        // Rᵀ's columns are R's rows. `1/s` and `Rᵀ·(−t/s)` overflow
        // on extreme decoded scales — propagate instead of trapping.
        let transform = try Matrix4x4F(values: [
            rigid.values[0], rigid.values[4], rigid.values[8], 0,
            rigid.values[1], rigid.values[5], rigid.values[9], 0,
            rigid.values[2], rigid.values[6], rigid.values[10], 0,
            rotated.x, rotated.y, rotated.z, 1,
        ])
        return try CrossRevisionScaledTransform(
            rigid: transform,
            uniformScale: 1 / uniformScale
        )
    }
}

/// The accepted-registration graph across revisions (issue #395):
/// directed edges source → target, traversable in either direction
/// (inverse applied with `1/s` and the rigid inverse). Path
/// resolution is deterministic — BFS by hop count with ties broken
/// by acceptance order — and reports direct vs chained so callers
/// can present accumulated uncertainty honestly.
public struct CrossRevisionRegistrationGraph: Sendable, Equatable {
    public let registrations: [CrossRevisionRegistration]

    public init(registrations: [CrossRevisionRegistration]) {
        self.registrations = registrations
    }

    /// Resolves the transform between two revisions' coordinate
    /// spaces through accepted registrations only.
    public func resolve(
        from sourceRevisionID: CaptureRevisionID,
        to targetRevisionID: CaptureRevisionID
    ) -> CrossRevisionTransformPath {
        if sourceRevisionID == targetRevisionID {
            return .identity
        }
        if let edge = registrations.first(where: {
            $0.sourceRevisionID == sourceRevisionID
                && $0.targetRevisionID == targetRevisionID
        }) {
            return .direct(edge)
        }

        // BFS over revisions; edges traverse forward (as stored) or
        // backward (inverted).
        struct Hop {
            let revisionID: CaptureRevisionID
            let transform: CrossRevisionScaledTransform
            let uncertaintySquared: Double
            let path: [CrossRevisionRegistration]
        }
        var visited: Set<CaptureRevisionID> = [sourceRevisionID]
        var queue: [Hop] = [
            Hop(
                revisionID: sourceRevisionID,
                transform: .identity,
                uncertaintySquared: 0,
                path: []
            )
        ]
        var best: Hop?
        var bestHopCount = Int.max
        while !queue.isEmpty {
            let hop = queue.removeFirst()
            if hop.path.count >= bestHopCount {
                continue
            }
            for edge in registrations {
                let forward =
                    edge.sourceRevisionID == hop.revisionID
                let backward =
                    edge.targetRevisionID == hop.revisionID
                guard forward || backward else {
                    continue
                }
                let next =
                    forward ? edge.targetRevisionID
                        : edge.sourceRevisionID
                guard !visited.contains(next) else {
                    continue
                }
                // An edge whose stored scale cannot be inverted or
                // composed without overflow is unusable as evidence —
                // skip it rather than trapping.
                let edgeTransform = try? forward
                    ? CrossRevisionScaledTransform(
                        rigid: edge.targetFromSource,
                        uniformScale: edge.uniformScale
                    )
                    : (try CrossRevisionScaledTransform(
                        rigid: edge.targetFromSource,
                        uniformScale: edge.uniformScale
                    )).inverted()
                guard let edgeTransform,
                      let combined = try? hop.transform.concatenated(
                          then: edgeTransform
                      )
                else {
                    continue
                }
                let uncertaintySquared = hop.uncertaintySquared
                    + edge.uncertaintyMeters * edge.uncertaintyMeters
                var path = hop.path
                path.append(edge)
                let nextHop = Hop(
                    revisionID: next,
                    transform: combined,
                    uncertaintySquared: uncertaintySquared,
                    path: path
                )
                if next == targetRevisionID {
                    if path.count < bestHopCount {
                        best = nextHop
                        bestHopCount = path.count
                    }
                    continue
                }
                visited.insert(next)
                queue.append(nextHop)
            }
        }
        guard let best else {
            return .unresolved
        }
        return .chained(
            registrations: best.path,
            targetFromSource: best.transform,
            accumulatedUncertaintyMeters:
                best.uncertaintySquared.squareRoot()
        )
    }
}

/// Gather helpers that build attested correspondence pairs from
/// bundle evidence (issue #395). Every helper pairs positions whose
/// physical referent is the same on both sides — a mismatched or
/// un-attested pairing is never emitted.
public enum CrossRevisionCorrespondenceGather {
    /// Builds the correspondence set for a `shared_field_datum`
    /// registration: each revision declared the same physical install
    /// datum, so the datum's origin and unit axis endpoints map
    /// field-space-identical points across the two capture spaces.
    /// Datum axes are orthonormal by construction, so the four
    /// generated points are non-collinear and feed the same
    /// least-squares solve as measured correspondence sets —
    /// residual transparency is preserved.
    public static func fromSharedFieldDatums(
        source: RoomFieldDatumDocument,
        target: RoomFieldDatumDocument
    ) throws -> [CrossRevisionCorrespondence] {
        func point(
            _ transform: RoomFieldDatumTransform,
            _ field: WorldPoint3D
        ) -> WorldPoint3D {
            WorldPoint3D(
                x: transform.originMeters.x
                    + field.x * transform.xAxis.x
                    + field.y * transform.yAxis.x
                    + field.z * transform.zAxis.x,
                y: transform.originMeters.y
                    + field.x * transform.xAxis.y
                    + field.y * transform.yAxis.y
                    + field.z * transform.zAxis.y,
                z: transform.originMeters.z
                    + field.x * transform.xAxis.z
                    + field.y * transform.yAxis.z
                    + field.z * transform.zAxis.z
            )
        }
        let elements: [(String, WorldPoint3D)] = [
            ("origin", .zero),
            ("x_axis", WorldPoint3D(x: 1, y: 0, z: 0)),
            ("y_axis", WorldPoint3D(x: 0, y: 1, z: 0)),
            ("z_axis", WorldPoint3D(x: 0, y: 0, z: 1)),
        ]
        return try elements.map { name, fieldPoint in
            try CrossRevisionCorrespondence(
                kind: .sharedFieldDatum,
                ref: "field_datum:\(name)",
                sourcePosition: point(
                    source.fieldFromCaptureWorld,
                    fieldPoint
                ),
                targetPosition: point(
                    target.fieldFromCaptureWorld,
                    fieldPoint
                )
            )
        }
    }

    /// Builds the correspondence set for a `reference_target`
    /// registration: targets declared in both revisions and observed
    /// (positionWorld present) under the same `target_id` on both
    /// sides — the exact-identity attestation the issue requires.
    /// Every target contributes its observed center. Fewer than three
    /// shared targets yield `.insufficientCorrespondences` via the
    /// solver; a target observed on only one side contributes nothing.
    public static func fromReferenceTargets(
        sourceObservations: [ReferenceTargetObservation],
        targetObservations: [ReferenceTargetObservation]
    ) throws -> [CrossRevisionCorrespondence] {
        func latestPositions(
            _ observations: [ReferenceTargetObservation]
        ) -> [ReferenceTargetID: WorldPoint3D] {
            var positions:
                [ReferenceTargetID: WorldPoint3D] = [:]
            for observation in observations.sorted(by: {
                $0.observationIndex < $1.observationIndex
            }) {
                guard let position = observation.positionWorld
                else {
                    continue
                }
                positions[observation.targetID] = WorldPoint3D(
                    x: Double(position.x),
                    y: Double(position.y),
                    z: Double(position.z)
                )
            }
            return positions
        }
        let sourcePositions = latestPositions(sourceObservations)
        let targetPositions = latestPositions(targetObservations)
        let sharedIDs = Set(sourcePositions.keys)
            .intersection(Set(targetPositions.keys))
        return try sharedIDs.sorted(by: {
            $0.description < $1.description
        }).map { targetID in
            try CrossRevisionCorrespondence(
                kind: .referenceTarget,
                ref: "reference_target:\(targetID.description)",
                sourcePosition: sourcePositions[targetID]!,
                targetPosition: targetPositions[targetID]!
            )
        }
    }
}
