import XCTest
@testable import HTDTCaptureCore

/// Issue bolph71656-ai/HTDT-Capture#409: the spatial survey pass walks accepted spatial
/// entities — RoomPlan surfaces/objects, mesh regions, annotation
/// entities — never synthesized views, and derives per-target states
/// from committed records.
final class SpatialSurveyModelTests: XCTestCase {

    private func roomPlan(
        id: String,
        category: String,
        isSurface: Bool
    ) -> RoomPlanBindableObject {
        RoomPlanBindableObject(
            identifier: id,
            category: category,
            isSurface: isSurface,
            worldFromObject: .identity,
            dimensionsMeters: Float3(1, 2, 0.1)
        )
    }

    private func entity(
        _ type: AnnotationEntityType,
        label: String
    ) throws -> CaptureAnnotationEntity {
        let isSpeaker =
            type == .speaker || type == .subwoofer
        return try CaptureAnnotationEntity(
            type: type,
            coordinateSpaceID: CoordinateSpaceID(),
            worldFromAnnotation: .identity,
            referencePointSemantics: .cabinetReferencePoint,
            label: label,
            placement: PlacementProvenance(method: .manualNumeric),
            orientation: isSpeaker
                ? OrientationAxes(
                    frontAxisLocal: .unit(0, 0, -1),
                    upAxisLocal: .unit(0, 1, 0)
                ) : nil,
            channelRole: isSpeaker
                ? ChannelRole(rawValue: "L") : nil
        )
    }

    private func model(
        roomPlanObjects: [RoomPlanBindableObject] = [],
        meshAnchorIDs: [UUID] = [],
        annotations: [CaptureAnnotationEntity] = [],
        authorities: TheaterAuthorityCollection? = nil,
        fieldEvidence: [FieldEvidenceRecord] = [],
        instruments: [MeasurementInstrumentProfile] = [],
        settingsObservations: [InstalledSettingsObservation] = [],
        wiringRoutes: [AsBuiltWiringRoute] = [],
        measurements: [CaptureMeasurement] = [],
        fieldNotes: [CaptureFieldNote] = [],
        revisitFlags: [ScanRevisitFlag] = [],
        taskPlan: HTDTCaptureTaskPlan? = nil,
        taskPlanStatus: CaptureTaskPlanStatusDocument? = nil,
        mode: SurveyMode = .all
    ) -> SpatialSurveyModel {
        SpatialSurveyModel(
            roomPlanObjects: roomPlanObjects,
            meshAnchorIDs: meshAnchorIDs,
            annotations: annotations,
            authorities: authorities,
            fieldEvidence: fieldEvidence,
            instruments: instruments,
            settingsObservations: settingsObservations,
            wiringRoutes: wiringRoutes,
            measurements: measurements,
            fieldNotes: fieldNotes,
            revisitFlags: revisitFlags,
            taskPlan: taskPlan,
            taskPlanStatus: taskPlanStatus,
            mode: mode
        )
    }

    private func entry(
        _ model: SpatialSurveyModel,
        _ targetID: String
    ) -> SurveyTargetEntry? {
        model.entries.first { $0.target.targetID == targetID }
    }

    // MARK: - Targets derive from accepted sources

    /// Every accepted source becomes a target with the issue's
    /// class/kind vocabulary — surfaces, openings, objects, semantic
    /// entities, mesh regions, and the room sentinel.
    func testTargetsDeriveFromAcceptedSources() throws {
        let speaker = try entity(.speaker, label: "Left main")
        let meshID = UUID()
        let survey = model(
            roomPlanObjects: [
                roomPlan(id: "wall-1", category: "wall", isSurface: true),
                roomPlan(id: "floor-1", category: "floor", isSurface: true),
                roomPlan(
                    id: "door-1",
                    category: "door(isOpen: true)",
                    isSurface: true
                ),
                roomPlan(
                    id: "obj-1",
                    category: "sofa",
                    isSurface: false
                ),
            ],
            meshAnchorIDs: [meshID],
            annotations: [speaker]
        )
        let wall = try XCTUnwrap(entry(survey, "roomplan:wall:wall-1"))
        XCTAssertEqual(wall.target.targetClass, .roomBoundary)
        XCTAssertEqual(wall.target.kind, .wall)
        XCTAssertEqual(wall.state, .notReviewed)

        let floor = try XCTUnwrap(entry(survey, "roomplan:floor:floor-1"))
        XCTAssertEqual(floor.target.kind, .floor)

        let door = try XCTUnwrap(entry(survey, "roomplan:door:door-1"))
        XCTAssertEqual(door.target.targetClass, .opening)
        XCTAssertTrue(door.target.kind.isOpeningKind)

        let object = try XCTUnwrap(entry(survey, "roomplan:object:obj-1"))
        XCTAssertEqual(object.target.targetClass, .roomObject)

        let entityEntry = survey.entries.first {
            $0.target.targetClass == .semanticEntity
        }
        XCTAssertEqual(entityEntry?.target.kind, .speaker)
        XCTAssertEqual(entityEntry?.target.label, "Left main")

        let mesh = survey.entries.first {
            $0.target.kind == .meshRegion
        }
        XCTAssertEqual(mesh?.target.targetClass, .feature)
        XCTAssertEqual(mesh?.target.targetID, "mesh:" + meshID.uuidString.lowercased())

        XCTAssertNotNil(entry(survey, "room"))
    }

    /// Opening categories classify by family prefix — CapturedRoom
    /// carries associated values in the category string.
    func testOpeningKinds() {
        for (category, expected) in [
            ("door(isOpen: true)", SurveyTargetKind.door),
            ("window", SurveyTargetKind.window),
            ("opening", SurveyTargetKind.opening),
        ] {
            let survey = model(
                roomPlanObjects: [
                    roomPlan(
                        id: "o-1", category: category, isSurface: true
                    ),
                ]
            )
            XCTAssertEqual(
                entry(survey, "roomplan:" + expected.rawValue + ":o-1")?.target.kind, expected
            )
        }
    }

    // MARK: - Coverage drives states

    /// A roomPlan object with its one expected family documented is
    /// reviewed; partially covered or uncovered targets stay
    /// unresolved. Coverage never comes from inferred intent — only
    /// records bound by identity tokens.
    func testCoverageDrivesState() throws {
        let object = roomPlan(
            id: "sofa-1", category: "sofa", isSurface: false
        )
        let empty = model(roomPlanObjects: [object])
        let emptyEntry = try XCTUnwrap(entry(empty, "roomplan:object:sofa-1"))
        XCTAssertEqual(emptyEntry.state, .notReviewed)
        XCTAssertEqual(
            emptyEntry.expectedFamilies, [.furnitureSemantics]
        )

        let furniture = try FurnitureSemanticConfirmation(
            binding: SurfaceRegionBinding(
                coordinateSpaceID: CoordinateSpaceID(),
                roomPlanObjectID: "sofa-1"
            ),
            category: .sofa,
            relevance: .movable,
            source: .userConfirmed
        )
        let covered = try XCTUnwrap(
            model(
                roomPlanObjects: [object],
                authorities: TheaterAuthorityCollection(
                    furnitureSemantics: [furniture]
                )
            )
        )
        let coveredEntry = try XCTUnwrap(entry(covered, "roomplan:object:sofa-1"))
        XCTAssertEqual(coveredEntry.state, .reviewed)
        XCTAssertEqual(
            coveredEntry.presentFamilies, [.furnitureSemantics]
        )
    }

    /// A boundary with only one of its expected families is
    /// partiallyDocumented — and isUnresolved.
    func testPartialCoverage() throws {
        let semantic = try SurfaceSemanticAuthority(
            label: "front wall",
            binding: SurfaceRegionBinding(
                coordinateSpaceID: CoordinateSpaceID(),
                roomPlanSurfaceID: "wall-1"
            ),
            hostClassification: .roomBoundary
        )
        let survey = model(
            roomPlanObjects: [
                roomPlan(id: "wall-1", category: "wall", isSurface: true),
            ],
            authorities: try TheaterAuthorityCollection(
                surfaceSemantics: [semantic]
            )
        )
        let wall = try XCTUnwrap(entry(survey, "roomplan:wall:wall-1"))
        XCTAssertEqual(wall.state, .partiallyDocumented)
        XCTAssertTrue(wall.state.isUnresolved)
    }

    // MARK: - Mission mapping

    /// A plan item's targetRef binds to the matching target — a
    /// required, pending item ranks the target first in the
    /// next-unresolved order and counts as a mission gap.
    func testMissionRequirementMapping() throws {
        let plan = try HTDTCaptureTaskPlan(
            planID: "plan-1",
            planVersion: "1",
            projectRef: "proj",
            roomName: "room",
            semanticTasks: [
                HTDTTaskPlanSemanticItem(
                    itemID: "task-1",
                    requirement: .required,
                    semanticKind: .surfaceSemantics,
                    targetRef: "roomplan:surface:wall-1",
                    label: "Check front wall"
                ),
            ]
        )
        let survey = model(
            roomPlanObjects: [
                roomPlan(id: "wall-1", category: "wall", isSurface: true),
                roomPlan(id: "wall-2", category: "wall", isSurface: true),
            ],
            taskPlan: plan
        )
        let wall = try XCTUnwrap(entry(survey, "roomplan:wall:wall-1"))
        XCTAssertTrue(wall.target.isMissionRequired)
        XCTAssertEqual(wall.target.missionItemIDs, ["task-1"])
        XCTAssertEqual(wall.pendingMissionItemIDs, ["task-1"])
        XCTAssertEqual(wall.state, .needsFollowUp)
        XCTAssertEqual(survey.summary.missionRequiredGapCount, 1)
        XCTAssertEqual(
            survey.nextUnresolved.first?.target.targetID, "roomplan:wall:wall-1"
        )
    }

    /// A completed plan item drops the pending flag — the target
    /// still carries its mission identity.
    func testCompletedMissionItemClearsPending() throws {
        let plan = try HTDTCaptureTaskPlan(
            planID: "plan-1",
            planVersion: "1",
            projectRef: "proj",
            roomName: "room",
            semanticTasks: [
                HTDTTaskPlanSemanticItem(
                    itemID: "task-1",
                    requirement: .required,
                    semanticKind: .surfaceSemantics,
                    targetRef: "wall-1"
                ),
            ]
        )
        let status = try CaptureTaskPlanStatusDocument(
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: CaptureSessionID(),
            planID: "plan-1",
            planVersion: "1",
            planSHA256: EvidenceIntegrity.sha256(of: Data("x".utf8)),
            items: [
                .init(itemID: "task-1", outcome: .completed),
            ]
        )
        let survey = model(
            roomPlanObjects: [
                roomPlan(id: "wall-1", category: "wall", isSurface: true),
            ],
            taskPlan: plan,
            taskPlanStatus: status
        )
        let wall = try XCTUnwrap(entry(survey, "roomplan:wall:wall-1"))
        XCTAssertTrue(wall.target.isMissionRequired)
        XCTAssertTrue(wall.pendingMissionItemIDs.isEmpty)
        XCTAssertEqual(wall.state, .notReviewed)
        XCTAssertEqual(survey.summary.missionRequiredGapCount, 0)
    }

    /// A required item whose targetRef matches nothing in the
    /// capture becomes an explicit `.unavailable` target — unknown
    /// is a state, not an absence.
    func testUnmatchedRequiredItemIsUnavailable() throws {
        let plan = try HTDTCaptureTaskPlan(
            planID: "plan-1",
            planVersion: "1",
            projectRef: "proj",
            roomName: "room",
            semanticTasks: [
                HTDTTaskPlanSemanticItem(
                    itemID: "task-missing",
                    requirement: .required,
                    semanticKind: .surfaceSemantics,
                    targetRef: "roomplan:surface:no-such-wall",
                    label: "Missing wall"
                ),
            ]
        )
        let survey = model(taskPlan: plan)
        let missing = try XCTUnwrap(
            entry(survey, "mission:task-missing")
        )
        XCTAssertEqual(missing.state, .unavailable)
        XCTAssertTrue(missing.state.isUnresolved)
        XCTAssertEqual(missing.pendingMissionItemIDs, ["task-missing"])
    }

    // MARK: - Filtered modes

    /// Mode filters change both expected families and relevance —
    /// records outside the mode don't satisfy it, and targets with
    /// nothing expected report `notApplicable` rather than a gap.
    func testModeFiltering() throws {
        let object = roomPlan(
            id: "sofa-1", category: "sofa", isSurface: false
        )
        let survey = model(
            roomPlanObjects: [
                roomPlan(id: "wall-1", category: "wall", isSurface: true),
                object,
            ],
            mode: .roomState
        )
        let wall = try XCTUnwrap(entry(survey, "roomplan:wall:wall-1"))
        // Wall keeps .roomState in room-state mode.
        XCTAssertEqual(wall.expectedFamilies, [.roomState])
        XCTAssertEqual(wall.state, .notReviewed)
        // The furniture target expects nothing in room-state mode.
        let sofa = try XCTUnwrap(entry(survey, "roomplan:object:sofa-1"))
        XCTAssertEqual(sofa.state, .notApplicable)
        XCTAssertFalse(sofa.state.isUnresolved)
    }

    // MARK: - Attention

    /// A needs-attention field note bound to a target's identity
    /// marks it needsFollowUp with the reason surfaced.
    func testFieldNoteAttentionMarksFollowUp() throws {
        let note = try CaptureFieldNote(
            captureRevisionID: CaptureRevisionID(),
            category: .followUp,
            text: "Wall shows cracking",
            needsAttention: true,
            bindingRefs: ["surface:wall-1"]
        )
        let survey = model(
            roomPlanObjects: [
                roomPlan(id: "wall-1", category: "wall", isSurface: true),
            ],
            fieldNotes: [note]
        )
        let wall = try XCTUnwrap(entry(survey, "roomplan:wall:wall-1"))
        XCTAssertEqual(wall.state, .needsFollowUp)
        XCTAssertFalse(wall.attentionReasons.isEmpty)
        XCTAssertEqual(
            survey.nextUnresolved.first?.target.targetID, "roomplan:wall:wall-1"
        )
    }

    // MARK: - Record families on the target

    /// Object-first presentation: the entry carries only the
    /// committed records bound to it — evidence refs ride along for
    /// the detail surface.
    func testEntryCarriesBoundRecords() throws {
        let evidence = try FieldEvidenceRecord(
            kind: .dimensionVerification,
            title: "Width check",
            targetRefs: ["surface:wall-1"],
            asset: nil,
            captureRevisionID: CaptureRevisionID()
        )
        let survey = model(
            roomPlanObjects: [
                roomPlan(id: "wall-1", category: "wall", isSurface: true),
            ],
            fieldEvidence: [evidence]
        )
        let wall = try XCTUnwrap(entry(survey, "roomplan:wall:wall-1"))
        XCTAssertEqual(wall.records.count, 1)
        XCTAssertEqual(wall.records[0].family, .fieldEvidence)
        XCTAssertFalse(wall.records[0].evidenceRefs.isEmpty)
    }
}
