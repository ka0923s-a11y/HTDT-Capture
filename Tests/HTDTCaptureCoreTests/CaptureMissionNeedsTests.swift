import Foundation
import Testing
@testable import HTDTCaptureCore

// #364 §4: "This capture needs" — mission intent itemized in
// operator vocabulary: counts and optional flags, never raw schema
// identifiers.

@Test
func generalCaptureNeedsOnlyRoomGeometry() {
    let needs = CaptureMissionNeeds.needs(
        for: CaptureTaskProfile.geometryOnly
    )
    #expect(needs == [CaptureMissionNeeds.roomGeometry])
}

@Test
func roomAndListeningProfileListsListeningPosition() {
    let needs = CaptureMissionNeeds.needs(
        for: CaptureTaskProfile.roomAndListeningPosition
    )
    #expect(needs.contains(
        CaptureMissionNeed(
            kind: .annotationEntity,
            title: "Listening position",
            count: 1,
            isOptional: false
        )
    ))
}

@Test
func theaterProfileItemizesRolesAndMergesAlternatives() {
    let profile = CaptureTaskProfile.theaterLayout(
        speakerRoles: ["L", "C", "R"],
        subwooferCount: 1
    )
    let needs = CaptureMissionNeeds.needs(for: profile)

    #expect(needs.contains {
        $0.kind == .annotationEntity
            && $0.title == "Listening position"
    })
    // The screen-presence alternative group merges into one row.
    #expect(needs.contains {
        $0.title == "Display or Projection screen"
    })
    #expect(!needs.contains { $0.title == "Display" })
    let speakerNeeds = needs.filter { $0.kind == .speakerRole }
    #expect(speakerNeeds.count == 4)
    #expect(speakerNeeds.contains { $0.title == "Speaker — L" })
    #expect(speakerNeeds.contains { $0.title == "Speaker — LFE" })
    // Never a raw schema identifier.
    #expect(!needs.contains { $0.title.contains("_") })
}

@Test
func layoutProfileResolvesRoleNamesThroughVocabulary() {
    let profile = CaptureTaskProfile.layoutProfile(
        SpeakerLayoutProfiles.stereo
    )
    let needs = CaptureMissionNeeds.needs(for: profile)
    // Built-in role IDs resolve to their display names (#315).
    #expect(needs.contains { $0.title == "Speaker — Front left" })
    #expect(needs.contains { $0.title == "Speaker — Front right" })
}

@Test
func taskPlanNeedsAggregateCountedRows() throws {
    let plan = try HTDTCaptureTaskPlan(
        planID: "plan-1",
        planVersion: "1.0.0",
        projectRef: "proj-1",
        roomName: "Studio",
        entityChecklist: [
            try HTDTTaskPlanEntityItem(
                itemID: "sp-l",
                entityType: .speaker,
                requirement: .required,
                channelRole: .left
            ),
            try HTDTTaskPlanEntityItem(
                itemID: "sp-r",
                entityType: .speaker,
                requirement: .required,
                channelRole: .right
            ),
            try HTDTTaskPlanEntityItem(
                itemID: "mlp",
                entityType: .listeningPosition,
                requirement: .required
            ),
            try HTDTTaskPlanEntityItem(
                itemID: "sub",
                entityType: .subwoofer,
                requirement: .optional,
                channelRole: .lfe1
            ),
        ],
        measurementRequests: [
            try HTDTTaskPlanMeasurementItem(
                itemID: "m1",
                quantityType: "room_width",
                requirement: .required
            ),
            try HTDTTaskPlanMeasurementItem(
                itemID: "m2",
                quantityType: "room_width",
                requirement: .required
            ),
        ]
    )
    let needs = CaptureMissionNeeds.needs(for: plan)

    #expect(needs.contains(
        CaptureMissionNeed(
            kind: .annotationEntity,
            title: "Speaker — L",
            count: 1,
            isOptional: false
        )
    ))
    #expect(needs.contains {
        $0.title == "Listening position" && !$0.isOptional
    })
    #expect(needs.contains {
        $0.title == "Subwoofer — LFE1" && $0.isOptional
    })
    #expect(needs.contains(
        CaptureMissionNeed(
            kind: .measurement,
            title: "Room Width",
            count: 2,
            isOptional: false
        )
    ))
    // Item IDs never leak into operator vocabulary.
    #expect(!needs.contains {
        $0.title.contains("sp-") || $0.title.contains("mlp")
    })
}

@Test
func humanizedTokenSplitsUnderscores() {
    #expect(
        CaptureMissionNeeds.humanizedToken("FRONT_LEFT")
            == "Front Left"
    )
    #expect(CaptureMissionNeeds.humanizedToken("LFE1") == "LFE1")
    #expect(CaptureMissionNeeds.humanizedToken("L") == "L")
}
