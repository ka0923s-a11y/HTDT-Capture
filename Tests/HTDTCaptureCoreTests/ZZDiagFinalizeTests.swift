import Foundation
import XCTest
@testable import HTDTCaptureCore

/// TEMPORARY diagnostic (not for commit): restores the app's copied
/// working set exactly like openRecoveredDraft, then runs the real
/// seal + BundleRevisionFinalizer path to print which manifest entry
/// the validator rejects during Validate and finalize.
final class ZZDiagFinalizeTests: XCTestCase {
    func testDiagnoseInvalidManifestEntry() async throws {
        let work = URL(fileURLWithPath: "/tmp/finalize-diag/work")
        let dst = URL(fileURLWithPath: "/tmp/finalize-diag/out/bundle")

        let draft = RecoverableWorkingRevision(
            url: work,
            revisionID: CaptureRevisionID(
                canonicalString: "f5e0e34b-b2cd-46ea-8b53-d3ebcdef1077")!,
            phase: .semanticAuthoring,
            captureSessionID: CaptureSessionID(
                canonicalString: "788e0b7d-0678-4be2-a904-a33bc4dc1f70"),
            coordinateSpaceID: CoordinateSpaceID(
                canonicalString: "6daa6fa7-91bc-4af6-a74f-fe528d16d98b"),
            retainedBytes: 0)

        let (store, report) = try await CaptureWorkingSetStore
            .restoreWorkingRevision(draft)
        print("DIAG restore unsupported=\(report.unsupportedPaths) superseded=\(report.supersededPaths) unmanifestable=\(report.unmanifestablePaths) missing=\(report.missingCheckpointFields)")

        let sealed: SealedWorkingSet
        do {
            sealed = try await store.sealForFinalization(
                requirements: CaptureQualityRequirements(
                    rulesetVersion: "1.2.0"))
        } catch {
            print("DIAG seal error: \(error)")
            throw error
        }
        print("DIAG sealed payloads=\(sealed.snapshot.payloadDeclarations.count)")
        for d in sealed.snapshot.payloadDeclarations {
            print("DIAG decl path=\(d.path) mt=\(d.mediaType) prod=\(d.producer) refs=\(d.sourceRefs ?? [])")
        }

        let req = try CaptureWorkingSetFinalizationRequestBuilder.build(
            sealed: sealed,
            app: BundleAppIdentity(version: "0.1.0", build: "1"))

        do {
            _ = try await BundleRevisionFinalizer().finalize(
                stagingDirectory: work,
                destinationDirectory: dst,
                request: req)
            print("DIAG finalizer succeeded")
        } catch let e as BundleDirectoryValidationError {
            print("DIAG VALIDATION ERROR: \(e)")
            // manifest.json was cleaned by the finalizer; rebuild the
            // entries and inspect each against validator rules.
            let limits = BundleFilesystemLimits()
            let staged = try BundleDirectoryScanner.scan(
                root: work, limits: limits)
            let decls = Dictionary(
                sealed.snapshot.payloadDeclarations.map {
                    ($0.path, $0)
                },
                uniquingKeysWith: { a, _ in a })
            var seen = Set<String>()
            for f in staged where f.path != "manifest.json" {
                guard let d = decls[f.path] else {
                    print("DIAG undeclared staged: \(f.path)")
                    continue
                }
                var bad: [String] = []
                do { try BundleLogicalPath.validate(f.path) } catch {
                    bad.append("path-invalid:\(error)")
                }
                if d.mediaType.isEmpty { bad.append("mt-empty") }
                if d.producer.isEmpty { bad.append("prod-empty") }
                if let refs = d.sourceRefs {
                    if refs.contains(where: { $0.isEmpty }) {
                        bad.append("empty-ref")
                    }
                    if Set(refs).count != refs.count {
                        bad.append("dup-ref:\(refs)")
                    }
                }
                if !seen.insert(f.path).inserted {
                    bad.append("dup-path")
                }
                if !bad.isEmpty {
                    print("DIAG BAD ENTRY \(f.path) -> \(bad)")
                }
            }
        } catch {
            print("DIAG finalizer other error: \(error)")
        }
    }
}
