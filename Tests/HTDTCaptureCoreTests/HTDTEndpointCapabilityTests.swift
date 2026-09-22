import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue #374: endpoint capability handshake — document decoding and
/// the pure compatibility classifier's hard-gap vs omission split.
final class HTDTEndpointCapabilityTests: XCTestCase {
    private func makeCapabilities(
        protocols: [String] = ["1"],
        bundleVersions: [String] = ["1.0.0"],
        payloadSchemas: [HTDTAcceptedPayloadSchema] = [],
        authorityFamilies: [String] = [],
        maxArchiveBytes: Int64? = nil,
        missionReceipts: Bool = true,
        catalogKeys: [String] = [],
        projectRef: String? = nil,
        manualReview: Bool = false
    ) -> HTDTEndpointCapabilityDocument {
        HTDTEndpointCapabilityDocument(
            endpointIdentity: "receiver-01",
            handoffProtocolVersions: protocols,
            acceptedBundleSchemaVersions: bundleVersions,
            acceptedPayloadSchemas: payloadSchemas,
            supportedAuthorityFamilies: authorityFamilies,
            maxArchiveBytes: maxArchiveBytes,
            missionReceiptsSupported: missionReceipts,
            equipmentCatalogsRecognized: catalogKeys,
            projectRef: projectRef,
            manualReviewRequired: manualReview
        )
    }

    private func makeInventory(
        bundleVersion: String = "1.0.0",
        payloadSchemas: [String] = [],
        authorityFamilies: [String] = [],
        catalogKeys: [String] = [],
        archiveBytes: Int64 = 1024,
        projectRef: String? = nil
    ) -> HTDTBundleInventory {
        HTDTBundleInventory(
            bundleSchemaVersion: bundleVersion,
            payloadSchemaNames: payloadSchemas,
            authorityFamilies: authorityFamilies,
            equipmentCatalogKeys: catalogKeys,
            archiveByteCount: archiveBytes,
            projectRef: projectRef
        )
    }

    func testDocumentRoundTrips() throws {
        let doc = makeCapabilities(
            payloadSchemas: [
                HTDTAcceptedPayloadSchema(
                    schema: "htdt.capture.authorities",
                    versions: ["1.0.0"]
                )
            ],
            maxArchiveBytes: 4096,
            projectRef: "proj-77"
        )
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(
            HTDTEndpointCapabilityDocument.self,
            from: data
        )
        XCTAssertEqual(decoded, doc)
        XCTAssertEqual(decoded.schema, "htdt.endpoint-capabilities")
        XCTAssertEqual(decoded.schemaVersion, "1.0.0")
    }

    func testCompatibleBundlePasses() {
        let verdict = HTDTCompatibilityChecker.check(
            inventory: makeInventory(
                payloadSchemas: ["a.schema"],
                authorityFamilies: ["speaker_layout"],
                catalogKeys: ["cat-1"],
                projectRef: "proj-77"
            ),
            capabilities: makeCapabilities(
                payloadSchemas: [
                    HTDTAcceptedPayloadSchema(
                        schema: "a.schema",
                        versions: ["1"]
                    )
                ],
                authorityFamilies: ["speaker_layout"],
                catalogKeys: ["cat-1"],
                projectRef: "proj-77"
            )
        )
        guard case .compatible = verdict else {
            XCTFail("expected compatible, got \(verdict)")
            return
        }
        XCTAssertTrue(verdict.sendPermitted)
    }

    func testOmissionsListPrecisely() {
        let verdict = HTDTCompatibilityChecker.check(
            inventory: makeInventory(
                payloadSchemas: ["a.schema", "b.schema"],
                authorityFamilies: ["speaker_layout", "acoustics"],
                catalogKeys: ["cat-x"]
            ),
            capabilities: makeCapabilities(
                payloadSchemas: [
                    HTDTAcceptedPayloadSchema(
                        schema: "a.schema",
                        versions: ["1"]
                    )
                ],
                authorityFamilies: ["speaker_layout"]
            )
        )
        guard case .compatibleWithOmissions(let gaps) = verdict else {
            XCTFail("expected omissions, got \(verdict)")
            return
        }
        let kinds = Set(gaps.map(\.kind))
        XCTAssertEqual(
            kinds,
            [
                .unsupportedPayloadSchema,
                .unsupportedAuthorityFamily,
                .unrecognizedEquipmentCatalog
            ]
        )
        XCTAssertTrue(verdict.sendPermitted)
        XCTAssertEqual(
            Set(gaps.map(\.subject)),
            ["b.schema", "acoustics", "cat-x"]
        )
    }

    func testHardGapsBlockSend() {
        let verdict = HTDTCompatibilityChecker.check(
            inventory: makeInventory(
                bundleVersion: "9.9.9",
                archiveBytes: 10_000_000
            ),
            capabilities: makeCapabilities(
                protocols: ["2"],
                bundleVersions: ["1.0.0"],
                maxArchiveBytes: 1_000_000,
                missionReceipts: false
            ),
            requiresMissionReceipts: true
        )
        guard case .incompatible(let gaps) = verdict else {
            XCTFail("expected incompatible, got \(verdict)")
            return
        }
        XCTAssertFalse(verdict.sendPermitted)
        let kinds = Set(gaps.map(\.kind))
        XCTAssertTrue(
            kinds.contains(.unsupportedBundleVersion)
        )
        XCTAssertTrue(
            kinds.contains(.unsupportedHandoffProtocol)
        )
        XCTAssertTrue(kinds.contains(.archiveTooLarge))
        XCTAssertTrue(
            kinds.contains(.missionReceiptsUnsupported)
        )
    }

    func testProjectRefMismatchIsOmissionAtBundleLevel() {
        // A receiver bound to another project still stages the bytes;
        // the mismatch is reported precisely but is not a hard
        // refusal — hard project enforcement lives at the mission
        // requirement level.
        let verdict = HTDTCompatibilityChecker.check(
            inventory: makeInventory(projectRef: "proj-A"),
            capabilities: makeCapabilities(projectRef: "proj-B")
        )
        guard case .compatibleWithOmissions(let gaps) = verdict else {
            XCTFail("expected omissions, got \(verdict)")
            return
        }
        XCTAssertEqual(
            gaps.map(\.kind),
            [.projectRefMismatch]
        )
    }

    func testMissionRequirementCheck() {
        let requirement = HTDTMissionReceiverRequirement(
            destinationProjectRef: "proj-77",
            minHandoffProtocol: "1",
            requiredAuthorityFamilies: ["speaker_layout"],
            requiredPayloadSchemas: ["a.schema"],
            requireMissionReceipts: true
        )
        let satisfied = HTDTCompatibilityChecker.checkMissionRequirement(
            requirement,
            capabilities: makeCapabilities(
                payloadSchemas: [
                    HTDTAcceptedPayloadSchema(
                        schema: "a.schema",
                        versions: ["1"]
                    )
                ],
                authorityFamilies: ["speaker_layout"],
                missionReceipts: true,
                projectRef: "proj-77"
            )
        )
        XCTAssertTrue(satisfied.sendPermitted)

        let failing = HTDTCompatibilityChecker.checkMissionRequirement(
            requirement,
            capabilities: makeCapabilities(
                missionReceipts: false,
                projectRef: "other"
            )
        )
        guard case .incompatible(let gaps) = failing else {
            XCTFail("expected incompatible, got \(failing)")
            return
        }
        let kinds = Set(gaps.map(\.kind))
        XCTAssertTrue(
            kinds.contains(.missionReceiptsUnsupported)
        )
        XCTAssertTrue(kinds.contains(.projectRefMismatch))
        XCTAssertTrue(
            kinds.contains(.unsupportedAuthorityFamily)
        )
        XCTAssertTrue(
            kinds.contains(.unsupportedPayloadSchema)
        )
    }

    func testAuthorityFamiliesInventory() {
        // The inventory maps populated authority sections to their
        // SemanticTaskKind family tokens; an empty collection maps
        // to no families.
        let collection = TheaterAuthorityCollection.empty
        XCTAssertTrue(collection.presentAuthorityFamilies().isEmpty)
    }
}
