import Foundation
import Testing
@testable import HTDTCaptureCore

// Contract coverage for the equipment-catalog epic:
//   #302 catalog snapshot identity + multi-catalog library
//   #315 versioned speaker-layout profile role binding
//   #337 portable external-authority dependency manifest
//   #345 label-scan suggestion provenance + matching

private func catalogEntry(
    id: String,
    version: String = "1.0.0",
    hash: String = "ab"
) throws -> HTDTEquipmentCatalogEntry {
    try HTDTEquipmentCatalogEntry(
        definitionID: id,
        version: version,
        semanticSHA256: EvidenceSHA256(
            String(repeating: hash, count: 32)
        ),
        identityKind: .manufacturer,
        manufacturer: "Example Audio",
        model: "Monitor X",
        userLabel: nil
    )
}

private func catalogSnapshot(
    entries: [HTDTEquipmentCatalogEntry],
    context: HTDTEquipmentCatalogContext? = nil
) throws -> HTDTEquipmentCatalogSnapshot {
    try HTDTEquipmentCatalogSnapshot(
        definitions: entries,
        catalogContext: context
    )
}

private func catalogContext() throws -> HTDTEquipmentCatalogContext {
    try HTDTEquipmentCatalogContext(
        catalogSnapshotID: "snap-42",
        catalogLabel: "HQ floor 3",
        catalogVersion: "2026.09",
        generatedAtUTC: "2026-09-20T00:00:00Z",
        sourceProjectRef: "project:hq",
        sourceInstanceRef: "instance:backend-1"
    )
}

private func speakerEntity(
    role: ChannelRole = .left,
    binding: SpeakerRoleBinding? = nil,
    equipmentRef: HTDTEquipmentReference? = nil,
    space: CoordinateSpaceID = CoordinateSpaceID()
) throws -> CaptureAnnotationEntity {
    try CaptureAnnotationEntity(
        type: .speaker,
        coordinateSpaceID: space,
        worldFromAnnotation: .identity,
        referencePointSemantics: .acousticCenter,
        label: "Speaker",
        placement: PlacementProvenance(method: .manualNumeric),
        orientation: try OrientationAxes(
            frontAxisLocal: SpatialVector3F(0, 0, -1),
            upAxisLocal: SpatialVector3F(0, 1, 0)
        ),
        channelRole: role,
        roleBinding: binding,
        equipmentRef: equipmentRef
    )
}

private func equipmentRef(
    id: String = "amp-1",
    version: String = "1.0.0"
) throws -> HTDTEquipmentReference {
    try HTDTEquipmentReference(
        equipmentID: id,
        equipmentVersion: version,
        equipmentHash: EvidenceSHA256(
            String(repeating: "cd", count: 32)
        ),
        authorityVersion:
            HTDTEquipmentCatalogSnapshot.expectedAuthorityVersion
    )
}

// MARK: - #302 catalog identity + library

@Test
func catalogIdentityDecodesSourceAndFreshness() throws {
    let context = try catalogContext()
    let snapshot = try catalogSnapshot(
        entries: [catalogEntry(id: "amp-1")],
        context: context
    )
    let identity = snapshot.identity
    #expect(!identity.isLegacy)
    #expect(identity.snapshotID == "snap-42")
    #expect(identity.label == "HQ floor 3")
    #expect(identity.catalogVersion == "2026.09")
    #expect(identity.generatedAtUTC == "2026-09-20T00:00:00Z")
    #expect(identity.sourceProjectRef == "project:hq")
    #expect(identity.sourceInstanceRef == "instance:backend-1")
    #expect(identity.definitionCount == 1)
    #expect(identity.stableKey == "snap-42")
}

@Test
func legacyCatalogSnapshotReadsAsUnknownLegacy() throws {
    let data = Data(
        """
        {
          "schema":"htdt.equipment.catalog-snapshot",
          "schema_version":1,
          "authority_version":"o100c-equipment-definition-1",
          "definitions":[]
        }
        """.utf8
    )
    let snapshot = try JSONDecoder().decode(
        HTDTEquipmentCatalogSnapshot.self,
        from: data
    )
    #expect(snapshot.identity.isLegacy)
    #expect(snapshot.identity.snapshotID == nil)
    #expect(
        snapshot.identity.stableKey
            == snapshot.contentSHA256.description
    )
}

@Test
func catalogContextRejectsMalformedGeneratedAt() throws {
    #expect(throws: HTDTEquipmentCatalogError.self) {
        _ = try HTDTEquipmentCatalogContext(
            catalogSnapshotID: "s1",
            catalogLabel: nil,
            catalogVersion: nil,
            generatedAtUTC: "not-a-timestamp",
            sourceProjectRef: nil,
            sourceInstanceRef: nil
        )
    }
}

@Test
func catalogContentHashIsSemanticAndOrderIndependent() throws {
    let a = try catalogEntry(id: "a", hash: "ab")
    let b = try catalogEntry(id: "b", hash: "cd")
    let first = try catalogSnapshot(entries: [a, b])
    let second = try catalogSnapshot(entries: [b, a])
    #expect(first.contentSHA256 == second.contentSHA256)

    let different = try catalogSnapshot(
        entries: [a, b, catalogEntry(id: "c", hash: "ef")]
    )
    #expect(first.contentSHA256 != different.contentSHA256)
}

@Test
func catalogRoundTripsContextThroughJSON() throws {
    let snapshot = try catalogSnapshot(
        entries: [catalogEntry(id: "amp-1")],
        context: catalogContext()
    )
    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(
        HTDTEquipmentCatalogSnapshot.self,
        from: data
    )
    #expect(decoded.catalogContext == snapshot.catalogContext)
    #expect(decoded.contentSHA256 == snapshot.contentSHA256)
}

@Test
func libraryStoresSwitchesAndMigratesCatalogs() throws {
    let root = try BundleValidationFixture.makeDirectory()
    defer { BundleValidationFixture.remove(root) }
    let legacy = root.appendingPathComponent("legacy.json")

    let library = HTDTEquipmentCatalogLibrary(
        directory: root.appendingPathComponent(
            "catalogs", isDirectory: true
        ),
        legacyFileURL: legacy
    )

    let snapshotA = try catalogSnapshot(
        entries: [catalogEntry(id: "a", hash: "ab")]
    )
    let snapshotB = try catalogSnapshot(
        entries: [catalogEntry(id: "b", hash: "cd")]
    )

    let dataA = try JSONEncoder().encode(snapshotA)
    let dataB = try JSONEncoder().encode(snapshotB)
    try library.store(dataA)
    try library.store(dataB)
    #expect(library.list().count == 2)
    // Two stored catalogs + no explicit choice → no active, never a
    // silent substitution.
    #expect(library.active() == nil)

    try library.setActive(
        contentKey: library.list()[0].contentKey
    )
    #expect(library.active() != nil)

    // Explicit second import activates deterministically.
    try library.storeAndActivate(dataB)
    #expect(
        library.active()?.snapshot.contentSHA256
            == snapshotB.contentSHA256
    )

    // Legacy single-slot cache migrates on first read and is
    // removed; identical bytes dedup to the existing stored copy and
    // become the active pointer.
    let legacyBytes = dataA
    try legacyBytes.write(to: legacy)
    _ = library.list()
    #expect(!FileManager.default.fileExists(atPath: legacy.path))
    #expect(library.list().count == 2)
    #expect(
        library.active()?.snapshot.contentSHA256
            == snapshotA.contentSHA256
    )

    // Unknown key never silently substitutes.
    #expect(throws: (any Error).self) {
        try library.setActive(contentKey: "nonexistent")
    }
}

@Test
func taskPlanCatalogPinIsCheckedDeterministically() throws {
    let pinned = try catalogSnapshot(
        entries: [catalogEntry(id: "amp-1")]
    )
    let other = try catalogSnapshot(
        entries: [catalogEntry(id: "amp-2", hash: "cd")]
    )
    let plan = try HTDTCaptureTaskPlan(
        planID: "plan-1",
        planVersion: "1.0.0",
        projectRef: "project:hq",
        roomName: "Lab",
        equipmentCatalog: pinned
    )

    #expect(
        EquipmentCatalogRequirement.check(
            plan: plan,
            activeCatalog: nil
        ) == .missingCatalog(
            pinnedSHA256: pinned.contentSHA256
        )
    )
    #expect(
        EquipmentCatalogRequirement.check(
            plan: plan,
            activeCatalog: pinned
        ).isSatisfied
    )
    #expect(
        EquipmentCatalogRequirement.check(
            plan: plan,
            activeCatalog: other
        ) == .mismatchedCatalog(
            pinnedSHA256: pinned.contentSHA256,
            activeSHA256: other.contentSHA256
        )
    )

    let unpinned = try HTDTCaptureTaskPlan(
        planID: "plan-2",
        planVersion: "1.0.0",
        projectRef: "project:hq",
        roomName: "Lab"
    )
    #expect(
        EquipmentCatalogRequirement.check(
            plan: unpinned,
            activeCatalog: nil
        ).isSatisfied
    )
}

// MARK: - #315 versioned layout profile role binding

@Test
func roleBindingRoundTripsOnEntityAndSchemaValidates() throws {
    let profile = SpeakerLayoutProfiles.surround7_1
    let binding = try SpeakerRoleBinding(
        profileID: profile.profileID,
        profileVersion: profile.profileVersion,
        roleID: "L"
    )
    let entity = try speakerEntity(binding: binding)
    #expect(entity.roleBinding == binding)

    let package = try AnnotationEvidencePackageBuilder.build(
        entities: [entity]
    )
    let root = try BundleValidationFixture.makeDirectory()
    defer { BundleValidationFixture.remove(root) }
    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                "annotations/entities.json",
                package.data,
                "application/json"
            ),
        ]
    )
    _ = try BundleDirectoryValidator.validate(root: root)

    let decoded = try JSONDecoder().decode(
        CaptureAnnotationCollection.self,
        from: package.data
    )
    #expect(decoded.entities.first?.roleBinding == binding)
}

@Test
func roleBindingRejectsNonSpeakerTypes() throws {
    let binding = try SpeakerRoleBinding(
        profileID: "htdt.generic-layout",
        profileVersion: "1.0.0",
        roleID: "L"
    )
    #expect(throws: AnnotationModelError.self) {
        _ = try CaptureAnnotationEntity(
            type: .referencePoint,
            coordinateSpaceID: CoordinateSpaceID(),
            worldFromAnnotation: .identity,
            referencePointSemantics: .userReferencePoint,
            label: "P",
            placement: PlacementProvenance(method: .manualNumeric),
            roleBinding: binding
        )
    }
}

@Test
func presetPlansCarryProfileIdentity() throws {
    for plan in SpeakerLayoutPresets.all {
        #expect(plan.profileIdentity != nil)
    }
    let plan = SpeakerLayoutProfiles.surround5_1.makePlan(
        name: "5.1"
    )
    #expect(
        plan.profileIdentity
            == SpeakerLayoutProfiles.surround5_1.reference
    )
}

@Test
func profileResolutionCoversUnboundUnknownAndForeign() throws {
    let profile = SpeakerLayoutProfiles.surround5_1
    let entityID = AnnotationEntityID()

    let resolved = profile.resolve(
        binding: try SpeakerRoleBinding(
            profileID: profile.profileID,
            profileVersion: profile.profileVersion,
            roleID: "L"
        ),
        entityID: entityID
    )
    guard case .resolved(_, let definition) = resolved else {
        Issue.record("expected resolved")
        return
    }
    #expect(definition.roleID == "L")

    let unknown = profile.resolve(
        binding: try SpeakerRoleBinding(
            profileID: profile.profileID,
            profileVersion: profile.profileVersion,
            roleID: "ZZ9"
        ),
        entityID: entityID
    )
    guard case .unknownRoleID = unknown else {
        Issue.record("expected unknownRoleID")
        return
    }

    let foreign = profile.resolve(
        binding: try SpeakerRoleBinding(
            profileID: "other.profile",
            profileVersion: "1.0.0",
            roleID: "L"
        ),
        entityID: entityID
    )
    guard case .foreignProfile = foreign else {
        Issue.record("expected foreignProfile")
        return
    }
}

@Test
func profileCardinalityFindsMissingAndOverMax() throws {
    let profile = SpeakerLayoutProfiles.stereo
    // No bindings → both required roles missing.
    let findings = profile.evaluateCardinality(boundRoleIDs: [])
    #expect(findings.count == 2)
    #expect(
        findings.contains(
            .missingRequiredRole(
                roleID: "L", expected: 1, observed: 0
            )
        )
    )

    // Two bindings to a max-1 role → over maximum.
    let over = profile.evaluateCardinality(
        boundRoleIDs: ["L", "L", "R"]
    )
    #expect(
        over.contains(
            .overMaximum(roleID: "L", maximum: 1, observed: 2)
        )
    )
}

@Test
func genericProfileSupportsMultiSubBindings() throws {
    let generic = SpeakerLayoutProfiles.generic
    let lfe = try #require(generic.roleDefinition(roleID: "LFE"))
    #expect(lfe.allowsMultipleBindings)
    #expect(lfe.maximumCount == nil)
    // Three LFE bindings are legal under the generic vocabulary.
    #expect(
        generic.evaluateCardinality(
            boundRoleIDs: ["LFE", "LFE", "LFE"]
        ).isEmpty
    )
}

@Test
func taskPlanLayoutProfileRoundTrips() throws {
    let plan = try HTDTCaptureTaskPlan(
        planID: "p1",
        planVersion: "1.0.0",
        projectRef: "project:x",
        roomName: "Lab",
        layoutProfile: SpeakerLayoutProfiles.stereo
    )
    let data = try JSONEncoder().encode(plan)
    let decoded = try JSONDecoder().decode(
        HTDTCaptureTaskPlan.self,
        from: data
    )
    #expect(
        decoded.layoutProfile?.profileID == "htdt.layout-stereo-2.0"
    )
}

@Test
func completenessEvaluatesProfileRoleBindings() throws {
    let profile = SpeakerLayoutProfiles.stereo
    let taskProfile = CaptureTaskProfile.layoutProfile(profile)

    // Binding-based requirements exist for each profile role plus
    // the standard MLP/screen requirements.
    let roleRequirements = taskProfile.requirements.filter {
        $0.match.kind == .annotationRoleBinding
    }
    #expect(roleRequirements.count == profile.roles.count)
    #expect(
        roleRequirements.allSatisfy {
            $0.match.profileID == profile.profileID
                && $0.match.profileVersion == profile.profileVersion
        }
    )

    // A bound entity satisfies the requirement; an unbound channel
    // token does not.
    let bound = try speakerEntity(
        binding: SpeakerRoleBinding(
            profileID: profile.profileID,
            profileVersion: profile.profileVersion,
            roleID: "L"
        )
    )
    let unbound = try speakerEntity()
    let boundReport = CaptureTaskCompletenessEvaluator.evaluate(
        profile: taskProfile,
        annotations: [bound],
        measurements: []
    )
    let boundRoleOutcome = try #require(
        boundReport.outcomes.first {
            $0.requirement.match.kind == .annotationRoleBinding
                && $0.requirement.match.value == "L"
        }
    )
    #expect(boundRoleOutcome.status == .satisfied)

    let unboundReport = CaptureTaskCompletenessEvaluator.evaluate(
        profile: taskProfile,
        annotations: [unbound],
        measurements: []
    )
    let unboundRoleOutcome = try #require(
        unboundReport.outcomes.first {
            $0.requirement.match.kind == .annotationRoleBinding
                && $0.requirement.match.value == "L"
        }
    )
    #expect(unboundRoleOutcome.status != .satisfied)
}

// MARK: - #337 external-authority dependency manifest

@Test
func manifestDeclaresEquipmentProfileAndPlanDependencies() throws {
    let catalog = try catalogSnapshot(
        entries: [
            HTDTEquipmentCatalogEntry(
                definitionID: "amp-1",
                version: "1.0.0",
                semanticSHA256: EvidenceSHA256(
                    String(repeating: "cd", count: 32)
                ),
                identityKind: .manufacturer,
                manufacturer: "Example Audio",
                model: "Monitor X",
                userLabel: nil
            ),
        ],
        context: catalogContext()
    )
    let profile = SpeakerLayoutProfiles.stereo
    let binding = try SpeakerRoleBinding(
        profileID: profile.profileID,
        profileVersion: profile.profileVersion,
        roleID: "L"
    )
    let entity = try speakerEntity(
        binding: binding,
        equipmentRef: equipmentRef()
    )
    let plan = try HTDTCaptureTaskPlan(
        planID: "plan-9",
        planVersion: "2.0.0",
        projectRef: "project:hq",
        roomName: "Lab"
    )
    let planHash = EvidenceIntegrity.sha256(
        of: Data("plan-bytes".utf8)
    )

    let manifest = try ExternalAuthorityDependencyBuilder.manifest(
        entities: [entity],
        catalog: catalog,
        taskPlan: plan,
        taskPlanSHA256: planHash,
        generatedAtUTC: "2026-09-20T00:00:00Z"
    )

    let kinds = Set(manifest.dependencies.map(\.kind))
    #expect(
        kinds == [
            .equipmentDefinition, .layoutProfile, .taskPlan,
        ]
    )

    let equipment = try #require(
        manifest.dependencies.first {
            $0.kind == .equipmentDefinition
        }
    )
    #expect(equipment.authorityID == "amp-1")
    #expect(equipment.authorityVersion == "1.0.0")
    // The pinned hash equals the exact hash the entity carries.
    #expect(
        equipment.authoritySHA256.description
            == String(repeating: "cd", count: 32)
    )
    #expect(equipment.required)
    // Portable resolution context carries catalog identity + model.
    #expect(
        equipment.resolutionContext?.catalogSnapshotID == "snap-42"
    )
    #expect(equipment.resolutionContext?.model == "Monitor X")
    #expect(
        equipment.resolutionContext?.catalogContentSHA256
            == catalog.contentSHA256
    )

    let layoutDep = try #require(
        manifest.dependencies.first {
            $0.kind == .layoutProfile
        }
    )
    #expect(layoutDep.authorityID == profile.profileID)
    #expect(
        layoutDep.authoritySHA256 == profile.contentSHA256
    )

    let planDep = try #require(
        manifest.dependencies.first {
            $0.kind == .taskPlan
        }
    )
    #expect(planDep.authorityID == "plan-9")
    #expect(!planDep.required)
}

@Test
func manifestUnresolvedAndCapabilityFailures() throws {
    let manifest = try ExternalAuthorityDependencyManifest(
        generatedAtUTC: "2026-09-20T00:00:00Z",
        dependencies: [
            ExternalAuthorityDependency(
                kind: .equipmentDefinition,
                authorityID: "amp-1",
                authorityVersion: "1.0.0",
                authoritySHA256: EvidenceSHA256(
                    String(repeating: "cd", count: 32)
                ),
                required: true,
                capabilityLoss: "model_lookup"
            ),
            ExternalAuthorityDependency(
                kind: .taskPlan,
                authorityID: "plan-9",
                authorityVersion: "2.0.0",
                authoritySHA256: EvidenceSHA256(
                    String(repeating: "ef", count: 32)
                ),
                required: false,
                capabilityLoss: "task_provenance"
            ),
        ]
    )

    // Nothing resolvable → the required dep fails its capability; the
    // optional one never fails the bundle.
    let failures = manifest.capabilityFailures(availableKeys: [])
    #expect(failures.count == 1)
    #expect(failures.first?.kind == .equipmentDefinition)

    // All resolved → no unresolved, no failures.
    let keys = Set(
        manifest.dependencies.map(\.identityKey)
    )
    #expect(manifest.unresolved(availableKeys: keys).isEmpty)
    #expect(
        manifest.capabilityFailures(availableKeys: keys).isEmpty
    )
}

@Test
func manifestRejectsDuplicateAuthorityIdentity() throws {
    let dep = try ExternalAuthorityDependency(
        kind: .equipmentDefinition,
        authorityID: "amp-1",
        authorityVersion: "1.0.0",
        authoritySHA256: EvidenceSHA256(
            String(repeating: "ab", count: 32)
        ),
        required: true
    )
    #expect(throws: ExternalAuthorityDependencyError.self) {
        _ = try ExternalAuthorityDependencyManifest(
            generatedAtUTC: "2026-09-20T00:00:00Z",
            dependencies: [dep, dep]
        )
    }
}

@Test
func manifestDocumentSchemaValidatesInBundle() throws {
    let manifest = try ExternalAuthorityDependencyManifest(
        generatedAtUTC: "2026-09-20T00:00:00Z",
        dependencies: [
            ExternalAuthorityDependency(
                kind: .layoutProfile,
                authorityID: "htdt.layout-stereo-2.0",
                authorityVersion: "1.0.0",
                authoritySHA256:
                    SpeakerLayoutProfiles.stereo.contentSHA256,
                required: true,
                capabilityLoss: "role_resolution"
            ),
        ]
    )
    let package = try ExternalAuthorityDependencyPackage(
        manifest: manifest
    )
    let root = try BundleValidationFixture.makeDirectory()
    defer { BundleValidationFixture.remove(root) }
    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                ExternalAuthorityDependencyPackage.path,
                package.data,
                "application/json"
            ),
        ]
    )
    _ = try BundleDirectoryValidator.validate(root: root)

    // Round-trip preserves every field.
    let decoded = try JSONDecoder().decode(
        ExternalAuthorityDependencyManifest.self,
        from: package.data
    )
    #expect(decoded == manifest)
}

@Test
func manifestRejectsMalformedJSONSchemaShape() throws {
    let bad = try BundleValidationFixture.canonical(
        .object([
            ("schema", .string("htdt.capture.authority-dependencies")),
            ("schema_version", .string("1.0.0")),
            ("generated_at", .string("not-a-time")),
            ("dependencies", .array([])),
        ])
    )
    let root = try BundleValidationFixture.makeDirectory()
    defer { BundleValidationFixture.remove(root) }
    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                ExternalAuthorityDependencyPackage.path,
                bad,
                "application/json"
            ),
        ]
    )
    #expect(throws: BundleDirectoryValidationError.self) {
        _ = try BundleDirectoryValidator.validate(root: root)
    }
}

// MARK: - #345 label-scan matching + provenance

@Test
func labelScanCandidatesRankCatalogAndSerial() throws {
    let entry = try catalogEntry(
        id: "amp-1",
        version: "1.0.0",
        hash: "ab"
    )
    let observations = [
        EquipmentLabelScanObservation(
            text: "amp-1@1.0.0",
            basis: .qrCode,
            confidence: 1.0
        ),
        EquipmentLabelScanObservation(
            text: "SN 7741-9912",
            basis: .ocr,
            confidence: 0.9
        ),
    ]
    let candidates = EquipmentLabelScanMatcher.candidates(
        from: observations,
        catalog: [entry]
    )
    let top = try #require(candidates.first)
    #expect(top.catalogSelectionKey == entry.selectionKey)
    #expect(top.confidence > 0.9)
    // The serial-shaped OCR token is a separate suggestion.
    #expect(
        candidates.contains {
            $0.serialOrAssetTag == "SN 7741-9912"
        }
    )
}

@Test
func labelScanManufacturerModelMatchOnly() throws {
    let entry = try catalogEntry(id: "amp-1")
    let observations = [
        EquipmentLabelScanObservation(
            text: "Example Audio",
            basis: .ocr,
            confidence: 0.9
        ),
        EquipmentLabelScanObservation(
            text: "Monitor X",
            basis: .ocr,
            confidence: 0.9
        ),
    ]
    let candidates = EquipmentLabelScanMatcher.candidates(
        from: observations,
        catalog: [entry]
    )
    #expect(
        candidates.contains {
            $0.catalogSelectionKey == entry.selectionKey
        }
    )
    #expect(
        candidates.contains {
            $0.manufacturer == "Example Audio"
                && $0.catalogSelectionKey == nil
        }
    )
}

@Test
func labelScanProvenanceRequiresPathRef() throws {
    #expect(throws: ExternalAuthorityDependencyError.self) {
        _ = try EquipmentLabelScanProvenance(
            algorithm: "vision-ocr-barcode",
            algorithmVersion: "1.0.0",
            evidenceRef: "bare/path.json",
            matchedRawStrings: []
        )
    }
    let provenance = try EquipmentLabelScanProvenance(
        algorithm: "vision-ocr-barcode",
        algorithmVersion: "1.0.0",
        evidenceRef: "path:evidence/frames/a.json",
        matchedRawStrings: ["SN-1"]
    )
    let encoded = try JSONEncoder().encode(provenance)
    let decoded = try JSONDecoder().decode(
        EquipmentLabelScanProvenance.self,
        from: encoded
    )
    #expect(decoded == provenance)
}

@Test
func identityRecordCarriesLabelScanProvenance() throws {
    let provenance = try EquipmentLabelScanProvenance(
        algorithm: "vision-ocr-barcode",
        algorithmVersion: "1.0.0",
        evidenceRef: "path:evidence/frames/a.json",
        matchedRawStrings: ["Monitor X"]
    )
    let record = try EquipmentIdentityRecord(
        entityID: AnnotationEntityID(),
        equipment: equipmentRef(),
        identityEvidenceRefs: ["path:evidence/frames/a.json"],
        serialOrAssetTag: "SN-1",
        labelScan: provenance,
        attestedPhysicalMatch: true
    )
    let encoded = try JSONEncoder().encode(record)
    let decoded = try JSONDecoder().decode(
        EquipmentIdentityRecord.self,
        from: encoded
    )
    #expect(decoded.labelScan == provenance)

    // Legacy records without label_scan still decode.
    let legacy = Data(
        """
        {
          "entity_id":"00000000-0000-4000-8000-000000000099",
          "equipment":{
            "authority_version":"o100c-equipment-definition-1",
            "equipment_id":"amp-1",
            "equipment_version":"1.0.0",
            "equipment_hash":"\(String(repeating: "cd", count: 32))"
          },
          "identity_evidence_refs":[],
          "serial_or_asset_tag":null,
          "attested_physical_match":false,
          "recorded_at_utc":"2026-09-20T00:00:00Z"
        }
        """.utf8
    )
    let decodedLegacy = try JSONDecoder().decode(
        EquipmentIdentityRecord.self,
        from: legacy
    )
    #expect(decodedLegacy.labelScan == nil)
}
